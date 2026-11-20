import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:itp_voice/controllers/base_screen_controller.dart';
import 'package:itp_voice/controllers/call_history_controller.dart';
import 'package:itp_voice/controllers/contacts_controller.dart';
import 'package:itp_voice/controllers/messages_controller.dart';
import 'package:itp_voice/controllers/profile_controller.dart';
import 'package:itp_voice/controllers/voicemails_controller.dart';
import 'package:itp_voice/design/v360.dart';
import 'package:itp_voice/screens/contacts_screen.dart';
import 'package:itp_voice/screens/home_screen.dart';
import 'package:itp_voice/screens/messages_screen.dart';
import 'package:itp_voice/screens/profile_screen.dart';
import 'package:itp_voice/screens/voice_mail_screen.dart';

class BaseScreen extends StatefulWidget {
  const BaseScreen({super.key});
  @override
  State<BaseScreen> createState() => _BaseScreenState();
}

class _BaseScreenState extends State<BaseScreen> with WidgetsBindingObserver {
  final _pages = <int, Widget>{};
  final BaseScreenController con = Get.put(BaseScreenController());

  final _updated = <int, DateTime>{};
  late final Worker _selection;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _updated[con.currentTab.value] = DateTime.now();
    _selection = ever(con.currentTab, _refreshIfStale);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _selection.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ModalRoute.of(context)?.isCurrent == true) {
      _refreshIfStale(con.currentTab.value);
    }
  }

  // Newly mounted tabs load themselves. Retained tabs revalidate when revisited.
  void _refreshIfStale(int tab) {
    final now = DateTime.now();
    final previous = _updated[tab];
    if (previous != null &&
        now.difference(previous) < const Duration(seconds: 30)) {
      return;
    }
    _updated[tab] = now;
    if (!_pages.containsKey(tab)) return;
    switch (tab) {
      case 0 when con.dialTab == 1 && Get.isRegistered<CallHistoryController>():
        Get.find<CallHistoryController>().refreshCalls();
      case 1 when Get.isRegistered<ContactsController>():
        Get.find<ContactsController>().fetchContacts('0');
      case 2 when Get.isRegistered<MessagesController>():
        Get.find<MessagesController>().loadThreads();
      case 3 when Get.isRegistered<VoiceMailsController>():
        Get.find<VoiceMailsController>().fetchVoiceMails();
      case 4 when Get.isRegistered<ProfileController>():
        Get.find<ProfileController>().fetchUserProfile();
    }
  }

  static const List<_Tab> _tabs = [
    _Tab(icon: Icons.dialpad_rounded, label: 'Dial'),
    _Tab(icon: Icons.people_alt_rounded, label: 'Contacts'),
    _Tab(icon: Icons.chat_bubble_rounded, label: 'Messages'),
    _Tab(icon: Icons.voicemail_rounded, label: 'Voicemail'),
    _Tab(icon: Icons.person_rounded, label: 'Profile'),
  ];

  Widget _bodyForTab(int index) {
    return switch (index) {
      0 => HomeScreen(),
      1 => ContactsScreen(),
      2 => MessagesScreen(),
      3 => VoiceMailScreen(),
      _ => ProfileScreen(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Obx(() {
          final selected = con.currentTab.value;
          _pages.putIfAbsent(selected, () => _bodyForTab(selected));
          return IndexedStack(index: selected, children: [
            for (var i = 0; i < _tabs.length; i++)
              TickerMode(
                  enabled: i == selected,
                  child: RepaintBoundary(
                      child: _pages[i] ?? const SizedBox.shrink())),
          ]);
        }),
      ),
      bottomNavigationBar: Obx(() {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(
              top: BorderSide(color: cs.outlineVariant),
            ),
          ),
          child: SafeArea(
            top: false,
            child: NavigationBar(
              selectedIndex: con.currentTab.value,
              onDestinationSelected: con.updateCurrentTab,
              backgroundColor: cs.surface,
              indicatorColor: cs.primaryContainer,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              destinations: [
                for (final t in _tabs)
                  NavigationDestination(
                    icon: Icon(t.icon),
                    selectedIcon: Icon(t.icon, color: cs.primary),
                    label: t.label,
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _Tab {
  final IconData icon;
  final String label;
  const _Tab({required this.icon, required this.label});
}
