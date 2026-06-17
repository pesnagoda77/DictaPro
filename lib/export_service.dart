import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'audio_service.dart';

class ExportService {
  static Future<void> shareText(String text) async {
    await Share.share(text, subject: 'Транскрипция записи');
  }

  static Future<void> copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  static Future<void> shareAudioFile(String filePath) async {
    await Share.shareXFiles([XFile(filePath)], text: 'Аудиозапись из ДиктаПро');
  }

  static Future<String> saveAsTxt(String text, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/exports/$fileName.txt';

    await Directory('${dir.path}/exports').create(recursive: true);

    final file = File(path);
    await file.writeAsString(text);
    return path;
  }

  static Future<void> shareFile(String text, String fileName) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$fileName';
    final file = File(path);
    await file.writeAsString(text);
    await Share.shareXFiles([XFile(path)], text: 'Транскрипция записи');
  }

  static String formatTranscriptTxt(Recording rec) {
    final buffer = StringBuffer();
    buffer.writeln('ДиктаПро - Транскрипция');
    buffer.writeln('Дата: ${rec.createdAt}');
    buffer.writeln('Длительность: ${rec.durationMs ~/ 1000} сек');
    buffer.writeln('=' * 40);
    buffer.writeln();

    if (rec.segments != null && rec.segments!.isNotEmpty) {
      for (var seg in rec.segments!) {
        final time = seg['time'] != null ? _fmtTime(seg['time'] as int) : '';
        buffer.writeln(time.isNotEmpty ? '[$time] ${seg['speaker']}: ${seg['text']}' : '[${seg['speaker']}] ${seg['text']}');
      }
    } else {
      buffer.writeln(rec.transcription ?? 'Нет текста');
    }

    return buffer.toString();
  }

  static String _fmtTime(int ms) {
    final s = ms ~/ 1000;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  static String formatTranscript(Recording rec) {
    final buffer = StringBuffer();
    buffer.writeln('ДиктаПро — Транскрипция');
    buffer.writeln('Дата: ${rec.createdAt}');
    buffer.writeln('Длительность: ${rec.durationMs ~/ 1000} сек');
    buffer.writeln('=' * 40);
    buffer.writeln();

    if (rec.segments != null && rec.segments!.isNotEmpty) {
      for (var seg in rec.segments!) {
        buffer.writeln('[${seg['speaker']}] ${seg['text']}');
      }
    } else {
      buffer.writeln(rec.transcription ?? 'Нет текста');
    }

    return buffer.toString();
  }

  static String formatTranscriptHtml(Recording rec) {
    final buffer = StringBuffer();
    buffer.writeln('<html><head><meta charset="UTF-8"><style>');
    buffer.writeln(
        'body{font-family:Arial,sans-serif;max-width:600px;margin:20px auto;padding:20px;background:#1a1a2e;color:#fff;}');
    buffer.writeln('.header{color:#888;font-size:12px;margin-bottom:20px;}');
    buffer.writeln(
        '.speaker-a{background:#1e3a5f;padding:10px 15px;border-radius:12px;margin:8px 0;text-align:left;}');
    buffer.writeln(
        '.speaker-b{background:#1e4a3a;padding:10px 15px;border-radius:12px;margin:8px 0;text-align:right;}');
    buffer
        .writeln('.label{font-size:10px;font-weight:bold;margin-bottom:4px;}');
    buffer.writeln('.text{font-size:14px;}');
    buffer.writeln('</style></head><body>');
    buffer.writeln(
        '<div class="header">ДиктаПро | ${rec.createdAt} | ${rec.durationMs ~/ 1000} сек</div>');

    if (rec.segments != null && rec.segments!.isNotEmpty) {
      for (var seg in rec.segments!) {
        final isA = seg['speaker'] == 'A';
        buffer.writeln('<div class="${isA ? 'speaker-a' : 'speaker-b'}">');
        buffer.writeln('<div class="label">Говорящий ${seg['speaker']}</div>');
        buffer.writeln('<div class="text">${seg['text']}</div>');
        buffer.writeln('</div>');
      }
    } else {
      buffer.writeln(
          '<div class="speaker-a"><div class="text">${rec.transcription ?? 'Нет текста'}</div></div>');
    }

    buffer.writeln('</body></html>');
    return buffer.toString();
  }

  static Future<String> exportAsPdf(Recording rec) async {
    final fontData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final ttf = pw.Font.ttf(fontData);

    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'ДиктаПро — Транскрипция',
                style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: ttf),
              ),
              pw.SizedBox(height: 8),
              pw.Text('Дата: ${rec.createdAt}', style: pw.TextStyle(fontSize: 12, font: ttf)),
              pw.Text('Длительность: ${rec.durationMs ~/ 1000} сек', style: pw.TextStyle(fontSize: 12, font: ttf)),
              pw.Divider(),
              pw.SizedBox(height: 8),
              if (rec.segments != null && rec.segments!.isNotEmpty)
                ...rec.segments!.map((seg) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 4),
                      child: pw.Text(
                        '[${seg['speaker']}] ${seg['text']}',
                        style: pw.TextStyle(fontSize: 14, font: ttf),
                      ),
                    ))
              else
                pw.Text(
                  rec.transcription ?? 'Нет текста',
                  style: pw.TextStyle(fontSize: 14, font: ttf),
                ),
            ],
          );
        },
      ),
    );

    final dir = await getTemporaryDirectory();
    final safeTitle = (rec.title ?? 'transcript').replaceAll(RegExp(r'[^\w\s\-]'), '_');
    final path = '${dir.path}/${safeTitle}.pdf';
    final file = File(path);
    await file.writeAsBytes(await pdf.save());
    return path;
  }
}
