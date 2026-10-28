import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'services/share_helper.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'audio_service.dart';
import 'app_strings.dart';

class ExportService {
  static Future<void> shareText(String text) async {
    await Share.share(text, subject: AppStrings.tGlobal('share_subject_transcript'));
  }

  static Future<void> copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  static Future<void> shareAudioFile(String filePath) async {
    await shareFileWithReturn(filePath, text: AppStrings.tGlobal('share_audio_caption'));
  }

  /// Task 117 П.7 / 118 П.3: имя файла по умолчанию —
  /// «<санитайзнутый title> — <дата>.<ext>». Санитайзер общий с миграцией
  /// имён (audio_service) — кириллица сохраняется.
  static String exportFileName(Recording rec, String ext) {
    final safe = AudioService.sanitizeFileName(
        (rec.title ?? 'transcript').trim());
    final date = DateFormat('dd.MM.yyyy').format(rec.createdAt);
    return '$safe — $date.$ext';
  }

  /// Task 117 П.7: «Сохранить» — системный диалог выбора места и имени
  /// (FilePicker.saveFile с bytes). Возвращает true, если файл сохранён.
  static Future<bool> saveWithPicker({
    required Recording rec,
    required String ext,
    required Uint8List bytes,
  }) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: AppStrings.tGlobal('export_save_dialog_title'),
      fileName: exportFileName(rec, ext),
      type: FileType.custom,
      allowedExtensions: [ext],
      bytes: bytes,
    );
    return path != null && path.isNotEmpty;
  }

  static Future<bool> saveTxt(Recording rec) async {
    final text = formatTranscriptTxt(rec);
    return saveWithPicker(rec: rec, ext: 'txt', bytes: utf8.encode(text));
  }

  static Future<bool> saveHtml(Recording rec) async {
    final text = formatTranscriptHtml(rec);
    return saveWithPicker(rec: rec, ext: 'html', bytes: utf8.encode(text));
  }

  static Future<bool> savePdf(Recording rec) async {
    // Task 118 П.3: перед генерацией перечитываем запись из базы — в списке
    // на главной может лежать устаревшая копия (транскрипция обновилась
    // после «Заново»), а PDF обязан содержать ПОЛНЫЙ актуальный текст.
    final fresh = AudioService().getRecordingById(rec.id) ?? rec;
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
                AppStrings.tGlobal('export_title'),
                style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: ttf),
              ),
              pw.SizedBox(height: 8),
              pw.Text(AppStrings.tfGlobal('export_label_date', {'v': '${fresh.createdAt}'}), style: pw.TextStyle(fontSize: 12, font: ttf)),
              pw.Text(AppStrings.tfGlobal('export_label_duration_sec', {'v': '${fresh.durationMs ~/ 1000}'}), style: pw.TextStyle(fontSize: 12, font: ttf)),
              pw.Divider(),
              pw.SizedBox(height: 8),
              if (fresh.segments != null && fresh.segments!.isNotEmpty)
                ...fresh.segments!.asMap().entries.map((e) {
                  final no = e.key + 1;
                  final seg = e.value;
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4),
                    child: pw.Text(
                      '[${AppStrings.tfGlobal('dialogue_speaker', {'n': '$no'})}] ${seg['text']}',
                      style: pw.TextStyle(fontSize: 14, font: ttf),
                    ),
                  );
                })
              else
                pw.Text(
                  fresh.transcription ?? AppStrings.tGlobal('no_text'),
                  style: pw.TextStyle(fontSize: 14, font: ttf),
                ),
            ],
          );
        },
      ),
    );
    return saveWithPicker(rec: rec, ext: 'pdf', bytes: await pdf.save());
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
    await shareFileWithReturn(path, text: AppStrings.tGlobal('share_subject_transcript'));
  }

  static String formatTranscriptTxt(Recording rec) {
    final buffer = StringBuffer();
    buffer.writeln(AppStrings.tGlobal('export_title'));
    buffer.writeln(AppStrings.tfGlobal('export_label_date', {'v': '${rec.createdAt}'}));
    buffer.writeln(AppStrings.tfGlobal('export_label_duration_sec', {'v': '${rec.durationMs ~/ 1000}'}));
    buffer.writeln('=' * 40);
    buffer.writeln();

    if (rec.segments != null && rec.segments!.isNotEmpty) {
      var phraseNo = 0;
      for (var seg in rec.segments!) {
        phraseNo++;
        final time = seg['time'] != null ? _fmtTime(seg['time'] as int) : '';
        final label = AppStrings.tfGlobal('dialogue_speaker', {'n': '$phraseNo'});
        buffer.writeln(time.isNotEmpty ? '[$time] $label: ${seg['text']}' : '$label: ${seg['text']}');
      }
    } else {
      buffer.writeln(rec.transcription ?? AppStrings.tGlobal('no_text'));
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
    buffer.writeln(AppStrings.tGlobal('export_title'));
    buffer.writeln(AppStrings.tfGlobal('export_label_date', {'v': '${rec.createdAt}'}));
    buffer.writeln(AppStrings.tfGlobal('export_label_duration_sec', {'v': '${rec.durationMs ~/ 1000}'}));
    buffer.writeln('=' * 40);
    buffer.writeln();

    if (rec.segments != null && rec.segments!.isNotEmpty) {
      var phraseNo = 0;
      for (var seg in rec.segments!) {
        phraseNo++;
        final label = AppStrings.tfGlobal('dialogue_speaker', {'n': '$phraseNo'});
        buffer.writeln('$label: ${seg['text']}');
      }
    } else {
      buffer.writeln(rec.transcription ?? AppStrings.tGlobal('no_text'));
    }

    return buffer.toString();
  }

  /// Task 117 П.7: читаемый HTML — заголовок (название записи), мета
  /// (дата, длительность), фразы списком. Светлая тема, без «пузырей».
  static String formatTranscriptHtml(Recording rec) {
    final title = (rec.title ?? '').trim();
    final date = DateFormat('dd.MM.yyyy HH:mm').format(rec.createdAt);
    final dur = _fmtTime(rec.durationMs);
    final esc = (String? s) => (s ?? '')
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');

    final buffer = StringBuffer();
    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln('<html><head><meta charset="UTF-8">');
    buffer.writeln('<meta name="viewport" content="width=device-width, initial-scale=1">');
    buffer.writeln('<title>${esc(title.isEmpty ? AppStrings.tGlobal('export_title') : title)}</title>');
    buffer.writeln('<style>');
    buffer.writeln('body{font-family:Georgia,serif;max-width:720px;margin:24px auto;padding:0 16px;color:#1a1a1a;line-height:1.5;}');
    buffer.writeln('h1{font-family:Arial,sans-serif;font-size:22px;margin:0 0 4px;}');
    buffer.writeln('.meta{color:#666;font-size:13px;font-family:Arial,sans-serif;margin-bottom:20px;}');
    buffer.writeln('.phrase{margin:0 0 12px;}');
    buffer.writeln('.time{color:#888;font-size:12px;font-family:Arial,sans-serif;}');
    buffer.writeln('.speaker{font-weight:bold;font-size:13px;font-family:Arial,sans-serif;}');
    buffer.writeln('</style></head><body>');
    buffer.writeln('<h1>${esc(title.isEmpty ? AppStrings.tGlobal('export_title') : title)}</h1>');
    buffer.writeln('<div class="meta">${esc(date)} · ${esc(dur)}</div>');

    if (rec.segments != null && rec.segments!.isNotEmpty) {
      var phraseNo = 0;
      for (var seg in rec.segments!) {
        phraseNo++;
        final t = seg['time'] as int?;
        final time = t != null ? _fmtTime(t) : '';
        final label = AppStrings.tfGlobal('dialogue_speaker', {'n': '$phraseNo'});
        buffer.writeln('<div class="phrase">');
        if (time.isNotEmpty) {
          buffer.writeln('<span class="time">[$time]</span> ');
        }
        buffer.writeln('<span class="speaker">${esc(label)}:</span> ${esc(seg['text'] as String?)}');
        buffer.writeln('</div>');
      }
    } else {
      buffer.writeln('<p>${esc(rec.transcription ?? AppStrings.tGlobal('no_text'))}</p>');
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
                AppStrings.tGlobal('export_title'),
                style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, font: ttf),
              ),
              pw.SizedBox(height: 8),
              pw.Text(AppStrings.tfGlobal('export_label_date', {'v': '${rec.createdAt}'}), style: pw.TextStyle(fontSize: 12, font: ttf)),
              pw.Text(AppStrings.tfGlobal('export_label_duration_sec', {'v': '${rec.durationMs ~/ 1000}'}), style: pw.TextStyle(fontSize: 12, font: ttf)),
              pw.Divider(),
              pw.SizedBox(height: 8),
              if (rec.segments != null && rec.segments!.isNotEmpty)
                // Task 115: номер фразы = index+1 (как в TXT/HTML), а не
                // seg['speaker'] — у всех сегментов он «Фраза 1».
                ...rec.segments!.asMap().entries.map((e) {
                  final no = e.key + 1;
                  final seg = e.value;
                  return pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4),
                    child: pw.Text(
                      '[${AppStrings.tfGlobal('dialogue_speaker', {'n': '$no'})}] ${seg['text']}',
                      style: pw.TextStyle(fontSize: 14, font: ttf),
                    ),
                  );
                })
              else
                pw.Text(
                  rec.transcription ?? AppStrings.tGlobal('no_text'),
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
