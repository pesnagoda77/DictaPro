import 'package:intl/intl.dart';

String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;
  
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

String formatDateTime(DateTime dateTime) {
  return DateFormat('dd.MM.yyyy HH:mm').format(dateTime);
}

String formatDate(DateTime dateTime) {
  return DateFormat('dd.MM.yyyy').format(dateTime);
}

String formatTime(DateTime dateTime) {
  return DateFormat('HH:mm').format(dateTime);
}

String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
