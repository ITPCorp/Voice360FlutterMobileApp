import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:itp_voice/locator.dart';
import 'package:itp_voice/main.dart' show firebaseReady;
import 'package:itp_voice/models/get_message_threads_response_model/get_message_threads_response_model.dart'
    as thr;
import 'package:itp_voice/models/get_thread_messages_response_model/get_thread_messages_response_model.dart';
import 'package:itp_voice/notification_service.dart';
import 'package:itp_voice/routes.dart';
import 'package:itp_voice/cache/cache_service.dart';
import 'package:itp_voice/services/numbers_service.dart';
import 'package:itp_voice/services/threads_cache.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/get_contacts_reponse_model/contact_response.dart';
import '../repo/messages_repo.dart';
import '../repo/shares_preference_repo.dart';
import '../storage_keys.dart';
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

  Rxn<GetThreadMessagesResponseModel> _messages = Rxn();
  GetThreadMessagesResponseModel? get messages => _messages.value;

  TextEditingController messageController = TextEditingController();
  StreamSubscription? channelSubscription;

  bool socketConnected = false;
  Timer? reconnector;

  @override
  void onClose() {
    reconnector?.cancel();
    channelSubscription?.cancel();
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
    final cache = locator<ThreadsCache>();
    if (forceRefresh) {
      await cache.invalidateAndRefresh(myNumber);
    }
    final hit = cache.findThreadForPeer(
      fromNumber: myNumber,
      peerNumber: threadNumber!,
    );
    if (hit != null) {
      threadId.value = hit.pk?.toString();
      return;
    }
    // No cached match yet — block on a single fetch and try again.
    try {
      await cache.get(myNumber);
      final retry = cache.findThreadForPeer(
        fromNumber: myNumber,
        peerNumber: threadNumber!,
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
    _connectWebsocket();
    _wireFcmListener();
  }

  void _connectWebsocket() {
    channelSubscription?.cancel();
    reconnector?.cancel();
    channelSubscription = messageSocketConnect().listen(
      (body) {
        final tid = threadId.value;
        if (tid != null) {
          try {
            repo.markAsRead(tid, myNumber);
          } catch (_) {}
        }
        handleWebsocketResponce(body);
      },
      onDone: () {
        socketConnected = false;
        reconnector = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
          if (socketConnected) return;
          socketConnected = true;
          channelSubscription?.cancel();
          channelSubscription = messageSocketConnect().listen(
            (body) {
              final tid = threadId.value;
              if (tid != null) {
                try {
                  repo.markAsRead(tid, myNumber);
                } catch (_) {}
              }
              handleWebsocketResponce(body);
            },
            onDone: () => socketConnected = false,
          );
        });
      },
    );
  }

  void _wireFcmListener() {
    if (!firebaseReady) return;
    FirebaseMessaging.onMessage.listen((message) {
      if (message.notification == null) return;
      if (Get.currentRoute != Routes.CHAT_SCREEN_ROUTE) {
        LocalNotificationService.createanddisplaynotification(message);
      }
    });
  }

  void handleWebsocketResponce(dynamic bod) {
    dynamic body = jsonDecode(bod);
    try {
      if (body['payload'] == 'Unauthorized') {
        CustomToast.showToast('Chat connection failed (unauthorized)', true);
        return;
      }
      socketConnected = true;
      if (body['message_type'] == 'sms-status' || body['message_type'] == 'sms') {
        final payload = jsonDecode(body['payload']);
        if (payload['message_status'] != null) {
          final providerId = payload['message_provider_id'];
          final index = messages?.result?.messages?.indexWhere(
                (e) => e.messageProviderId == providerId,
              ) ??
              -1;
          if (index != -1 && _messages.value != null) {
            _messages.value!.result!.messages![index].isDelivered = true;
          } else {
            try {
              if (payload['from_number'] == threadNumber) {
                _messages.value?.result?.messages?.insert(
                  0,
                  Messages.fromPayload(payload as Map<String, dynamic>),
                );
              }
            } catch (_) {}
          }
          isLoading.refresh();
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('WS parse error: $e');
    }
  }

  Stream messageSocketConnect() {
    final apiId = SharedPreferencesMethod.getString(StorageKeys.API_ID);
    final connection = WebSocketChannel.connect(
      Uri.parse('wss://websockets.api.itp247.com/sms'),
    );
    final token = SharedPreferencesMethod.storage.getString(StorageKeys.REFRESH_TOKEN);
    connection.sink.add(jsonEncode({
      'action': 'login',
      'payload': {
        'account_id': '$apiId',
        'jwt_token': token,
        'phone_number': myNumber,
      },
    }));
    return connection.stream;
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

  Future<void> sendMessage({bool isImage = false}) async {
    if (myNumber.isEmpty) {
      CustomToast.showToast(
        'No outbound number assigned. Open Messages to choose one.',
        true,
      );
      return;
    }

    final peer = threadNumber;
    if (peer == null || peer.isEmpty) {
      CustomToast.showToast('No recipient.', true);
      return;
    }

    // Image path
    if (isImage) {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (image == null) return;
      isMessageLoading.value = true;
      try {
        final to = _toListJson([peer]);
        final message =
            await repo.sendMessage(myNumber, '', to, image.path);
        if (message != null) {
          message.isDelivered = false;
          await _onSendSucceeded(message);
        } else {
          CustomToast.showToast('Please check your internet connection', true);
        }
      } finally {
        isMessageLoading.value = false;
      }
      return;
    }

    // Text path
    final text = messageController.text.trim();
    if (text.isEmpty || isMessageLoading.value) return;
    isMessageLoading.value = true;
    try {
      final to = _toListJson([peer]);
      final message = await repo.sendMessage(myNumber, text, to);
      messageController.clear();
      if (message != null) {
        message.isDelivered = false;
        await _onSendSucceeded(message);
      } else {
        CustomToast.showToast('Please check your internet connection', true);
      }
    } finally {
      isMessageLoading.value = false;
    }
  }

  /// Insert a freshly-sent message into the local view. If we were in compose
  /// mode, this is the moment to promote ourselves to thread mode — find the
  /// newly-created thread and switch over.
  Future<void> _onSendSucceeded(Messages message) async {
    if (_messages.value != null) {
      _messages.value!.result!.messages!.insert(0, message);
      isLoading.refresh();
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

    // Now ask the server for the real thread id so subsequent reads/sends and
    // websocket pairing work normally. Force a refresh — the thread we just
    // created won't be in the cached snapshot.
    await _findExistingThreadForPeer(forceRefresh: true);
    if (threadId.value != null) {
      _loadThreadMode();
    }
  }

  String _toListJson(List<String> numbers) =>
      '{"list": ["${numbers.join(',')}"]}';
}
