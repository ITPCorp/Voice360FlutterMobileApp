import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:itp_voice/helpers/group_chat.dart';
import 'package:itp_voice/locator.dart';
import 'package:itp_voice/models/get_message_threads_response_model/get_message_threads_response_model.dart'
    as thr;
import 'package:itp_voice/models/get_thread_messages_response_model/get_thread_messages_response_model.dart';
import 'package:itp_voice/cache/cache_service.dart';
import 'package:itp_voice/services/contact_resolver.dart';
import 'package:itp_voice/services/global_socket_service.dart';
import 'package:itp_voice/services/numbers_service.dart';
import 'package:itp_voice/services/threads_cache.dart';

import '../models/get_contacts_reponse_model/contact_response.dart';
import '../repo/messages_repo.dart';
import '../widgets/custom_toast.dart';

/// Chat controller — supports two modes:
///
/// **Thread mode**: opened from the Messages list. Arguments are
/// `[threadId, myNumber, peerNumber]`. Fetches existing messages, marks read,
/// connects to the SMS websocket. This is the original behaviour.
///
/// **Compose mode**: opened from a contact's "Message" action without an
/// existing thread. Arguments are `[null, peerNumber, contactOrNull]`. The
/// controller looks for an existing thread for that peer; if found, switches
/// into thread mode automatically. If not, the user lands in an empty chat
/// view and can type the first message. On send, the new thread is created
/// server-side and we promote ourselves to thread mode.
class ChatController extends GetxController {
  RxBool isLoading = false.obs;
  RxBool isMessageLoading = false.obs;
  MessagesRepo repo = MessagesRepo();

  /// The number the user is sending FROM (their assigned virtual number).
  /// In compose mode this comes from arguments[1] as the peer's number — we
  /// normalize below. Reactive so the composer dropdown can rebind it on the
  /// fly when the user has multiple chat numbers.
  RxString myNumberRx = ''.obs;
  String get myNumber => myNumberRx.value;
  set myNumber(String v) => myNumberRx.value = v;

  /// The peer's phone number (the other side of the conversation).
  String? threadNumber;

  /// Saved-contact info, if the chat was opened from a contact tap. Lets us
  /// render a nicer header even in compose mode.
  Contact? contact;

  /// Existing thread id. `null` until we either:
  ///   - load the messages screen with a known thread, OR
  ///   - find an existing thread for the peer during init, OR
  ///   - send the first message in compose mode and the server returns one.
  RxnString threadId = RxnString();

  bool get isCompose => threadId.value == null;

  /// Available outbound numbers (the user's chat-enabled DIDs). Read straight
  /// from the cached NumbersService — already loaded by the splash flow.
  List<String> get availableFromNumbers =>
      locator<NumbersService>().chatNumbers;

  /// Change the "from" number in compose mode. If a thread exists for this
  /// peer under the newly-chosen number, we'll switch into thread mode.
  Future<void> changeFromNumber(String newNumber) async {
    if (newNumber.isEmpty || newNumber == myNumber) return;
    myNumber = newNumber;
    // In thread mode the peer is bound to the existing thread on the server,
    // so we don't switch threads — but we still update outbound-sender.
    if (threadId.value != null) return;
    await _findExistingThreadForPeer();
    if (threadId.value != null) {
      _loadThreadMode();
    }
  }

  final Rxn<GetThreadMessagesResponseModel> _messages = Rxn();
  GetThreadMessagesResponseModel? get messages => _messages.value;

  TextEditingController messageController = TextEditingController();

  /// Everyone in the thread as [ChatMember]s (us included), names resolved.
  List<ChatMember> get members =>
      ContactResolver.membersOf(_messages.value?.result?.participants);

  /// More than one peer besides our number.
  bool get isGroup => isGroupThread(members);

  /// Subscription to the global notification socket (lifetime = chat screen).
  StreamSubscription<GlobalSocketEvent>? _socketSub;

  /// Socket events already applied to this thread, see [SmsEventDeduper].
  final SmsEventDeduper _seenEvents = SmsEventDeduper();

  @override
  void onClose() {
    _socketSub?.cancel();
    super.onClose();
  }

  @override
  void onInit() {
    super.onInit();
    _parseArguments();
    // Hydrate from the on-disk message cache synchronously, BEFORE the
    // first build runs. Otherwise the screen would render the seeded
    // participants stub (which has zero messages) and briefly show the
    // empty state until fetchChat's disk hydration completes.
    _hydrateMessagesFromDisk();
    _bootstrap();
  }

  void _hydrateMessagesFromDisk() {
    final tid = threadId.value;
    if (tid == null) return;
    if (!AppCache.instance.isReady) return;
    final cached = AppCache.instance.messages.read(tid);
    if (cached == null) return;
    _mergeFreshResponse(cached);
  }

  void _parseArguments() {
    final args = Get.arguments;
    if (args is! List) return;

    // arg 0: threadId (String|int) or null/empty in compose mode
    final raw0 = args.isNotEmpty ? args[0] : null;
    final firstArg = raw0?.toString();
    if (firstArg != null && firstArg.isNotEmpty && firstArg != 'null') {
      threadId.value = firstArg;
    }

    // arg 1: peer number (a String). In thread mode this is the user's own
    // number when called from messages list; in compose mode it's the peer.
    // We disambiguate below in _bootstrap().
    final raw1 = args.length > 1 ? args[1] : null;
    final secondArg = raw1?.toString() ?? '';

    // arg 2: peer number OR contact OR null. If a String, treat as peer.
    final raw2 = args.length > 2 ? args[2] : null;
    if (raw2 is Contact) {
      contact = raw2;
    } else if (raw2 is String && raw2.isNotEmpty && raw2 != 'null') {
      threadNumber = raw2;
    }

    // arg 3 (optional): the full MessageThreads object from the list. Lets
    // us render the contact name immediately on the chat header — before the
    // network fetch returns. We do this by seeding a stub
    // GetThreadMessagesResponseModel with the embedded participants so
    // _peerDisplay() picks up `participant.contact` on the first frame.
    final raw3 = args.length > 3 ? args[3] : null;
    if (raw3 is thr.MessageThreads) {
      _seedFromThread(raw3);
    }

    // Pick the user's own number from the cached chat numbers; the second arg
    // is most often this when opened from the messages list, but in compose
    // mode it's the peer.
    final myNumbers = locator<NumbersService>().chatNumbers;
    if (secondArg.isNotEmpty &&
        myNumbers.any((n) => n.replaceAll(RegExp(r'\D'), '') ==
            secondArg.replaceAll(RegExp(r'\D'), ''))) {
      myNumber = secondArg;
    } else {
      // Compose entry: `secondArg` is the peer; assume the first chat number
      // is the sender. Settings lets users change it later.
      threadNumber ??= (secondArg.isNotEmpty ? secondArg : null);
      myNumber = myNumbers.isNotEmpty ? myNumbers.first : '';
    }

    // Last-resort: derive peer from contact.
    threadNumber ??= contact?.phone;

    // arg 4 (optional): recipients of a new group conversation, picked on
    // the New Message screen. Seed them as participants so the header,
    // reply-all list and opt-out check work before the thread exists.
    final raw4 = args.length > 4 ? args[4] : null;
    if (raw4 is List && threadId.value == null) {
      final picked = otherMembers(raw4.whereType<ChatMember>());
      if (picked.length > 1) _seedCompose(picked);
    }
  }

  /// True when this chat was opened to start a new group (compose mode).
  bool composingGroup = false;

  void _seedCompose(List<ChatMember> picked) {
    composingGroup = true;
    threadNumber = picked.first.number;
    _messages.value = GetThreadMessagesResponseModel(
      result: Result(messages: [], participants: [
        Participants(number: myNumber, isSelf: true),
        for (final m in picked)
          Participants(
            number: m.number,
            isSelf: false,
            contact: (m.firstname == null && m.lastname == null && !m.dndSms)
                ? null
                : ParticipantContact(
                    firstname: m.firstname,
                    lastname: m.lastname,
                    phone: m.number,
                    dndSms: m.dndSms,
                  ),
          ),
      ]),
    );
  }

  /// Bridge from the threads-list participant shape (`thr.Participants`) to
  /// the thread-messages participant shape (`Participants`). The two are
  /// structurally identical, but live in different libraries.
  void _seedFromThread(thr.MessageThreads t) {
    final ps = t.participants;
    if (ps == null || ps.isEmpty) return;
    final bridged = <Participants>[
      for (final p in ps)
        Participants(
          messageThreadId: p.messageThreadId,
          pk: p.pk,
          number: p.number,
          isSelf: p.isSelf,
          contact: p.contact == null
              ? null
              : ParticipantContact(
                  pk: p.contact!.pk,
                  firstname: p.contact!.firstname,
                  lastname: p.contact!.lastname,
                  phone: p.contact!.phone,
                  email: p.contact!.email,
                  dndSms: p.contact!.dndSms,
                ),
        ),
    ];
    _messages.value = GetThreadMessagesResponseModel(
      result: Result(messages: const [], participants: bridged),
    );
    // Also pre-fill threadNumber from the peer if we don't have one yet.
    threadNumber ??= bridged
        .firstWhere(
          (p) => p.isSelf != true,
          orElse: () => Participants(),
        )
        .number;
  }

  Future<void> _bootstrap() async {
    if (threadId.value != null) {
      _loadThreadMode();
    } else {
      await _findExistingThreadForPeer();
      if (threadId.value != null) {
        _loadThreadMode();
      } else {
        // Stay in compose mode. No fetch, no socket, no read marks.
        isLoading.value = false;
      }
    }
  }

  /// Search the user's threads for one that already has `threadNumber` as a
  /// participant. Promotes us into thread mode if found.
  Future<void> _findExistingThreadForPeer({bool forceRefresh = false}) async {
    if (threadNumber == null || threadNumber!.isEmpty || myNumber.isEmpty) {
      return;
    }
    // A group is found by its whole member set, a 1:1 by the one peer.
    final peers = recipientNumbers;
    final cache = locator<ThreadsCache>();
    if (forceRefresh) {
      await cache.invalidateAndRefresh(myNumber);
    }
    final hit = cache.findThreadForPeers(
      fromNumber: myNumber,
      peerNumbers: peers,
    );
    if (hit != null) {
      threadId.value = hit.pk?.toString();
      return;
    }
    // No cached match yet — block on a single fetch and try again.
    try {
      await cache.get(myNumber);
      final retry = cache.findThreadForPeers(
        fromNumber: myNumber,
        peerNumbers: peers,
      );
      if (retry != null) {
        threadId.value = retry.pk?.toString();
      }
    } catch (e) {
      // ignore: avoid_print
      print('Thread lookup failed: $e');
    }
  }

  void _loadThreadMode() {
    fetchChat();
    final tid = threadId.value;
    if (tid != null) {
      repo.markAsRead(tid, myNumber);
    }
    _subscribeToGlobalSocket();
    // FCM banner display + tap routing is handled by PushService now.
  }

  /// Subscribe to SMS events from the platform-wide notification socket
  /// and route ones matching this thread into the visible message list.
  /// Mirrors the web client's RealChatContainer.jsx event handling.
  void _subscribeToGlobalSocket() {
    _socketSub?.cancel();
    final socket = locator<GlobalSocketService>();
    // Ensure the socket is up. Idempotent — does nothing if already connected.
    socket.connect();
    _socketSub = socket.events.listen(_handleSocketEvent);
  }

  void _handleSocketEvent(GlobalSocketEvent event) {
    if (!event.isAnySms) return;
    final reader = SmsEventReader(event);

    // Filter to this thread. owner_number says which of our numbers the
    // event is for, thread_id / participants say which conversation (a group
    // and a 1:1 with the same person are different threads). Old payloads
    // without those fall back to the single peer: from_number on
    // sms.received, the recipient on sms.sent.
    final myTid = threadId.value;
    final peer = event.isSmsSent ? reader.toNumber : reader.fromNumber;
    final matchesThisThread = smsEventBelongsToThread(
      myNumber: myNumber,
      ownerNumber: reader.ownerNumberFor(myNumber),
      eventThreadId: reader.threadId,
      threadId: myTid,
      eventParticipants: reader.participantNumbers,
      legacyPeer: peer,
      threadOthers: recipientNumbers,
    );
    if (!matchesThisThread) return;

    // A group send gets one delivery receipt per recipient, all for the same
    // message. Handle the first, drop the rest.
    if (_seenEvents.isRepeat(
        event.innerType ?? '', [reader.messagePk, reader.providerId])) {
      return;
    }

    final pk = reader.messagePk;
    final providerId = reader.providerId; // sms_id from the WS event
    final body = reader.body ?? '';
    final list = _messages.value?.result?.messages;

    int existingIdx = -1;
    if (list != null) {
      existingIdx = list.indexWhere((m) {
        // 1. Exact id match (when the WS payload includes one).
        if (pk != null && m.pk == pk) return true;
        // 2. Exact provider-id match (after the first sms.sent has populated it).
        if (providerId != null && m.messageProviderId == providerId) {
          return true;
        }
        // 3. For sms.sent: fingerprint-match against an outbound `pending`
        //    bubble we just POSTed. Same body, undelivered, very recent.
        //    The POST response carries no provider id and the WS event
        //    carries no pk, so this is the only way to bind them.
        if (event.isSmsSent &&
            m.messageProviderId == null &&
            (m.messageStatus?.toLowerCase() == 'pending') &&
            (m.messageBody ?? '') == body) {
          return true;
        }
        return false;
      });
    }

    if (existingIdx != -1) {
      final msg = list![existingIdx];
      msg.isDelivered = true;
      if (providerId != null) msg.messageProviderId = providerId;
      final newStatus = reader.status ?? (event.isSmsSent ? 'delivered' : null);
      if (newStatus != null) msg.messageStatus = newStatus;
      _persistMessagesToCache();
      isLoading.refresh();
      return;
    }

    // No match → insert as a fresh bubble (typical for sms.received).
    try {
      final legacy = reader.toLegacyPayload();
      final inserted = Messages.fromPayload(legacy);
      if (pk != null) inserted.pk = pk;
      if (providerId != null) inserted.messageProviderId = providerId;
      list?.insert(0, inserted);
      _persistMessagesToCache();
      isLoading.refresh();
    } catch (e) {
      // ignore: avoid_print
      print('Socket insert failed: $e');
    }

    // Best-effort mark-read while we're looking at the thread.
    if (myTid != null) {
      try {
        repo.markAsRead(myTid, myNumber);
      } catch (_) {}
    }
  }

  void _persistMessagesToCache() {
    final tid = threadId.value;
    if (tid == null) return;
    if (!AppCache.instance.isReady) return;
    if (_messages.value == null) return;
    AppCache.instance.messages.write(tid, _messages.value!);
  }

  RxBool loadTitle = false.obs;

  Future<void> fetchChat() async {
    final tid = threadId.value;
    if (tid == null) return;

    // Hydrate from disk first — renders the conversation instantly while we
    // refresh in the background. Important: we hydrate even when we already
    // have a stub from _seedFromThread (participants but no messages),
    // because the stub doesn't include the actual message history. The
    // disk cache does — its messages get merged on top of the seed.
    final hasMessages =
        (_messages.value?.result?.messages?.isNotEmpty ?? false);
    if (!hasMessages && AppCache.instance.isReady) {
      final cached = AppCache.instance.messages.read(tid);
      if (cached != null) {
        _mergeFreshResponse(cached);
      }
    }

    // Show full-screen spinner only when there's truly nothing to render
    // (no seeded participants AND no cached messages).
    isLoading.value = (_messages.value?.result?.messages?.isEmpty ?? true);
    final res = await repo.getThreadMessages(tid, myNumber);
    if (res is GetThreadMessagesResponseModel) {
      _mergeFreshResponse(res);
      if (AppCache.instance.isReady) {
        AppCache.instance.messages.write(tid, _messages.value!);
      }
      if (threadNumber == null) {
        threadNumber = _messages.value?.result?.participants
            ?.firstWhere((p) => p.isSelf != true,
                orElse: () => Participants())
            .number;
        loadTitle.value = !loadTitle.value;
      }
    }
    isLoading.value = false;
  }

  /// Merge a fresh server response with whatever we've already got
  /// in-memory. The big concern: the server's thread-messages endpoint
  /// sometimes returns participants WITHOUT the embedded `contact` block
  /// (the contact info only seems to be on the threads-list endpoint).
  /// If we trust the server response wholesale we'd lose the name we seeded.
  /// So: replace messages, but for each participant keep the existing
  /// `contact` if the fresh one is null.
  void _mergeFreshResponse(GetThreadMessagesResponseModel res) {
    final existing = _messages.value;
    if (existing == null) {
      _messages.value = res;
      return;
    }
    // Build a number→existing-contact map so we can patch the fresh
    // participants with any contact info we already had.
    final byNumber = <String, ParticipantContact>{};
    for (final p in existing.result?.participants ?? const <Participants>[]) {
      if (p.contact == null || p.number == null) continue;
      byNumber[p.number!] = p.contact!;
    }
    final patched = <Participants>[
      for (final p in res.result?.participants ?? const <Participants>[])
        Participants(
          messageThreadId: p.messageThreadId,
          pk: p.pk,
          number: p.number,
          isSelf: p.isSelf,
          contact: p.contact ?? byNumber[p.number ?? ''],
        ),
    ];
    _messages.value = GetThreadMessagesResponseModel(
      result: Result(
        messages: res.result?.messages ?? const [],
        participants: patched.isEmpty
            ? existing.result?.participants
            : patched,
      ),
      errors: res.errors,
      error: res.error,
      message: res.message,
      pageSize: res.pageSize,
      nextStartKey: res.nextStartKey,
      startKey: res.startKey,
    );
  }

  /// Who a send from this screen goes to. In a group thread that is every
  /// other participant (reply-all, like the web's getReplyNumbers); in a 1:1
  /// it is the one peer.
  List<String> get recipientNumbers {
    final ms = members;
    if (isGroupThread(ms)) return replyNumbers(ms);
    final peer = threadNumber;
    return (peer == null || peer.isEmpty) ? const [] : [peer];
  }

  Future<void> sendMessage({bool isImage = false}) async {
    if (myNumber.isEmpty) {
      CustomToast.showToast(
        'No outbound number assigned. Open Messages to choose one.',
        true,
      );
      return;
    }

    final to = recipientNumbers;
    if (to.isEmpty) {
      CustomToast.showToast('No recipient.', true);
      return;
    }
    final group = to.length > 1;
    // Carrier cap and opted-out members, checked before the request goes
    // out (the web fails the bubble with the same reason).
    if (group) {
      final reason = groupSendBlockReason(members);
      if (reason != null) {
        CustomToast.showToast(reason, true);
        return;
      }
    } else if (contact?.dndSms == true ||
        optedOutMembers(members).isNotEmpty) {
      CustomToast.showToast(
        'This contact has opted out of SMS. You cannot send messages to '
        'this contact.',
        true,
      );
      return;
    }

    String? imagePath;
    String text = '';
    if (isImage) {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (image == null) return;
      imagePath = image.path;
    } else {
      text = messageController.text.trim();
      if (text.isEmpty) return;
    }
    if (isMessageLoading.value) return;

    isMessageLoading.value = true;
    try {
      // One POST with the whole recipient list: voice-api keys the thread by
      // the full participant set and sends a single group MMS.
      final message = await repo.sendMessage(
          myNumber, text, toNumbersListJson(to), imagePath);
      if (!isImage) messageController.clear();
      if (message != null) {
        message.isDelivered = false;
        await _onSendSucceeded(message);
      } else {
        final body = repo.lastSendErrorBody;
        final reason = (group || isTooManyRecipientsError(body))
            ? sendErrorMessage(body)
            : '';
        CustomToast.showToast(
          reason.isNotEmpty
              ? reason
              : (body != null
                  ? 'Message not sent.'
                  : 'Please check your internet connection'),
          true,
        );
      }
    } finally {
      isMessageLoading.value = false;
    }
  }

  /// Insert a freshly-sent message into the local view. If we were in compose
  /// mode, this is the moment to promote ourselves to thread mode — find the
  /// newly-created thread and switch over.
  Future<void> _onSendSucceeded(Messages message) async {
    // The send response has no message_participant; it is ours.
    message.messageParticipant ??= myNumber;
    final list = _messages.value?.result?.messages;
    if (list != null) {
      // A delivery receipt can beat the POST response and already have put
      // this message on screen. Update that bubble instead of adding a
      // second one, and don't let the POST's "sent" walk back a final
      // delivered/failed status.
      final idx = indexOfMessagePk<Messages>(list, message.pk, (m) => m.pk);
      if (idx != -1) {
        final existing = list[idx];
        final keep = kFinalStatuses
            .contains(existing.messageStatus?.toLowerCase() ?? '');
        if (!keep) {
          existing.messageStatus = message.messageStatus;
          existing.isDelivered = message.isDelivered;
        }
        existing.messageMmsMedia ??= message.messageMmsMedia;
      } else {
        list.insert(0, message);
      }
      _persistMessagesToCache();
      isLoading.refresh();
      // New group: the stub had no thread yet. The send response names it.
      if (isCompose) await _promoteToThread(message);
      return;
    }
    // Compose mode: there's no in-memory thread yet. Bootstrap a minimal
    // response so the UI renders the first bubble immediately.
    final newResult = Result(
      messages: [message],
      participants: [
        Participants(number: myNumber, isSelf: true),
        Participants(number: threadNumber, isSelf: false),
      ],
    );
    _messages.value = GetThreadMessagesResponseModel(result: newResult);
    isLoading.refresh();
    await _promoteToThread(message);
  }

  /// Leave compose mode once the first message created the thread. The send
  /// response carries message_thread_id; older servers that don't get the
  /// old path, a forced threads refresh and a lookup by peer(s).
  Future<void> _promoteToThread(Messages sent) async {
    final tid = sent.messageThreadId;
    if (tid != null) {
      threadId.value = tid.toString();
    } else {
      await _findExistingThreadForPeer(forceRefresh: true);
    }
    if (threadId.value != null) {
      composingGroup = false;
      _persistMessagesToCache();
      _loadThreadMode();
    }
  }
}
