import 'dart:developer';

import 'package:itp_voice/controllers/call_history_controller.dart';
import 'package:itp_voice/models/call_history_model.dart';
import 'package:itp_voice/models/get_contacts_reponse_model/get_contacts_reponse_model.dart';
import 'package:itp_voice/models/get_contacts_reponse_model/user_contact.dart';
import 'package:itp_voice/repo/base_requester.dart';
import 'package:itp_voice/repo/contacts_repo.dart';
import 'package:itp_voice/repo/shares_preference_repo.dart';
import 'package:itp_voice/routes.dart';
import 'package:itp_voice/storage_keys.dart';

class CallHistoryRepo {
  // Default window mirrors the web client: paginate within a date range so the
  // backend doesn't scan unbounded CDRs (which 500s on malformed rows).
  static const Duration _defaultWindow = Duration(days: 30);

  Future<dynamic> fetchCallHistory({required int offSet}) async {
    final List<CallHistory> out = [];
    final String? apiId =
        await SharedPreferencesMethod.getString(StorageKeys.API_ID);
    final String? userId =
        await SharedPreferencesMethod.getString(StorageKeys.USER_ID);
    final String myPhoneNumber = SharedPreferencesMethod.storage
            .getString(StorageKeys.DEFAULT_NUMBER) ??
        '';
    final String myExtension =
        SharedPreferencesMethod.storage.getString(StorageKeys.EXTENTION) ?? '';

    final now = DateTime.now();
    final start = now.subtract(_defaultWindow);
    final url = Endpoints.GET_CALL_HISTORY(
      apiId,
      offSet,
      startMs: start.millisecondsSinceEpoch,
      endMs: now.millisecondsSinceEpoch,
    );

    try {
      final apiResponse =
          await BaseRequesterMethods.baseRequester.baseGetAPI(url);
      if (apiResponse == null) return "Couldn't load call history.";
      if (apiResponse is! Map) {
        return "Call history is temporarily unavailable. Try again in a moment.";
      }
      if (apiResponse['errors'] == true) {
        return apiResponse['message']?.toString() ??
            "Couldn't load call history.";
      }
      if (apiResponse['errors'] == null && apiResponse['result'] is String) {
        // Server-side 500 with `{"error":"","result":"Internal Server Error"}`.
        return "Call history is temporarily unavailable. Try again in a moment.";
      }

      final result = apiResponse['result'];
      if (result is! Map) return out;

      final reports = result['user_reports'];
      if (reports is! List || reports.isEmpty) {
        // No calls in window — empty success.
        itemCount = 0;
        return out;
      }

      final report = reports.first as Map;
      final allCalls = (report['all_calls'] as List?) ?? const [];
      itemCount = (report['total_calls'] as num?)?.toInt() ?? allCalls.length;
      log('item count new value $itemCount');

      for (final raw in allCalls) {
        if (raw is! Map) continue;
        final call = Map<String, dynamic>.from(raw);

        String? transcription;
        final tx = call['call_transcription'];
        if (tx is String && tx.isNotEmpty) {
          transcription = tx;
        } else if (tx is Map) {
          final inner = tx['transcription'] ?? tx['formatedTranscription'];
          if (inner is String && inner.isNotEmpty) transcription = inner;
        }

        final src = call['src']?.toString();
        final dst = call['dst']?.toString();
        final clid = call['clid']?.toString();
        final isOutbound =
            (src != null) && (src == myExtension || src == myPhoneNumber);

        final name = isOutbound
            ? ((clid != null && clid.contains('<'))
                ? clid.split('<')[0].replaceAll('"', '').trim()
                : (clid ?? dst ?? ''))
            : (src ?? '');

        DateTime? time;
        final calldate = call['calldate'];
        if (calldate is num) {
          time = DateTime.fromMillisecondsSinceEpoch(
              (calldate * 1000).toInt());
        } else if (calldate is String) {
          final secs = int.tryParse(calldate.split('.').first);
          if (secs != null) {
            time = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
          } else {
            time = DateTime.tryParse(calldate);
          }
        }

        out.add(CallHistory(
          name: name,
          time: time,
          isIncoming: !isOutbound,
          isMissed: call['disposition']?.toString() != 'ANSWERED',
          numberToDial: isOutbound ? dst : src,
          cdrPk: (call['pk'] as num?)?.toInt(),
          duration: (call['duration'] as num?)?.toInt() ??
              (call['billsec'] as num?)?.toInt(),
          callRecordingFilename: call['call_recording_filename'] as String?,
          callTranscription: transcription,
          aiCall: call['ai_call'] == true || call['was_ai'] == true,
        ));
      }
      return out;
    } catch (e) {
      print('fetchCallHistory error: $e');
      return "Couldn't load call history.";
    }
  }
}
