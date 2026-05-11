import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:itp_voice/repo/base_requester.dart';
import 'package:itp_voice/repo/shares_preference_repo.dart';
import 'package:itp_voice/routes.dart';
import 'package:itp_voice/storage_keys.dart';
import 'package:itp_voice/widgets/custom_toast.dart';

/// One row in the outbound caller ID dropdown. We render
/// "{formatted-number} ({description})" to match the web client.
class AssignedNumber {
  final String number;
  final String? description;
  const AssignedNumber({required this.number, this.description});

  String get label {
    final formatted = formatPhone(number);
    if (description == null || description!.trim().isEmpty) return formatted;
    return '$formatted (${description!.trim()})';
  }

  static String formatPhone(String n) {
    final digits = n.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 11 && digits.startsWith('1')) {
      // +1 (NPA) NXX-XXXX
      return '+1 (${digits.substring(1, 4)}) ${digits.substring(4, 7)}-${digits.substring(7)}';
    }
    if (digits.length == 10) {
      return '(${digits.substring(0, 3)}) ${digits.substring(3, 6)}-${digits.substring(6)}';
    }
    return n;
  }
}

/// Backs the Call Settings screen.
///
/// Mirrors voice360-fe-redesign's CallForwarding + CallerId components.
/// Forward + override settings persist to `/itpvoice/v2/{api_id}/my-extension`
/// via PATCH on each change — same endpoint and field names as the web.
class CallSettingsController extends GetxController {
  final RxBool isLoading = false.obs;
  final RxBool isSaving = false.obs;

  // ── Call forwarding (server-backed) ──────────────────────────────────────
  final RxBool callForwarding = false.obs;
  final RxBool keepOriginalCallerId = false.obs;
  final RxBool forwardQueueCalls = false.obs;
  final RxBool callScreening = false.obs;
  final TextEditingController forwardNumberController = TextEditingController();

  // ── Outbound caller ID override (server-backed) ──────────────────────────
  /// Local switch: ON when the user has set a custom caller ID number.
  /// Matches the web's `switchOverrideDefaultCallerID` which is also derived
  /// from whether the fields are populated (no server boolean exists).
  final RxBool overrideDefaultCallerId = false.obs;
  final RxString selectedCallerIdNumber = ''.obs;
  final TextEditingController callerIdNameController = TextEditingController();
  final RxList<AssignedNumber> assignedNumbers = <AssignedNumber>[].obs;
  final RxBool isLoadingNumbers = false.obs;

  // ── Call recording (local pref — no /my-extension equivalent) ────────────
  final RxBool callRecordingInternal = false.obs;
  final RxBool callRecordingExternal = false.obs;

  String? _apiId;

  @override
  void onInit() {
    super.onInit();
    _apiId = SharedPreferencesMethod.storage.getString(StorageKeys.API_ID);
    _fetchExtensionSettings();
    _fetchAssignedNumbers();
  }

  @override
  void onClose() {
    forwardNumberController.dispose();
    callerIdNameController.dispose();
    super.onClose();
  }

  Future<void> _fetchExtensionSettings() async {
    if (_apiId == null || _apiId!.isEmpty) return;
    isLoading.value = true;
    try {
      final res = await BaseRequesterMethods.baseRequester
          .baseGetAPI(Endpoints.GET_USER_DATA(_apiId));
      final result = res is Map ? res['result'] : null;
      if (result is Map) {
        callForwarding.value = result['callforward_enable'] == true;
        forwardNumberController.text =
            (result['callforward_number'] ?? '').toString();
        keepOriginalCallerId.value =
            result['callforward_keep_caller_caller_id'] == true;
        forwardQueueCalls.value = result['callforward_queue_calls'] == true;
        callScreening.value = result['callforward_call_confirmation'] == true;

        final callerIdNumber =
            (result['default_outbound_callerid_number'] ?? '').toString();
        final callerIdName =
            (result['default_outbound_callerid_name'] ?? '').toString();
        selectedCallerIdNumber.value = callerIdNumber;
        callerIdNameController.text = callerIdName;
        // Override considered "on" if either field is populated — same
        // heuristic the web uses.
        overrideDefaultCallerId.value =
            callerIdNumber.isNotEmpty || callerIdName.isNotEmpty;
      }
    } catch (e) {
      // ignore: avoid_print
      print('Call settings fetch failed: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _fetchAssignedNumbers() async {
    if (_apiId == null || _apiId!.isEmpty) return;
    isLoadingNumbers.value = true;
    try {
      // Mirrors voice360-fe's MySettings page: it pulls the user-visible
      // number list from /my-extension/chat/numbers (the "assignedNumbers"
      // petition key), NOT the bare /my-extension/numbers endpoint which
      // returns an empty list for non-admin users.
      final res = await BaseRequesterMethods.baseRequester
          .baseGetAPI(Endpoints.GET_CHAT_NUMBERS_URL(_apiId));
      final list = res is Map ? res['result'] : null;
      if (list is List) {
        assignedNumbers.value = [
          for (final row in list)
            if (row is Map && row['number'] != null)
              AssignedNumber(
                number: row['number'].toString(),
                description: row['description']?.toString(),
              ),
        ];
      }
    } catch (e) {
      // ignore: avoid_print
      print('Assigned numbers fetch failed: $e');
    } finally {
      isLoadingNumbers.value = false;
    }
  }

  /// PATCH only the field(s) the user just changed. Matches
  /// editSwitchsCallForwardingService.js semantics: turning the master switch
  /// off clears everything; otherwise just the single field is patched.
  Future<void> _patch(Map<String, dynamic> data) async {
    if (_apiId == null || _apiId!.isEmpty) return;
    isSaving.value = true;
    try {
      final url = Endpoints.GET_USER_DATA(_apiId);
      final res = await BaseRequesterMethods.baseRequester.basePatchAPI(
        url,
        json.encode(data),
        protected: true,
      );
      if (res == null) {
        CustomToast.showToast('Could not save settings', true);
      }
    } catch (e) {
      // ignore: avoid_print
      print('Call settings PATCH failed: $e');
      CustomToast.showToast('Could not save settings', true);
    } finally {
      isSaving.value = false;
    }
  }

  // ── Forwarding toggle handlers ──────────────────────────────────────────
  Future<void> toggleCallForwarding(bool v) async {
    callForwarding.value = v;
    if (!v) {
      forwardNumberController.clear();
      keepOriginalCallerId.value = false;
      forwardQueueCalls.value = false;
      callScreening.value = false;
      await _patch({
        'callforward_enable': false,
        'callforward_keep_caller_caller_id': false,
        'callforward_queue_calls': false,
        'callforward_call_confirmation': false,
        'callforward_number': '',
      });
    } else {
      await _patch({'callforward_enable': true});
    }
  }

  Future<void> saveForwardNumber() async {
    await _patch({'callforward_number': forwardNumberController.text.trim()});
  }

  Future<void> toggleKeepOriginalCallerId(bool v) async {
    keepOriginalCallerId.value = v;
    await _patch({'callforward_keep_caller_caller_id': v});
  }

  Future<void> toggleForwardQueueCalls(bool v) async {
    forwardQueueCalls.value = v;
    await _patch({'callforward_queue_calls': v});
  }

  Future<void> toggleCallScreening(bool v) async {
    callScreening.value = v;
    await _patch({'callforward_call_confirmation': v});
  }

  // ── Caller ID override handlers ─────────────────────────────────────────
  Future<void> toggleOverrideDefaultCallerId(bool v) async {
    overrideDefaultCallerId.value = v;
    if (!v) {
      // Mirror editSwitchsCallerIdService: PATCH empty strings.
      selectedCallerIdNumber.value = '';
      callerIdNameController.clear();
      await _patch({
        'default_outbound_callerid_number': '',
        'default_outbound_callerid_name': '',
      });
    }
    // When turning ON we don't PATCH yet — wait for the user to actually
    // pick a number/name. Same as the web.
  }

  Future<void> setCallerIdNumber(String number) async {
    selectedCallerIdNumber.value = number;
    await _patch({'default_outbound_callerid_number': number});
  }

  Future<void> saveCallerIdName() async {
    await _patch({
      'default_outbound_callerid_name': callerIdNameController.text.trim(),
    });
  }

  /// True when the persisted caller ID number isn't in the list of currently
  /// assigned numbers — admin reassigned/removed it. Web flags this in red.
  bool get hasOrphanedCallerId =>
      selectedCallerIdNumber.value.isNotEmpty &&
      !assignedNumbers.any((n) => n.number == selectedCallerIdNumber.value);
}
