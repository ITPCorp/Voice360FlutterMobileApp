import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:itp_voice/controllers/call_screen_controller.dart';
import 'package:itp_voice/design/v360.dart';

class InCallDialPad extends StatelessWidget {
  InCallDialPad({super.key});
  final CallScreenController con = Get.find<CallScreenController>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Keypad')),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              V360Dialpad(onKey: (d) => con.handleDtmf(d)),
              const SizedBox(height: V360Spacing.s8),
              SizedBox(
                width: 72,
                height: 72,
                child: Material(
                  color: V360Colors.callDecline,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  elevation: 6,
                  shadowColor:
                      V360Colors.callDecline.withOpacity(0.4),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => con.handleHangup(goBack: true),
                    child: const Icon(Icons.call_end_rounded,
                        color: Colors.white, size: 32),
                  ),
                ),
              ),
              const SizedBox(height: V360Spacing.s5),
            ],
          ),
        ),
      ),
    );
  }
}
