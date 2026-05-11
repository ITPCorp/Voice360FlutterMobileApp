import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:itp_voice/controllers/base_screen_controller.dart';
import 'package:itp_voice/design/v360.dart';
import 'package:itp_voice/screens/contacts_screen.dart';
import 'package:itp_voice/screens/home_screen.dart';
import 'package:itp_voice/screens/messages_screen.dart';
import 'package:itp_voice/screens/profile_screen.dart';
import 'package:itp_voice/screens/voice_mail_screen.dart';

class BaseScreen extends StatelessWidget {
  BaseScreen({super.key});
  final BaseScreenController con = Get.put(BaseScreenController());

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
        child: Obx(() => _bodyForTab(con.currentTab.value)),
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
              labelBehavior:
                  NavigationDestinationLabelBehavior.alwaysShow,
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
