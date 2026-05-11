import 'package:itp_voice/models/call_history_model.dart';
import 'package:itp_voice/models/get_contacts_reponse_model/contact_response.dart';
import 'package:itp_voice/models/get_message_threads_response_model/get_message_threads_response_model.dart'
    as thr;
import 'package:itp_voice/models/get_thread_messages_response_model/get_thread_messages_response_model.dart'
    as msg;
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory toggle that swaps API responses with curated fake data so we
/// can take Play Store / App Store screenshots without leaking real PII.
///
/// Toggle from the Debug screen (7-tap profile avatar). Persists across
/// launches via SharedPreferences so screenshots survive cold-start.
class DemoModeService {
  DemoModeService._();
  static final DemoModeService instance = DemoModeService._();

  static const _prefKey = 'demo_mode_enabled';

  bool _enabled = false;
  bool get enabled => _enabled;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefKey) ?? false;
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
  }

  static const String demoFromNumber = '+15555550100';

  static final List<_FakeContact> _contacts = [
    _FakeContact('Alex Chen', '+15555550101'),
    _FakeContact('Jordan Rivera', '+15555550102'),
    _FakeContact('Sam Patel', '+15555550103'),
    _FakeContact('Taylor Brooks', '+15555550104'),
    _FakeContact('Morgan Lee', '+15555550105'),
    _FakeContact('Casey Nguyen', '+15555550106'),
    _FakeContact('Riley Davis', '+15555550107'),
    _FakeContact('Quinn Foster', '+15555550108'),
  ];

  // ──────────────────────────────────────────────────────────────────
  // Threads list (Messages tab).
  // ──────────────────────────────────────────────────────────────────

  thr.GetMessageThreadsResponseModel fakeThreadsResponse() {
    final now = DateTime.now();
    final threads = <thr.MessageThreads>[
      _thread(9001, _contacts[0], 'Sounds good, see you at 3!',
          now.subtract(const Duration(minutes: 8)), 0),
      _thread(9002, _contacts[1], 'Did the new feature get pushed yet?',
          now.subtract(const Duration(minutes: 42)), 2),
      _thread(9003, _contacts[2], 'Thanks for the quick turnaround.',
          now.subtract(const Duration(hours: 3)), 0),
      _thread(9004, _contacts[3], 'Can you forward me the invoice?',
          now.subtract(const Duration(hours: 5, minutes: 15)), 1),
      _thread(9005, _contacts[4], 'On my way!',
          now.subtract(const Duration(hours: 8)), 0),
      _thread(9006, _contacts[5], 'No worries. Talk soon.',
          now.subtract(const Duration(days: 1, hours: 2)), 0),
      _thread(9007, _contacts[6], 'Got it 👍',
          now.subtract(const Duration(days: 2)), 0),
    ];
    final r = thr.GetMessageThreadsResponseModel();
    r.result = thr.Result(messageThreads: threads);
    return r;
  }

  thr.MessageThreads _thread(int pk, _FakeContact peer, String lastMessage,
      DateTime when, int unread) {
    return thr.MessageThreads(
      pk: pk,
      lastMessage: lastMessage,
      lastUpdated: when.toIso8601String(),
      unreadMessages: unread,
      threadRead: unread == 0,
      participants: [
        thr.Participants(
          messageThreadId: pk.toString(),
          pk: 1,
          number: demoFromNumber,
          isSelf: true,
        ),
        thr.Participants(
          messageThreadId: pk.toString(),
          pk: 2,
          number: peer.number,
          isSelf: false,
          contact: thr.ParticipantContact(
            pk: 100 + pk,
            firstname: peer.name.split(' ').first,
            lastname: peer.name.split(' ').length > 1
                ? peer.name.split(' ').last
                : null,
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // Messages within a thread.
  // ──────────────────────────────────────────────────────────────────

  msg.GetThreadMessagesResponseModel fakeThreadMessages(String threadId) {
    final tid = int.tryParse(threadId) ?? 9001;
    final peer = _peerForTid(tid);
    final now = DateTime.now();

    final convo = _conversationFor(tid);
    final messages = <msg.Messages>[];
    var t = now;
    for (final line in convo.reversed) {
      final m = msg.Messages.fromPayload({
        'message_thread_pk': tid,
        'message': line.body,
        'message_provider_id': 'demo-$tid-${messages.length}',
        'message_timestamp': t.toIso8601String(),
        'from_number': line.isMine ? demoFromNumber : peer.number,
        'message_status': 'delivered',
      });
      m.isDelivered = true;
      m.messageStatus = 'delivered';
      messages.add(m);
      t = t.subtract(const Duration(minutes: 4));
    }

    final participants = <msg.Participants>[
      msg.Participants(
        messageThreadId: tid.toString(),
        pk: 1,
        number: demoFromNumber,
        isSelf: true,
      ),
      msg.Participants(
        messageThreadId: tid.toString(),
        pk: 2,
        number: peer.number,
        isSelf: false,
        contact: msg.ParticipantContact(
          pk: 100 + tid,
          firstname: peer.name.split(' ').first,
          lastname: peer.name.split(' ').length > 1
              ? peer.name.split(' ').last
              : null,
        ),
      ),
    ];

    final res = msg.GetThreadMessagesResponseModel();
    res.result = msg.Result()
      ..messages = messages
      ..participants = participants;
    return res;
  }

  // ──────────────────────────────────────────────────────────────────
  // Call history.
  // ──────────────────────────────────────────────────────────────────

  List<CallHistory> fakeCallHistory() {
    final now = DateTime.now();
    return [
      _call('Alex Chen', '+15555550101', 4, false, true,
          now.subtract(const Duration(hours: 1))),
      _call('Jordan Rivera', '+15555550102', 0, true, true,
          now.subtract(const Duration(hours: 2, minutes: 30))),
      _call('Sam Patel', '+15555550103', 12, false, false,
          now.subtract(const Duration(hours: 5))),
      _call('Taylor Brooks', '+15555550104', 2, false, true,
          now.subtract(const Duration(hours: 8))),
      _call('Morgan Lee', '+15555550105', 6, false, false,
          now.subtract(const Duration(days: 1, hours: 1))),
      _call('Casey Nguyen', '+15555550106', 0, true, true,
          now.subtract(const Duration(days: 1, hours: 4))),
      _call('Riley Davis', '+15555550107', 9, false, true,
          now.subtract(const Duration(days: 2))),
      _call('Quinn Foster', '+15555550108', 3, false, false,
          now.subtract(const Duration(days: 3))),
    ];
  }

  CallHistory _call(String name, String number, int mins, bool missed,
      bool incoming, DateTime when) {
    return CallHistory(
      name: name,
      time: when,
      isIncoming: incoming,
      isMissed: missed,
      numberToDial: number,
      duration: mins * 60,
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // Contacts.
  // ──────────────────────────────────────────────────────────────────

  ContactResponse fakeContacts() {
    final list = <Contact>[];
    for (var i = 0; i < _contacts.length; i++) {
      final c = _contacts[i];
      final parts = c.name.split(' ');
      list.add(Contact(
        pk: 100 + i,
        firstname: parts.first,
        lastname: parts.length > 1 ? parts.last : '',
        phone: c.number,
      ));
    }
    final res = ContactResponse();
    res.result = list;
    return res;
  }

  _FakeContact _peerForTid(int tid) {
    final i = (tid - 9001).clamp(0, _contacts.length - 1);
    return _contacts[i];
  }

  List<_Line> _conversationFor(int tid) {
    switch (tid) {
      case 9001:
        return const [
          _Line('Hey, are we still on for 3?', isMine: false),
          _Line('Yes! Just heading out now.', isMine: true),
          _Line('Perfect — park around back, the front lot is full.', isMine: false),
          _Line('Will do, thanks.', isMine: true),
          _Line('Sounds good, see you at 3!', isMine: false),
        ];
      case 9002:
        return const [
          _Line('Did the new feature get pushed yet?', isMine: false),
          _Line('Should be live in about 10 min.', isMine: true),
          _Line('Nice. I\'ll keep an eye on the dashboard.', isMine: false),
        ];
      case 9003:
        return const [
          _Line('Got the contract — looks great.', isMine: false),
          _Line('Glad to hear. Anything we should tweak?', isMine: true),
          _Line('No, all good. Will sign tonight.', isMine: false),
          _Line('Thanks for the quick turnaround.', isMine: false),
        ];
      case 9004:
        return const [
          _Line('Can you forward me the invoice?', isMine: false),
          _Line('Sending it over now.', isMine: true),
        ];
      case 9005:
        return const [
          _Line('Running about 10 min late.', isMine: true),
          _Line('No worries, take your time.', isMine: false),
          _Line('On my way!', isMine: true),
        ];
      default:
        return const [
          _Line('Hey!', isMine: false),
          _Line('What\'s up?', isMine: true),
        ];
    }
  }
}

class _FakeContact {
  final String name;
  final String number;
  const _FakeContact(this.name, this.number);
}

class _Line {
  final String body;
  final bool isMine;
  const _Line(this.body, {required this.isMine});
}
