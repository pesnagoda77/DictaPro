import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Результат онлайн-транскрипции одного фрагмента.
class SttChunkResult {
  final String text;
  SttChunkResult(this.text);
}

/// Провайдер распознавания речи (BYOK — ключ пользователя).
abstract class SttProvider {
  String get id;
  String get title;
  String get keyPrefsName;

  /// Распознать один WAV-файл (16 кГц моно 16 бит).
  Future<String> transcribe(File wavFile, String apiKey);

  static List<SttProvider> get all => [GroqProvider(), DeepgramProvider()];

  static SttProvider byId(String id) =>
      all.firstWhere((p) => p.id == id, orElse: () => GroqProvider());
}

/// Groq (whisper-large-v3-turbo): $0.04/час, регистрация по e-mail,
/// free tier без карты (2000 запросов/сутки), файл ≤25 МБ.
class GroqProvider extends SttProvider {
  @override
  String get id => 'groq';
  @override
  String get title => 'Groq (whisper-large-v3-turbo)';
  @override
  String get keyPrefsName => 'groq_api_key';

  static const String _url = 'https://api.groq.com/openai/v1/audio/transcriptions';

  @override
  Future<String> transcribe(File wavFile, String apiKey) async {
    final req = http.MultipartRequest('POST', Uri.parse(_url))
      ..headers['Authorization'] = '***'
      ..fields['model'] = 'whisper-large-v3-turbo'
      ..fields['response_format'] = 'json'
      ..fields['language'] = 'ru'
      ..fields['temperature'] = '0'
      ..files.add(await http.MultipartFile.fromPath('file', wavFile.path));

    final streamed = await req.send().timeout(const Duration(seconds: 180));
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) {
      throw SttException(
          'Groq HTTP ${resp.statusCode}: ${resp.body.substring(0, resp.body.length.clamp(0, 200))}');
    }
    final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    return (j['text'] as String? ?? '').trim();
  }
}

/// Deepgram Nova-3 (multilingual): $200 стартовых кредитов без карты,
/// диаризация включена, регистрация по e-mail.
class DeepgramProvider extends SttProvider {
  @override
  String get id => 'deepgram';
  @override
  String get title => 'Deepgram Nova-3 (multilingual)';
  @override
  String get keyPrefsName => 'deepgram_api_key';

  static const String _url =
      'https://api.deepgram.com/v1/listen?model=nova-3&language=multi&smart_format=true&punctuate=true';

  @override
  Future<String> transcribe(File wavFile, String apiKey) async {
    final bytes = await wavFile.readAsBytes();
    final resp = await http
        .post(Uri.parse(_url), headers: {
          'Authorization': '***',
          'Content-Type': 'audio/wav',
        }, body: bytes)
        .timeout(const Duration(seconds: 180));
    if (resp.statusCode != 200) {
      throw SttException(
          'Deepgram HTTP ${resp.statusCode}: ${resp.body.substring(0, resp.body.length.clamp(0, 200))}');
    }
    final j = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final alt = (((j['results'] ?? {})['channels'] as List?)?.firstOrNull?['alternatives']
        as List?)?.firstOrNull;
    return (alt?['transcript'] as String? ?? '').trim();
  }
}

class SttException implements Exception {
  final String message;
  SttException(this.message);
  @override
  String toString() => message;
}

/// Настройки онлайн-транскрипции (ключи и выбор провайдера).
class SttSettings {
  static const String enabledKey = 'stt_online_enabled';
  static const String providerKey = 'stt_online_provider';
  static const String consentKey = 'stt_online_consent';

  static Future<bool> isEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(enabledKey) ?? false;
  }

  static Future<void> setEnabled(bool v) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(enabledKey, v);
  }

  static Future<String> providerId() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(providerKey) ?? 'groq';
  }

  static Future<void> setProviderId(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(providerKey, id);
  }

  static Future<String?> apiKey(String prefsName) async {
    final p = await SharedPreferences.getInstance();
    final k = p.getString(prefsName);
    if (k == null || k.trim().isEmpty) return null;
    return k.trim();
  }

  static Future<void> setApiKey(String prefsName, String key) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(prefsName, key.trim());
  }

  static Future<bool> hasConsent() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(consentKey) ?? false;
  }

  static Future<void> setConsent() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(consentKey, true);
  }
}
