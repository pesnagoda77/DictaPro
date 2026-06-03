import 'package:flutter/material.dart';

/// Wrapper model for recording details passed to SummaryPage.
/// Bridges between the old Recording model and the new SummaryPage API.
class RecordingDetailsModel {
  final String? summary;
  final String? transcript;
  final DateTime? dateTime;
  final Duration? duration;
  final String? filePath;
  final String title;

  RecordingDetailsModel({
    this.summary,
    this.transcript,
    this.dateTime,
    this.duration,
    this.filePath,
    required this.title,
  });

  factory RecordingDetailsModel.fromRecording(Map<String, dynamic> recording) {
    return RecordingDetailsModel(
      summary: recording['summary']?.toString(),
      transcript: recording['transcription']?.toString() ?? recording['transcript']?.toString(),
      dateTime: recording['createdAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(recording['createdAt'])
          : null,
      duration: recording['durationMs'] != null
          ? Duration(milliseconds: recording['durationMs'] as int)
          : null,
      filePath: recording['filePath']?.toString(),
      title: recording['title']?.toString() ?? 'Без названия',
    );
  }
}
