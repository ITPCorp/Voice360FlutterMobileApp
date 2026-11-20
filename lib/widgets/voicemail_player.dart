import 'package:flutter/material.dart';
import 'package:itp_voice/design/v360.dart';
import 'package:itp_voice/repo/shares_preference_repo.dart';
import 'package:itp_voice/routes.dart';
import 'package:itp_voice/storage_keys.dart';

class VoiceMailPlayer extends StatelessWidget {
  final String? id;
  final int? durationSeconds;

  const VoiceMailPlayer({super.key, this.id, this.durationSeconds});

  @override
  Widget build(BuildContext context) {
    final apiId = SharedPreferencesMethod.storage.getString(StorageKeys.API_ID);
    final token =
        SharedPreferencesMethod.storage.getString(StorageKeys.REFRESH_TOKEN);
    if (id == null || id!.isEmpty || apiId == null || token == null) {
      return const Text('Voicemail audio is unavailable.');
    }
    final uri = Uri.parse(Endpoints.DOWNLOAD_VOICE_MAIL_MESSAGES(apiId));
    return V360AudioPlayer.compact(
      url: uri.replace(
        pathSegments: [...uri.pathSegments, id!],
        queryParameters: {'token': token},
      ).toString(),
      durationSeconds: durationSeconds,
      filename: 'voicemail.mp3',
    );
  }
}
