import 'dart:io';

import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:dio/dio.dart';
// downloads_path_provider_28 is dead (Flutter v1 embedding); using path_provider instead
import 'package:flutter/cupertino.dart';
import 'package:get/get.dart';
import 'package:itp_voice/cache/cache_service.dart';
import 'package:itp_voice/models/get_voice_mails_response_model/get_voice_mails_response_model.dart';
import 'package:itp_voice/models/get_voice_mails_response_model/result.dart';
import 'package:itp_voice/repo/shares_preference_repo.dart';
import 'package:itp_voice/repo/voice_mails_repo.dart';
import 'package:itp_voice/routes.dart';
import 'package:itp_voice/storage_keys.dart';
import 'package:itp_voice/widgets/custom_loader.dart';
import 'package:itp_voice/widgets/custom_toast.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class VoiceMailsController extends GetxController {
  List<VoiceMails> voiceMails = [];
  RxBool downloadingVoicemail = true.obs;
  PlayerController? playerController;
  bool voiceMailDownload = false;
  String savePath = "";
  int tappedIndex = 0;
  late VoiceMails voiceMail;
  // final player = AudioPlayer();
  Duration? voiceMailDuration;
  bool isVoiceMailsLoading = false;
  VoiceMailsRepo repo = VoiceMailsRepo();
  TextEditingController searchController = TextEditingController();

  bool _hydratedFromCache = false;
  bool get hasCachedData => _hydratedFromCache;

  void _hydrateFromCache() {
    if (!AppCache.instance.isReady || _hydratedFromCache) return;
    final cached = AppCache.instance.voicemails.readAll();
    if (cached.isEmpty) return;
    voiceMails = List.from(cached);
    _hydratedFromCache = true;
    update();
  }

  fetchVoiceMails() async {
    _hydrateFromCache();
    // Show loading state only when we have nothing on screen.
    isVoiceMailsLoading = voiceMails.isEmpty;
    update();

    final res = await repo.getVoiceMails();
    isVoiceMailsLoading = false;
    if (res is GetVoiceMailsResponseModel) {
      final fresh = res.voiceMails ?? const [];
      voiceMails = List.from(fresh);
      if (AppCache.instance.isReady) {
        AppCache.instance.voicemails.writeAll(voiceMails);
      }
    }
    update();
  }

  deleteVoiceMail(id) async {
    Get.back();
    CustomLoader.showLoader();
    var res = await repo.deleteVoicemail(id);
    Get.back();

    if (res is String) {
      CustomToast.showToast(res, true);
    } else {
      voiceMails.removeWhere((v) => v.msgId == id);
      if (AppCache.instance.isReady) {
        AppCache.instance.voicemails.remove(id?.toString() ?? '');
      }
      update();
      fetchVoiceMails();
    }
  }

  getDataList() {
    if (searchController.text.isEmpty) {
      return voiceMails;
    }
    if (searchController.text.isNotEmpty) {
      return voiceMails
          .where((element) => element.callerid!
              .toLowerCase()
              .contains(searchController.text.toLowerCase()))
          .toList();
    }
  }

  @override
  void onInit() {
    // TODO: implement onInit
    super.onInit();
    playerController = PlayerController();
    fetchVoiceMails();
  }

  downloadVoicemail(id) async {
    // Writing to getApplicationDocumentsDirectory() is in the app's
    // private sandbox — no storage permission required on any platform.
    // The legacy Permission.storage.request() that used to gate this code
    // returns "denied permanently" on Android 13+ and broke the feature
    // entirely.
    final apiId = await SharedPreferencesMethod.getString(StorageKeys.API_ID);
    final token =
        await SharedPreferencesMethod.getString(StorageKeys.REFRESH_TOKEN);
    final directory = await getApplicationDocumentsDirectory();
    final dir = directory.path;
    if (dir.isEmpty) {
      CustomToast.showToast('Could not locate storage directory', true);
      return;
    }
    savePath = '$dir/ITP Voicemails/voicemail_$id.mp3';
    try {
      Get.back();
      CustomLoader.showLoader();
      await Dio().download(
        '${Endpoints.DOWNLOAD_VOICE_MAIL_MESSAGES(apiId)}/$id?token=$token',
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            print('${(received / total * 100).toStringAsFixed(0)}%');
          }
        },
      );
      Get.back();
      CustomToast.showToast('Voicemail saved', false);
    } on DioError catch (_) {
      Get.back();
      savePath = '';
      CustomToast.showToast(
          'Something went wrong while downloading voicemail', true);
    } catch (_) {
      Get.back();
      CustomToast.showToast('Something went wrong', true);
    }
  }

  // initialiseAudio(String id) async {
  //   String? apiId = await SharedPreferencesMethod.getString(StorageKeys.API_ID);
  //   String? token =
  //       await SharedPreferencesMethod.getString(StorageKeys.REFRESH_TOKEN);

  //   voiceMailDuration = await player.setAudioSource(AudioSource.uri(Uri.parse(
  //       "${Endpoints.DOWNLOAD_VOICE_MAIL_MESSAGES(apiId)}/${id}?token=${token}")));
  // }
}
