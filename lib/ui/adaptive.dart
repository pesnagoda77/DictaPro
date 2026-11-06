import 'package:flutter/material.dart';

/// Адаптивные брейкпоинты ДиктаПро (планшетная версия, ветка feature/tablet-adaptive).
///
/// Использование:
///   final size = sizeOf(context);
///   if (size == ScreenSize.tablet) { /* две панели */ }
///
/// Шаг 1 плана: файл ничего не меняет в UI, только задаёт точки перелома.
/// Подключение к home_page — в следующих шагах ветки.

class Breakpoints {
  /// две панели: список + панель текста
  static const double tablet = 600;

  /// три зоны: фильтры/папки + список + панель текста
  static const double desktop = 1024;
}

enum ScreenSize { phone, tablet, desktop }

ScreenSize sizeOf(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (w >= Breakpoints.desktop) return ScreenSize.desktop;
  if (w >= Breakpoints.tablet) return ScreenSize.tablet;
  return ScreenSize.phone;
}

/// Ширина бокового списка на планшете (по прототипу «Суть»).
const double tabletListWidth = 360;

/// Максимальная ширина контента настроек/подписки на планшете.
const double wideContentMaxWidth = 720;
