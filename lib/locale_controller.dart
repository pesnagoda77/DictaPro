import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Язык интерфейса. По умолчанию — системный (как у пользователя в телефоне);
/// можно закрепить вручную: Русский / English / Deutsch.
class LocaleController {
  LocaleController._();
  static final LocaleController instance = LocaleController._();

  static const _box = 'settings';
  static const _key = 'ui_lang';

  /// null = системный язык.
  final ValueNotifier<Locale?> locale = ValueNotifier<Locale?>(null);

  Future<void> load() async {
    try {
      final box = await Hive.openBox<dynamic>(_box);
      final v = box.get(_key)?.toString();
      locale.value = (v == null || v == 'system' || v.isEmpty)
          ? null
          : Locale(v);
    } catch (_) {}
  }

  Future<void> setLang(String? code) async {
    locale.value = (code == null || code == 'system' || code.isEmpty)
        ? null
        : Locale(code);
    try {
      final box = await Hive.openBox<dynamic>(_box);
      await box.put(_key, code ?? 'system');
    } catch (_) {}
  }
}
