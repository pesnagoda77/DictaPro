import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vosk_flutter/vosk_flutter.dart';

import 'services/vosk_custom_words_extended.dart';
import 'services/vosk_auto_correction_extended.dart';
import 'services/punctuation_service.dart';
import 'services/speaker_diarization.dart' as diarization;

class DialogueSegment {
  final String speaker;
  final String text;
  final double startTime;
  final double endTime;

  DialogueSegment({
    required this.speaker,
    required this.text,
    required this.startTime,
    required this.endTime,
  });

  Map<String, dynamic> toMap() => {
        'speaker': speaker,
        'text': text,
        'startTime': startTime,
        'endTime': endTime,
      };

  factory DialogueSegment.fromMap(Map<String, dynamic> map) => DialogueSegment(
        speaker: map['speaker'],
        text: map['text'],
        startTime: map['startTime'],
        endTime: map['endTime'],
      );
}

class TranscriptionResult {
  final String fullText;
  final List<DialogueSegment> segments;

  TranscriptionResult({
    required this.fullText,
    required this.segments,
  });
}

/// Разобранный заголовок WAV: позиция и размер блока data + формат.
class _WavInfo {
  final int dataOffset;
  final int dataSize;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  _WavInfo({
    required this.dataOffset,
    required this.dataSize,
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
  });

  bool get isVoskReady =>
      sampleRate == 16000 && channels == 1 && bitsPerSample == 16;
}

class TranscriptionService {
  static final TranscriptionService _instance =
      TranscriptionService._internal();
  factory TranscriptionService() => _instance;
  TranscriptionService._internal();

  final _vosk = VoskFlutterPlugin.instance();
  Recognizer? _recognizer;
  bool _isModelLoaded = false;
  static const _platform = MethodChannel('dictapro/convert');

  Future<void> initModel() async {
    if (_isModelLoaded) return;

    final modelPath = await ModelLoader()
        .loadFromAssets('assets/models/vosk-model-small-ru-0.22.zip');

    final model = await _vosk.createModel(modelPath);
    _recognizer = await _vosk.createRecognizer(
      model: model,
      sampleRate: 16000,
    );

    // Add custom words to improve recognition quality
    VoskCustomWordsExtended.initWords(_recognizer!);

    _isModelLoaded = true;
  }

  /// Потоковая транскрибация (память НЕ растёт с длиной записи).
  /// [onProgress] — 0.0..1.0 по объёму обработанного аудио.
  Future<TranscriptionResult> transcribeFile(
    String audioPath, {
    void Function(double progress)? onProgress,
  }) async {
    if (!_isModelLoaded) await initModel();
    await resetRecognizer(); // Сброс перед новой транскрибацией

    final ext = audioPath.toLowerCase().split('.').last;
    File sourceWav;
    final tempFilesToDelete = <File>[];

    if (ext == 'wav') {
      sourceWav = File(audioPath);
    } else {
      String convertPath = audioPath;

      // Очищаем ID3-теги из MP3 ПЕРЕД конвертацией (потоково, без чтения всего файла)
      if (ext == 'mp3') {
        final cleaned = await _stripMp3Tags(audioPath);
        if (cleaned != null) {
          convertPath = cleaned;
          tempFilesToDelete.add(File(cleaned));
        }
      }

      final tempDir = await getTemporaryDirectory();
      final tempWav =
          '${tempDir.path}/temp_convert_${DateTime.now().millisecondsSinceEpoch}.wav';

      final result = await _platform.invokeMethod<Map<dynamic, dynamic>>(
        'convertToWav',
        {'inputPath': convertPath, 'outputPath': tempWav},
      );

      if (result == null || result['success'] != true) {
        throw Exception(result?['error'] ?? 'Conversion failed');
      }
      sourceWav = File(tempWav);
      tempFilesToDelete.add(sourceWav);
    }

    try {
      final rawResults = await _processWavStreaming(
        sourceWav,
        onProgress: onProgress,
      );

      // Собираем полный текст
      String fullText = '';
      for (var result in rawResults) {
        if (result['text'] != null &&
            result['text'].toString().isNotEmpty) {
          fullText += ' ${result['text']}';
        }
      }
      fullText = fullText.trim();

      // Apply auto-correction for common recognition mistakes
      fullText = VoskAutoCorrectionExtended.correctText(fullText);
      // Add punctuation to transcription
      fullText = PunctuationService.addPunctuationToText(fullText);

      // Speaker diarization: build chunks from VOSK results with timestamps
      final chunks = _buildChunksFromResults(rawResults);
      final diarizationSegments =
          diarization.SpeakerDiarizationService.segmentSpeakers(chunks);
      final segments = _convertDiarizationSegments(diarizationSegments);

      // Apply punctuation to each segment's text
      final punctuatedSegments = segments
          .map((seg) => DialogueSegment(
                speaker: seg.speaker,
                text: PunctuationService.addPunctuationToText(seg.text),
                startTime: seg.startTime,
                endTime: seg.endTime,
              ))
          .toList();

      return TranscriptionResult(
        fullText: fullText,
        segments: punctuatedSegments,
      );
    } finally {
      // Чистим временные файлы
      for (final f in tempFilesToDelete) {
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
  }

  /// Разбор WAV-заголовка из первых байт файла.
  _WavInfo _parseWavHeader(Uint8List headerBytes) {
    if (headerBytes.length < 44) {
      throw Exception('WAV file too small');
    }
    if (String.fromCharCodes(headerBytes.sublist(0, 4)) != 'RIFF') {
      throw Exception('Not a valid WAV file');
    }
    final reader = ByteData.sublistView(headerBytes);
    var pos = 12;

    int? channels;
    int? sampleRate;
    int? bitsPerSample;
    int? dataOffset;
    int? dataSize;

    while (pos + 8 <= headerBytes.length) {
      final chunkId = String.fromCharCodes(headerBytes.sublist(pos, pos + 4));
      final chunkSize = reader.getUint32(pos + 4, Endian.little);

      if (chunkId == 'fmt ') {
        channels = reader.getUint16(pos + 10, Endian.little);
        sampleRate = reader.getUint32(pos + 12, Endian.little);
        bitsPerSample = reader.getUint16(pos + 22, Endian.little);
        pos += 8 + chunkSize;
      } else if (chunkId == 'data') {
        dataOffset = pos + 8;
        dataSize = chunkSize;
        break;
      } else {
        pos += 8 + chunkSize;
      }
    }

    if (channels == null ||
        sampleRate == null ||
        bitsPerSample == null ||
        dataOffset == null ||
        dataSize == null) {
      throw Exception('Invalid WAV header');
    }

    return _WavInfo(
      dataOffset: dataOffset,
      dataSize: dataSize,
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample,
    );
  }

  /// Потоковая подача WAV в VOSK: читаем файл кусками с диска,
  /// конвертируем в 16кГц mono 16-bit на лету (если нужно) и кормим распознаватель.
  /// Потребление памяти — константа (chunkSize), не зависит от длины записи.
  Future<List<Map<String, dynamic>>> _processWavStreaming(
    File wavFile, {
    void Function(double progress)? onProgress,
  }) async {
    const int chunkSize = 262144; // 256 KB
    final results = <Map<String, dynamic>>[];

    final raf = await wavFile.open();
    try {
      final fileLength = await wavFile.length();
      final headerLen = math.min(65536, fileLength);
      final headerBytes = await raf.read(headerLen);
      final info = _parseWavHeader(headerBytes);

      final dataStart = info.dataOffset;
      final dataEnd =
          math.min(dataStart + info.dataSize, fileLength);

      _StreamResampler? resampler;
      if (!info.isVoskReady) {
        resampler = _StreamResampler(
          inSampleRate: info.sampleRate,
          inChannels: info.channels,
          inBits: info.bitsPerSample,
        );
      }

      await raf.setPosition(dataStart);
      var pos = dataStart;
      var chunkCount = 0;

      while (pos < dataEnd) {
        final toRead = math.min(chunkSize, dataEnd - pos);
        final chunk = await raf.read(toRead);
        if (chunk.isEmpty) break;
        pos += chunk.length;
        chunkCount++;

        final pcm = resampler == null ? chunk : resampler.feed(chunk);
        if (pcm.isNotEmpty) {
          try {
            final resultReady =
                await _recognizer!.acceptWaveformBytes(pcm);
            if (resultReady) {
              final resultJson = await _recognizer!.getResult();
              results.add(jsonDecode(resultJson));
            }
          } catch (e) {
            print('VOSK chunk $chunkCount error: $e');
          }
        }

        final total = dataEnd - dataStart;
        if (total > 0) {
          onProgress?.call((pos - dataStart) / total);
        }

        // Small delay to let VOSK native process
        await Future.delayed(const Duration(milliseconds: 5));
      }

      final tail = resampler == null ? Uint8List(0) : resampler.flush();
      if (tail.isNotEmpty) {
        try {
          await _recognizer!.acceptWaveformBytes(tail);
        } catch (e) {
          print('VOSK tail error: $e');
        }
      }
      try {
        final finalJson = await _recognizer!.getFinalResult();
        results.add(jsonDecode(finalJson));
      } catch (e) {
        print('VOSK final error: $e');
      }
    } finally {
      await raf.close();
    }

    return results;
  }

  /// Потоковое удаление ID3-тегов MP3 (без чтения файла целиком).
  /// Возвращает путь к очищенному файлу или null, если тегов нет.
  Future<String?> _stripMp3Tags(String path) async {
    try {
      final file = File(path);
      final length = await file.length();
      if (length < 10) return null;

      final raf = await file.open();
      int startOffset = 0;
      int endOffset = length;
      try {
        final head = await raf.read(10);
        if (head.length >= 10 &&
            String.fromCharCodes(head.sublist(0, 3)) == 'ID3') {
          final b6 = head[6], b7 = head[7], b8 = head[8], b9 = head[9];
          final tagSize = ((b6 & 0x7F) << 21) |
              ((b7 & 0x7F) << 14) |
              ((b8 & 0x7F) << 7) |
              (b9 & 0x7F);
          startOffset = 10 + tagSize;
        }
        if (length >= 128) {
          await raf.setPosition(length - 128);
          final tail = await raf.read(3);
          if (tail.length == 3 &&
              String.fromCharCodes(tail) == 'TAG') {
            endOffset = length - 128;
          }
        }
      } finally {
        await raf.close();
      }

      if (startOffset == 0 && endOffset == length) return null;
      if (endOffset <= startOffset) {
        throw Exception('MP3 contains only metadata, no audio data found');
      }

      final tempDir = await getTemporaryDirectory();
      final cleanMp3 =
          '${tempDir.path}/temp_clean_${DateTime.now().millisecondsSinceEpoch}.mp3';

      // Копируем диапазон потоково
      final src = await file.open();
      final dst = File(cleanMp3).openWrite();
      try {
        await src.setPosition(startOffset);
        var remaining = endOffset - startOffset;
        const buf = 262144;
        while (remaining > 0) {
          final toRead = math.min(buf, remaining);
          final chunk = await src.read(toRead);
          if (chunk.isEmpty) break;
          dst.add(chunk);
          remaining -= chunk.length;
        }
      } finally {
        await src.close();
        await dst.close();
      }
      return cleanMp3;
    } catch (e) {
      print('MP3 tag strip error: $e');
      return null;
    }
  }

  List<DialogueSegment> _convertDiarizationSegments(
    List<diarization.DialogueSegment> diarizationSegments,
  ) {
    return diarizationSegments.map((seg) {
      final speakerLabel = seg.speaker.contains('Speaker 2') ? 'B' : 'A';
      return DialogueSegment(
        speaker: speakerLabel,
        text: seg.text,
        startTime: seg.chunks.isNotEmpty ? seg.chunks.first.startTime : 0.0,
        endTime: seg.chunks.isNotEmpty ? seg.chunks.last.endTime : 0.0,
      );
    }).toList();
  }

  List<diarization.TranscriptionChunk> _buildChunksFromResults(
    List<Map<String, dynamic>> results,
  ) {
    final List<diarization.TranscriptionChunk> chunks = [];
    const bytesPerSecond = 32000; // 16000 Hz * 2 bytes
    const chunkSize = 8192;
    const secondsPerChunk = chunkSize / bytesPerSecond; // ~0.256s

    double currentTime = 0.0;

    for (var result in results) {
      final text = (result['text'] as String? ?? '').trim();
      if (text.isEmpty) {
        currentTime += secondsPerChunk;
        continue;
      }

      chunks.add(diarization.TranscriptionChunk(
        text: text,
        startTime: currentTime,
        endTime: currentTime + secondsPerChunk,
        pitch: null,
        volume: null,
        confidence: (result['confidence'] as num?)?.toDouble() ?? 0.8,
      ));
      currentTime += secondsPerChunk;
    }

    return chunks;
  }

  // ========== Live Transcription ==========

  Future<Map<String, dynamic>> getPartialResult() async {
    if (!_isModelLoaded) await initModel();
    final partialJson = await _recognizer!.getPartialResult();
    return jsonDecode(partialJson);
  }

  Future<void> acceptWaveform(Uint8List chunk) async {
    if (!_isModelLoaded) await initModel();
    await _recognizer!.acceptWaveformBytes(chunk);
  }

  Future<void> resetRecognizer() async {
    if (_recognizer != null) {
      await _recognizer!.reset();
    }
  }

  void dispose() {
    _recognizer?.dispose();
  }
}

/// Потоковый конвертер PCM → 16 кГц mono 16-bit.
/// Держит хвост неполных фреймов и фазу ресемплинга между чанками.
class _StreamResampler {
  final int inSampleRate;
  final int inChannels;
  final int inBits;

  final int _bytesPerSample;
  final int _frameSize;
  final double _ratio; // inSampleRate / 16000

  final List<int> _carry = <int>[];
  double _phase = 0.0;

  _StreamResampler({
    required this.inSampleRate,
    required this.inChannels,
    required this.inBits,
  })  : _bytesPerSample = inBits ~/ 8,
        _frameSize = (inBits ~/ 8) * inChannels,
        _ratio = inSampleRate / 16000.0;

  Uint8List feed(Uint8List chunk) {
    // Собираем буфер: хвост + новый чанк
    final bytes = Uint8List(_carry.length + chunk.length);
    bytes.setAll(0, _carry);
    bytes.setAll(_carry.length, chunk);
    _carry.clear();

    final totalFrames = bytes.length ~/ _frameSize;
    if (totalFrames == 0) {
      _carry.addAll(bytes);
      return Uint8List(0);
    }

    final out = BytesBuilder();

    // Сколько выходных сэмплов можно сделать, начиная с текущей фазы
    var phase = _phase;
    while (true) {
      final srcFrame = phase.floor();
      if (srcFrame >= totalFrames) break;
      final sample = _readFrameMono(bytes, srcFrame);
      final bd = ByteData(2);
      bd.setInt16(0, sample, Endian.little);
      out.add(bd.buffer.asUint8List());
      phase += _ratio;
    }
    _phase = phase - totalFrames;

    // Хвост неполных фреймов переносим в carry
    final usedBytes = totalFrames * _frameSize;
    _carry.addAll(bytes.sublist(usedBytes));

    return out.toBytes();
  }

  Uint8List flush() {
    // Всё, что осталось — игнорируем (неполный фрейм)
    _carry.clear();
    return Uint8List(0);
  }

  int _readFrameMono(Uint8List bytes, int frame) {
    final base = frame * _frameSize;
    double sum = 0;
    for (var ch = 0; ch < inChannels; ch++) {
      final pos = base + ch * _bytesPerSample;
      if (pos + _bytesPerSample > bytes.length) break;
      double v;
      if (inBits == 8) {
        v = bytes[pos] - 128;
      } else if (inBits == 16) {
        v = ByteData.sublistView(bytes, pos, pos + 2)
            .getInt16(0, Endian.little)
            .toDouble();
      } else if (inBits == 24) {
        final b0 = bytes[pos];
        final b1 = bytes[pos + 1];
        final b2 = bytes[pos + 2];
        var val = b0 | (b1 << 8) | (b2 << 16);
        if (val & 0x800000 != 0) val -= 0x1000000;
        v = val.toDouble();
      } else if (inBits == 32) {
        v = ByteData.sublistView(bytes, pos, pos + 4)
            .getInt32(0, Endian.little)
            .toDouble();
      } else {
        v = 0;
      }
      sum += v;
    }
    return (sum / inChannels).toInt().clamp(-32768, 32767);
  }
}
