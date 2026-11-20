import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:itp_voice/controllers/base_screen_controller.dart';
import 'package:itp_voice/design/v360.dart';
import 'package:itp_voice/routes.dart';
import 'package:itp_voice/screens/call_history_screen.dart';

class HomeScreen extends StatefulWidget {
  final String? initialValue;
  const HomeScreen({super.key, this.initialValue});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final BaseScreenController con = Get.find<BaseScreenController>();
  late final TabController _tabs;
  final TextEditingController _number = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    if (widget.initialValue != null) {
      _number.text = widget.initialValue!;
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    _number.dispose();
    super.dispose();
  }

  void _press(String d) {
    final pos = _number.selection.baseOffset;
    final text = _number.text;
    final at = (pos < 0 || pos > text.length) ? text.length : pos;
    final next = text.replaceRange(at, at, d);
    _number.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: at + d.length),
    );
  }

  /// Long-press 0: the 0 entered on touch becomes "+".
  void _zeroToPlus() {
    final pos = _number.selection.baseOffset;
    final text = _number.text;
    final at = (pos < 0 || pos > text.length) ? text.length : pos;
    if (at == 0 || text[at - 1] != '0') return;
    _number.value = TextEditingValue(
      text: text.replaceRange(at - 1, at, '+'),
      selection: TextSelection.collapsed(offset: at),
    );
  }

  void _backspace() {
    HapticFeedback.selectionClick();
    final pos = _number.selection.baseOffset;
    final text = _number.text;
    if (text.isEmpty) return;
    final at = (pos < 0 || pos > text.length) ? text.length : pos;
    if (at == 0) return;
    final next = text.replaceRange(at - 1, at, '');
    _number.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: at - 1),
    );
  }

  void _clear() {
    HapticFeedback.mediumImpact();
    _number.clear();
  }

  Future<void> _call() async {
    final n = _number.text.trim();
    if (n.isEmpty) return;
    HapticFeedback.mediumImpact();
    await con.handleCall(n, context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VOICE360'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Get.toNamed(Routes.SETTINGS_SCREEN_ROUTE),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Keypad'),
            Tab(text: 'Recent'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        // No swipe between Keypad and Recent: while a finger is down, a
        // swipeable pager ignores every other touch, so fast dialing (next key
        // pressed before the last finger lifts) dropped digits. Tabs still
        // switch by tapping Keypad / Recent.
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _buildKeypad(context),
          const CallHistoryScreen(),
        ],
      ),
    );
  }

  Widget _buildKeypad(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                      child: Column(
                    children: [
                      const SizedBox(height: V360Spacing.s5),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: V360Spacing.s6),
                        child: Row(
                          children: [
                            Expanded(
                              child: ValueListenableBuilder(
                                valueListenable: _number,
                                builder: (_, value, __) {
                                  final empty = value.text.isEmpty;
                                  return TextField(
                                    controller: _number,
                                    readOnly: false,
                                    showCursor: true,
                                    textAlign: TextAlign.center,
                                    keyboardType: TextInputType.none,
                                    style: tt.headlineLarge?.copyWith(
                                      fontWeight: FontWeight.w400,
                                      letterSpacing: 1.5,
                                      color: empty
                                          ? cs.onSurfaceVariant
                                          : cs.onSurface,
                                    ),
                                    decoration: InputDecoration(
                                      filled: false,
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      hintText: 'Enter number',
                                      hintStyle: tt.headlineLarge?.copyWith(
                                        color: cs.onSurfaceVariant,
                                        fontWeight: FontWeight.w300,
                                      ),
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: V360Spacing.s2),
                      const Spacer(),
                      V360Dialpad(
                        compact: constraints.maxHeight < 520,
                        onKey: _press, // the dialpad already does the haptic
                        onPlus: _zeroToPlus,
                      ),
                      const SizedBox(height: V360Spacing.s5),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: V360Spacing.s6),
                        child: Row(
                          children: [
                            ValueListenableBuilder(
                                valueListenable: _number,
                                builder: (_, value, __) => _smallAction(
                                      context,
                                      icon: Icons.person_add_alt_1_rounded,
                                      label: 'Add contact',
                                      onTap: value.text.trim().isEmpty
                                          ? null
                                          : () => Get.toNamed(
                                                Routes.ADD_NEW_CONTACT_ROUTE,
                                                arguments: _number.text,
                                              ),
                                    )),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: V360Spacing.s4,
                                ),
                                child: ValueListenableBuilder(
                                  valueListenable: _number,
                                  builder: (_, value, __) => _CallButton(
                                    enabled: value.text.trim().isNotEmpty,
                                    onTap: _call,
                                  ),
                                ),
                              ),
                            ),
                            _smallAction(
                              context,
                              icon: Icons.backspace_outlined,
                              label: 'Delete digit. Hold to clear',
                              onTap: _backspace,
                              onLongPress: _clear,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: V360Spacing.s6),
                    ],
                  )),
                ),
              )),
    );
  }

  Widget _smallAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    final cs = Theme.of(context).colorScheme;
    final disabled = onTap == null;
    return SizedBox(
      width: 56,
      height: 56,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Center(
            child: Icon(
              icon,
              semanticLabel: label,
              color: disabled
                  ? cs.onSurfaceVariant.withOpacity(0.5)
                  : cs.onSurface,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

class _CallButton extends StatefulWidget {
  final bool enabled;
  final VoidCallback onTap;
  const _CallButton({required this.enabled, required this.onTap});

  @override
  State<_CallButton> createState() => _CallButtonState();
}

class _CallButtonState extends State<_CallButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.enabled ? V360Colors.callAccept : V360Colors.gray400;
    return AnimatedScale(
      scale: _pressed ? 0.92 : 1.0,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      child: SizedBox(
        width: 72,
        height: 72,
        child: Material(
          color: color,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          elevation: widget.enabled ? (_pressed ? 1 : 4) : 0,
          shadowColor: color.withOpacity(0.4),
          animationDuration: const Duration(milliseconds: 120),
          child: InkWell(
            customBorder: const CircleBorder(),
            splashColor: Colors.white.withOpacity(0.2),
            highlightColor: Colors.transparent,
            onTapDown:
                widget.enabled ? (_) => setState(() => _pressed = true) : null,
            onTapCancel:
                widget.enabled ? () => setState(() => _pressed = false) : null,
            onTapUp:
                widget.enabled ? (_) => setState(() => _pressed = false) : null,
            onTap: widget.enabled
                ? () {
                    HapticFeedback.mediumImpact();
                    widget.onTap();
                  }
                : null,
            child: const Center(
              child: Icon(Icons.call_rounded,
                  semanticLabel: 'Call', color: Colors.white, size: 32),
            ),
          ),
        ),
      ),
    );
  }
}
