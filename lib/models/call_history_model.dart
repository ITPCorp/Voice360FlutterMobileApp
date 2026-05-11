class CallHistory {
  String? name;
  DateTime? time;
  bool? isIncoming;
  String? numberToDial;
  bool? isMissed;

  /// CDR primary key — needed to build the recording-download URL.
  int? cdrPk;

  /// Call duration in seconds.
  int? duration;

  /// Server-side recording filename. Presence implies a downloadable recording.
  String? callRecordingFilename;

  /// Raw AWS-Transcribe-Call-Analytics JSON string (parsed lazily on tap).
  String? callTranscription;

  /// True for AI-handled calls.
  bool aiCall;

  CallHistory({
    this.name,
    this.time,
    this.isIncoming,
    this.isMissed,
    this.numberToDial,
    this.cdrPk,
    this.duration,
    this.callRecordingFilename,
    this.callTranscription,
    this.aiCall = false,
  });

  bool get hasRecording =>
      callRecordingFilename != null && callRecordingFilename!.isNotEmpty;
  bool get hasTranscript =>
      callTranscription != null && callTranscription!.trim().isNotEmpty;

  Map<String, dynamic> toMap() => {
        'name': name,
        'time': time?.millisecondsSinceEpoch,
        'isIncoming': isIncoming,
        'isMissed': isMissed,
        'numberToDial': numberToDial,
        'cdrPk': cdrPk,
        'duration': duration,
        'callRecordingFilename': callRecordingFilename,
        'callTranscription': callTranscription,
        'aiCall': aiCall,
      };

  factory CallHistory.fromMap(Map<dynamic, dynamic> map) => CallHistory(
        name: map['name'] as String?,
        time: map['time'] is int
            ? DateTime.fromMillisecondsSinceEpoch(map['time'] as int)
            : null,
        isIncoming: map['isIncoming'] as bool?,
        isMissed: map['isMissed'] as bool?,
        numberToDial: map['numberToDial'] as String?,
        cdrPk: (map['cdrPk'] as num?)?.toInt(),
        duration: (map['duration'] as num?)?.toInt(),
        callRecordingFilename: map['callRecordingFilename'] as String?,
        callTranscription: map['callTranscription'] as String?,
        aiCall: map['aiCall'] == true,
      );
}
