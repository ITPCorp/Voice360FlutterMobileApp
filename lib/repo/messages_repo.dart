import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:itp_voice/models/get_message_threads_response_model/get_message_threads_response_model.dart' hide Result;
import 'package:itp_voice/models/get_message_threads_response_model/get_message_threads_response_model.dart' as thr show Result;
import 'package:itp_voice/models/get_thread_messages_response_model/get_thread_messages_response_model.dart';
import 'package:itp_voice/repo/base_requester.dart';
import 'package:itp_voice/repo/shares_preference_repo.dart';
import 'package:itp_voice/routes.dart';
import 'package:itp_voice/services/demo_mode_service.dart';
import 'package:itp_voice/storage_keys.dart';

class MessagesRepo {
  /// Pagination size for the threads list. Matches voice360-fe (15).
  static const int kThreadsPageLimit = 15;

  /// Fetch a page of SMS threads for [myNumber]. Pass [offset] = 0 for the
  /// first page; subsequent pages add [kThreadsPageLimit] each time.
  getMessageThreads(String myNumber, {int offset = 0}) async {
    if (DemoModeService.instance.enabled) {
      // First page only — pretend pagination ended.
      if (offset > 0) {
        final empty = GetMessageThreadsResponseModel();
        empty.result = thr.Result(messageThreads: const []);
        return empty;
      }
      return DemoModeService.instance.fakeThreadsResponse();
    }
    String? apiId = await SharedPreferencesMethod.getString(StorageKeys.API_ID);
    try {
      final base = Endpoints.GET_MESSAGE_THREADS(apiId, myNumber);
      final url = '$base?offset=$offset&limit=$kThreadsPageLimit';
      final apiResponse =
          await BaseRequesterMethods.baseRequester.baseGetAPI(url);
      if (!apiResponse['errors']) {
        GetMessageThreadsResponseModel response =
            GetMessageThreadsResponseModel.fromJson(apiResponse);
        return response;
      }
      return "Something went wrong";
    } catch (e) {
      print(e.toString());
      return "Something went wrong";
    }
  }

  getThreadMessages(String threadId, String myNumber) async {
    if (DemoModeService.instance.enabled) {
      return DemoModeService.instance.fakeThreadMessages(threadId);
    }
    String? apiId = await SharedPreferencesMethod.getString(StorageKeys.API_ID);
    try {
      String number = myNumber;
      final apiResponse = await BaseRequesterMethods.baseRequester.baseGetAPI(
        Endpoints.GET_THREAD_MESSAGES(apiId, number, threadId),
      );
      if (!apiResponse['errors']) {
        GetThreadMessagesResponseModel response = GetThreadMessagesResponseModel.fromJson(apiResponse);
        return response;
      }
      return "Something went wrong";
    } catch (e) {
      print(e.toString());
      return "Something went wrong";
    }
  }

  Future<void> markAsRead(String threadId, String myNumber) async {
    String? apiId = await SharedPreferencesMethod.getString(StorageKeys.API_ID);
    try {
      String number = myNumber;
      final apiResponse = await BaseRequesterMethods.baseRequester.basePostAPI(
        Endpoints.MARK_AS_READ(apiId, number, threadId),
        jsonEncode(''),
        protected: true,
      );
      if (!apiResponse['errors']) {
        return;
      }
      return;
    } catch (e) {
      print(e.toString());
    }
  }

  Future<Messages?> sendMessage(String myNumber, String body, String to, [String? image]) async {
    String? apiId = await SharedPreferencesMethod.getString(StorageKeys.API_ID);
    try {
      // {
      //     "body": body,
      //     "from_number": myNumber,
      //     "to_numbers_list": "{\"list\": [\"+13052990233\"]}"
      //   }
      Dio dio = Dio();
      print(body);
      Map<String, dynamic> data = {
        "body": body,
        "from_number": myNumber,
        "to_numbers_list": to,
      };
      print(to);
      if (image != null) {
        data["file"] = await MultipartFile.fromFile(image);
      }
      final resp = await BaseRequesterMethods.baseRequester
          .basePostAPI(Endpoints.SEND_MESSAGE(apiId, myNumber), data, useDio: true);
      print(resp);
      return Messages.fromJson(resp["result"]);
    } catch (e) {
      if (e is DioError) {
        print(e.response);
      }
      print(e.toString());
      return null;
    }
  }
}
