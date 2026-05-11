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
  /// True when the per-user caller ID override is active. The server field
  /// is `automatic_caller_id` — same flag voice360-fe-redesign's MySettings
  /// reads. When false, the user inherits the account-level caller ID
  /// (set by admins on the GeneralSettings page in the web).
  final RxBool overrideDefaultCallerId = false.obs;
  final RxString selectedCallerIdNumber = ''.obs;
  final TextEditingController callerIdNameController = TextEditingController();
  final RxList<AssignedNumber> assignedNumbers = <AssignedNumber>[].obs;
  final RxBool isLoadingNumbers = false.obs;

  /// Account-level outbound caller ID, read from `voice_account` on
  /// `/my-extension`. When the user's own `default_outbound_callerid_*`
  /// fields are empty, the dropdown should display this number as the
  /// effective caller ID (inherited from the account default). Stored so
  /// we can tell "this is the inherited account default" apart from
  /// "this number was set but is no longer assigned to the account"
  /// (the orphan-warning case).
  final RxString accountDefaultCallerIdNumber = ''.obs;
  final RxString accountDefaultCallerIdName = ''.obs;

  // ── Call recording (server-backed: "enabled" string flags) ───────────────
  /// Stored on the server as `call_recording_internal` / `call_recording_external`
  /// with the value `"enabled"` or `"disabled"`. The web's MySettings checks
  /// `=== "enabled"`. We mirror that — toggling PATCHes the string form.
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
        // Defaults to TRUE if the server hasn't explicitly set it to false —
        // matches the web's `data.callforward_keep_caller_caller_id !== false`.
        keepOriginalCallerId.value =
            result['callforward_keep_caller_caller_id'] != false;
        forwardQueueCalls.value = result['callforward_queue_calls'] == true;
        callScreening.value = result['callforward_call_confirmation'] == true;

        // Caller ID: `automatic_caller_id` is the server boolean for "user
        // override is active". When true, the user's saved
        // default_outbound_callerid_* fields are used; if those are empty
        // the user inherits the account-level values nested under
        // `voice_account` (set by admins). Mirrors the web's MySettings.
        overrideDefaultCallerId.value = result['automatic_caller_id'] == true;
        final voiceAccount = result['voice_account'];
        final acctNumber = voiceAccount is Map
            ? (voiceAccount['default_outbound_callerid_number'] ?? '').toString()
            : '';
        final acctName = voiceAccount is Map
            ? (voiceAccount['default_outbound_callerid_name'] ?? '').toString()
            : '';
        accountDefaultCallerIdNumber.value = acctNumber;
        accountDefaultCallerIdName.value = acctName;
        final userNumber =
            (result['default_outbound_callerid_number'] ?? '').toString();
        final userName =
            (result['default_outbound_callerid_name'] ?? '').toString();
        selectedCallerIdNumber.value =
            userNumber.isNotEmpty ? userNumber : acctNumber;
        callerIdNameController.text =
            userName.isNotEmpty ? userName : acctName;

        // Call recording flags are server-side per-user (the web's
        // MySettings reads them from /my-extension too). Stored as the
        // string "enabled" / "disabled" rather than a boolean.
        callRecordingInternal.value =
            result['call_recording_internal'] == 'enabled';
        callRecordingExternal.value =
            result['call_recording_external'] == 'enabled';
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
    // The server boolean is `automatic_caller_id` — same field the web's
    // MySettings reads. PATCH it directly. We keep the existing number/name
    // intact so the user doesn't lose what they previously set if they
    // toggle off then back on.
    await _patch({'automatic_caller_id': v});
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
  /// assigned numbers AND isn't the account-level default — admin
  /// reassigned/removed it. Web flags this in red.
  /// (The account default may legitimately not appear in the user's assigned
  /// numbers — inheriting it is not an orphan condition.)
  bool get hasOrphanedCallerId {
    final selected = selectedCallerIdNumber.value;
    if (selected.isEmpty) return false;
    if (selected == accountDefaultCallerIdNumber.value) return false;
    return !assignedNumbers.any((n) => n.number == selected);
  }

  // ── Call recording handlers (server-backed) ─────────────────────────────
  Future<void> toggleCallRecordingInternal(bool v) async {
    callRecordingInternal.value = v;
    await _patch({'call_recording_internal': v ? 'enabled' : 'disabled'});
  }

  Future<void> toggleCallRecordingExternal(bool v) async {
    callRecordingExternal.value = v;
    await _patch({'call_recording_external': v ? 'enabled' : 'disabled'});
  }
}
