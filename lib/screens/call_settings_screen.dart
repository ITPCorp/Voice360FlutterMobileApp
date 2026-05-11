import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:itp_voice/controllers/call_settings_controller.dart';
import 'package:itp_voice/design/v360.dart';

class CallSettingsScreen extends StatelessWidget {
  CallSettingsScreen({super.key});
  final CallSettingsController con = Get.put(CallSettingsController());

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Call settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          horizontal: V360Spacing.s4,
          vertical: V360Spacing.s4,
        ),
        children: [
          _label('CALL FORWARDING'),
          const SizedBox(height: V360Spacing.s2),
          V360Card(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Obx(() => SwitchListTile(
                      value: con.callForwarding.value,
                      onChanged: (v) => con.callForwarding.value = v,
                      title: const Text('Forward calls'),
                      secondary: Icon(Icons.phone_forwarded_outlined,
                          color: cs.primary),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: V360Spacing.s4,
                      ),
                    )),
                Divider(
                    height: 1,
                    color: cs.outlineVariant,
                    indent: 56),
                Obx(() => SwitchListTile(
                      value: con.forwardDirectCallsOnly.value,
                      onChanged: (v) => con.forwardDirectCallsOnly.value = v,
                      title: const Text('Direct calls only'),
                      subtitle: Text(
                        'Only forward calls placed directly to your number',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      secondary: Icon(Icons.tune_rounded, color: cs.primary),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: V360Spacing.s4,
                      ),
                    )),
                Divider(
                    height: 1,
                    color: cs.outlineVariant,
                    indent: 56),
                Obx(() => SwitchListTile(
                      value: con.keepOriginalCallerId.value,
                      onChanged: (v) => con.keepOriginalCallerId.value = v,
                      title: const Text('Keep original caller ID'),
                      secondary: Icon(Icons.person_outline_rounded,
                          color: cs.primary),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: V360Spacing.s4,
                      ),
                    )),
              ],
            ),
          ),
          const SizedBox(height: V360Spacing.s5),
          _label('CALLER ID'),
          const SizedBox(height: V360Spacing.s2),
          V360Card(
            padding: EdgeInsets.zero,
            child: Obx(() {
              final on = con.overrideDefaultCallerIdSettings;
              return Column(
                children: [
                  SwitchListTile(
                    value: on,
                    onChanged: (v) =>
                        con.overrideDefaultCallerIdSettings = v,
                    title: const Text('Override default caller ID'),
                    secondary: Icon(Icons.badge_outlined, color: cs.primary),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: V360Spacing.s4,
                    ),
                  ),
                  if (on) ...[
                    const Divider(height: 1, indent: 56),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        V360Spacing.s4,
                        V360Spacing.s3,
                        V360Spacing.s4,
                        V360Spacing.s4,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: con.callerNameController,
                            decoration: const InputDecoration(
                              labelText: 'Caller name',
                              prefixIcon:
                                  Icon(Icons.person_outline_rounded, size: 20),
                            ),
                          ),
                          const SizedBox(height: V360Spacing.s3),
                          TextField(
                            controller: con.callerNnumberController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Caller number',
                              prefixIcon:
                                  Icon(Icons.phone_outlined, size: 20),
                            ),
                          ),
                          const SizedBox(height: V360Spacing.s4),
                          V360Button(
                            label: 'Save caller ID',
                            onPressed: con.updateOverriddenCallerData,
                            fullWidth: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            }),
          ),
          const SizedBox(height: V360Spacing.s5),
          _label('CALL RECORDING'),
          const SizedBox(height: V360Spacing.s2),
          V360Card(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Obx(() => SwitchListTile(
                      value: con.callRecordingInternal.value,
                      onChanged: (v) => con.callRecordingInternal.value = v,
                      title: const Text('Record internal calls'),
                      secondary: Icon(Icons.fiber_manual_record_rounded,
                          color: V360Colors.danger500),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: V360Spacing.s4,
                      ),
                    )),
                Divider(
                    height: 1,
                    color: cs.outlineVariant,
                    indent: 56),
                Obx(() => SwitchListTile(
                      value: con.callRecordingExternal.value,
                      onChanged: (v) => con.callRecordingExternal.value = v,
                      title: const Text('Record external calls'),
                      secondary: Icon(Icons.fiber_manual_record_outlined,
                          color: cs.primary),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: V360Spacing.s4,
                      ),
                    )),
              ],
            ),
          ),
          const SizedBox(height: V360Spacing.s10),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(left: V360Spacing.s2),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      );
}
