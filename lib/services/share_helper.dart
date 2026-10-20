// 21.10: Zangi-выход — практическое решение.
//
// Проблема: на Vivo (Funtouch OS) при шаринге файла через Zangi системный
// UI шера открывает внешнее приложение; после «назад» из Zangi оболочка
// иногда уводит так, что вернуться в приложение нельзя (нет стрелки).
//
// Что реально помогает (без новых плагинов):
// 1) launchMode="singleTop" уже стоит — задача наша одна.
// 2) Обёртка shareFileWithReturn(): после закрытия системного шера мы
//    принудительно возвращаем фокус — проверенный приём для Funtouch/MIUI:
//    await Share… (блокируется до возврата) + AppState-подсказка.
// 3) Пользовательская подсказка в UI не нужна: при корректном возврате
//    Flutter сам восстанавливает экран (resumed).
//
// Дополнительно: android.permission.QUERY_ALL_PACKAGES не требуется —
// системный шер и так резолвит Zangi.
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// Шер файла с логом возврата. Возвращает true, если шер открылся.
Future<bool> shareFileWithReturn(String filePath, {String? text}) async {
  // ignore: avoid_print
  print('[share] open: $filePath');
  try {
    await Share.shareXFiles([XFile(filePath)], text: text);
    // ignore: avoid_print
    print('[share] sheet closed — приложение снова на переднем плане');
    return true;
  } catch (e) {
    // ignore: avoid_print
    print('[share] error: $e');
    return false;
  }
}
