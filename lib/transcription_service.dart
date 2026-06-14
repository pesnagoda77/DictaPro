import 'dart:convert';
import 'dart:io';
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

  Future<TranscriptionResult> transcribeFile(String audioPath) async {
    if (!_isModelLoaded) await initModel();
    await resetRecognizer(); // Сброс перед новой транскрибацией

    final ext = audioPath.toLowerCase().split('.').last;
    Uint8List audioBytes;

    if (ext == 'wav') {
      final wavBytes = await File(audioPath).readAsBytes();
      // Конвертируем любой WAV в 16kHz mono 16-bit PCM
      audioBytes = _convertWavToPcm16_16k_mono(wavBytes);
    } else {
      String convertPath = audioPath;

      // Очищаем ID3-теги из MP3 перед конвертацией
      if (ext == 'mp3') {
        final fileBytes = await File(audioPath).readAsBytes();
        int startOffset = 0;
        int endOffset = fileBytes.length;

        if (fileBytes.length >= 3) {
          final header = String.fromCharCodes(fileBytes.sublist(0, 3));
          // ID3v2 в начале файла — пропускаем тег
          if (header == 'ID3') {
            if (fileBytes.length >= 10) {
              final b6 = fileBytes[6];
              final b7 = fileBytes[7];
              final b8 = fileBytes[8];
              final b9 = fileBytes[9];
              final tagSize = ((b6 & 0x7F) << 21) | ((b7 & 0x7F) << 14) | ((b8 & 0x7F) << 7) | (b9 & 0x7F);
              startOffset = 10 + tagSize;
            }
          }
          // ID3v1 в конце файла — отрезаем последние 128 байт
          if (fileBytes.length >= 128) {
            final tail = String.fromCharCodes(fileBytes.sublist(fileBytes.length - 128, fileBytes.length - 125));
            if (tail == 'TAG') {
              endOffset = fileBytes.length - 128;
            }
          }
        }

        // Если есть теги — создаём чистый временный MP3
        if (startOffset > 0 || endOffset < fileBytes.length) {
          if (endOffset <= startOffset) {
            throw Exception('MP3 contains only metadata, no audio data found');
          }
          final tempDir = await getTemporaryDirectory();
          final cleanMp3 = '${tempDir.path}/temp_clean_${DateTime.now().millisecondsSinceEpoch}.mp3';
          await File(cleanMp3).writeAsBytes(fileBytes.sublist(startOffset, endOffset));
          convertPath = cleanMp3;
        }
      }

      final tempDir = await getTemporaryDirectory();
      final tempWav = '${tempDir.path}/temp_convert_${DateTime.now().millisecondsSinceEpoch}.wav';

      final result = await _platform.invokeMethod<Map<dynamic, dynamic>>(
        'convertToWav',
        {'inputPath': convertPath, 'outputPath': tempWav},
      );

      if (result == null || result['success'] != true) {
        throw Exception(result?['error'] ?? 'Conversion failed');
      }

      final wavBytes = await File(tempWav).readAsBytes();
      audioBytes = _convertWavToPcm16_16k_mono(wavBytes);
      await File(tempWav).delete();

      // Удаляем временный очищенный MP3, если создавали
      if (convertPath != audioPath) {
        await File(convertPath).delete();
      }
    }

    final rawResults = await _processAudioRaw(audioBytes);

    // Собираем полный текст
    String fullText = '';
    for (var result in rawResults) {
      if (result['text'] != null && result['text'].toString().isNotEmpty) {
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
    final diarizationSegments = diarization.SpeakerDiarizationService.segmentSpeakers(chunks);
    final segments = _convertDiarizationSegments(diarizationSegments);

    // Apply punctuation to each segment's text
    final punctuatedSegments = segments.map((seg) => DialogueSegment(
      speaker: seg.speaker,
      text: PunctuationService.addPunctuationToText(seg.text),
      startTime: seg.startTime,
      endTime: seg.endTime,
    )).toList();

    return TranscriptionResult(
      fullText: fullText,
      segments: punctuatedSegments,
    );
  }

  Future<List<Map<String, dynamic>>> _processAudioRaw(
      Uint8List audioBytes) async {
    final List<Map<String, dynamic>> results = [];
    int chunkSize = 262144; // 8 seconds 16kHz mono 16-bit = 256KB
    int pos = 0;
    int chunkCount = 0;

    while (pos + chunkSize < audioBytes.length) {
      final chunk = Uint8List.sublistView(audioBytes, pos, pos + chunkSize);
      chunkCount++;

      try {
        final resultReady = await _recognizer!.acceptWaveformBytes(chunk);
        pos += chunkSize;

        if (resultReady) {
          final resultJson = await _recognizer!.getResult();
          results.add(jsonDecode(resultJson));
        }
      } catch (e) {
        print('VOSK chunk $chunkCount error: $e');
        pos += chunkSize;
      }

      // Small delay to let VOSK native process and reduce crash risk
      await Future.delayed(Duration(milliseconds: 10));
    }

    final lastChunk = Uint8List.sublistView(audioBytes, pos, audioBytes.length);
    try {
      await _recognizer!.acceptWaveformBytes(lastChunk);
      final finalJson = await _recognizer!.getFinalResult();
      results.add(jsonDecode(finalJson));
    } catch (e) {
      print('VOSK final error: $e');
    }

    return results;
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

  // ========== WAV конвертер: любой WAV → 16kHz mono 16-bit PCM ==========

  Uint8List _convertWavToPcm16_16k_mono(Uint8List wavBytes) {
    if (wavBytes.length < 44) {
      throw Exception('WAV file too small');
    }

    final reader = ByteData.sublistView(wavBytes);
    var pos = 0;

    // RIFF header
    if (String.fromCharCodes(wavBytes.sublist(0, 4)) != 'RIFF') {
      throw Exception('Not a valid WAV file');
    }
    pos += 12; // skip RIFF...WAVE

    int? channels;
    int? sampleRate;
    int? bitsPerSample;
    int? dataOffset;
    int? dataSize;

    // Parse chunks
    while (pos + 8 <= wavBytes.length) {
      final chunkId = String.fromCharCodes(wavBytes.sublist(pos, pos + 4));
      final chunkSize = reader.getUint32(pos + 4, Endian.little);

      if (chunkId == 'fmt ') {
        channels = reader.getUint16(pos + 10, Endian.little);
        sampleRate = reader.getUint32(pos + 12, Endian.little);
        bitsPerSample = reader.getUint16(pos + 22, Endian.little);
        pos += 8 + chunkSize;
      } else if (chunkId == 'data') {
        dataOffset = pos + 8;
        dataSize = chunkSize;
        break; // data is the last chunk we care about
      } else {
        pos += 8 + chunkSize;
      }
    }

    if (channels == null || sampleRate == null || bitsPerSample == null ||
        dataOffset == null || dataSize == null) {
      throw Exception('Invalid WAV header');
    }

    // If already 16kHz mono 16-bit — just skip header and return data portion
    if (sampleRate == 16000 && channels == 1 && bitsPerSample == 16) {
      final end = (dataOffset + dataSize).clamp(0, wavBytes.length);
      return Uint8List.sublistView(wavBytes, dataOffset, end);
    }

    // Clamp dataSize to actual file bounds
    final actualDataSize = (dataOffset + dataSize > wavBytes.length)
        ? wavBytes.length - dataOffset
        : dataSize;

    return _resampleAndConvert(
      wavBytes,
      dataOffset,
      actualDataSize,
      sampleRate,
      channels,
      bitsPerSample,
    );
  }

  Uint8List _resampleAndConvert(
    Uint8List bytes,
    int offset,
    int length,
    int inSampleRate,
    int inChannels,
    int inBits,
  ) {
    final outSampleRate = 16000;
    final outChannels = 1;
    final outBits = 16;

    // Total input samples (per channel)
    final bytesPerSample = inBits ~/ 8;
    final totalInputFrames = length ~/ (bytesPerSample * inChannels);
    if (totalInputFrames == 0) return Uint8List(0);

    final ratio = inSampleRate / outSampleRate;
    final totalOutputFrames = (totalInputFrames / ratio).ceil();

    final result = BytesBuilder();

    for (int i = 0; i < totalOutputFrames; i++) {
      final srcFrame = (i * ratio).toInt().clamp(0, totalInputFrames - 1);
      final srcBytePos = offset + srcFrame * bytesPerSample * inChannels;

      // Read and average all channels to mono
      double sampleSum = 0;
      for (int ch = 0; ch < inChannels; ch++) {
        final pos = srcBytePos + ch * bytesPerSample;
        if (pos + bytesPerSample > bytes.length) break;

        double sampleVal;
        if (inBits == 8) {
          sampleVal = bytes[pos] - 128; // unsigned to signed
        } else if (inBits == 16) {
          sampleVal = ByteData.sublistView(bytes, pos, pos + 2)
              .getInt16(0, Endian.little)
              .toDouble();
        } else if (inBits == 24) {
          final b0 = bytes[pos];
          final b1 = bytes[pos + 1];
          final b2 = bytes[pos + 2];
          int val = b0 | (b1 << 8) | (b2 << 16);
          if (val & 0x800000 != 0) val -= 0x1000000;
          sampleVal = val.toDouble();
        } else if (inBits == 32) {
          sampleVal = ByteData.sublistView(bytes, pos, pos + 4)
              .getInt32(0, Endian.little)
              .toDouble();
        } else {
          sampleVal = 0;
        }
        sampleSum += sampleVal;
      }

      final monoSample = (sampleSum / inChannels).toInt().clamp(-32768, 32767);

      // Write as 16-bit little-endian
      final bd = ByteData(2);
      bd.setInt16(0, monoSample, Endian.little);
      result.add(bd.buffer.asUint8List());
    }

    return result.toBytes();
  }
}
