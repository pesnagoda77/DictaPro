import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Тема приложения: две цветовые схемы (тёмная и светлая), крупные размеры.
/// Значения взяты из дизайн-системы (docs/design): база #12141a / #f5f6f8,
/// акцент #e0a03c (янтарь) в тёмной и #1f6feb (синий) в светлой.
class AppColors {
  // тёмная
  static const darkBg = Color(0xFF12141A);
  static const darkSurface = Color(0xFF1A1E26);
  static const darkSurface2 = Color(0xFF222834);
  static const darkLine = Color(0xFF2E3644);
  static const darkText = Color(0xFFEEF1F6);
  static const darkMuted = Color(0xFF9AA5B8);
  static const darkAccent = Color(0xFFE0A03C);
  // светлая
  static const lightBg = Color(0xFFF5F6F8);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurface2 = Color(0xFFEEF1F5);
  static const lightLine = Color(0xFFDFE4EC);
  static const lightText = Color(0xFF151A22);
  static const lightMuted = Color(0xFF5C6573);
  static const lightAccent = Color(0xFF1F6FEB);
  // смысловые
  static const record = Color(0xFFE2585C);
  static const ok = Color(0xFF5FBF8B);
  static const info = Color(0xFF6EA8D8);
}

class AppTheme {
  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        bg: AppColors.darkBg,
        surface: AppColors.darkSurface,
        surface2: AppColors.darkSurface2,
        line: AppColors.darkLine,
        text: AppColors.darkText,
        muted: AppColors.darkMuted,
        accent: AppColors.darkAccent,
        accentInk: const Color(0xFF1B1508),
      );

  static ThemeData light() => _build(
        brightness: Brightness.light,
        bg: AppColors.lightBg,
        surface: AppColors.lightSurface,
        surface2: AppColors.lightSurface2,
        line: AppColors.lightLine,
        text: AppColors.lightText,
        muted: AppColors.lightMuted,
        accent: AppColors.lightAccent,
        accentInk: const Color(0xFFFFFFFF),
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color surface2,
    required Color line,
    required Color text,
    required Color muted,
    required Color accent,
    required Color accentInk,
  }) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: accentInk,
      secondary: accent,
      onSecondary: accentInk,
      error: AppColors.record,
      onError: Colors.white,
      surface: surface,
      onSurface: text,
    );

    // Крупная база: было 11–14, стало 14–17. Читается с телефона с руки.
    const base = TextTheme(
      displaySmall: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, height: 1.15),
      headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
      titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontSize: 17, height: 1.5),
      bodyMedium: TextStyle(fontSize: 15, height: 1.45),
      bodySmall: TextStyle(fontSize: 14),
      labelLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      labelSmall: TextStyle(fontSize: 12.5),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      dividerColor: line,
      textTheme: base.apply(bodyColor: text, displayColor: text),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: base.titleLarge!.copyWith(color: text),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: line),
        ),
      ),
      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 24),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        textColor: text,
        minVerticalPadding: 12,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        titleTextStyle: base.bodyLarge!.copyWith(color: text),
        subtitleTextStyle: base.bodyMedium!.copyWith(color: muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: accentInk,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: base.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          minimumSize: const Size(0, 48),
          side: BorderSide(color: line),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          textStyle: base.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          minimumSize: const Size(0, 44),
          textStyle: base.labelLarge,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? accent : muted),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? accent.withValues(alpha: 0.35) : surface2),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? accent : muted),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        hintStyle: base.bodyMedium!.copyWith(color: muted),
        labelStyle: base.bodyMedium!.copyWith(color: muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: accent, width: 1.6),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface2,
        contentTextStyle: base.bodyMedium!.copyWith(color: text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: accent,
        unselectedItemColor: muted,
        selectedLabelStyle: base.labelSmall,
        unselectedLabelStyle: base.labelSmall,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface2,
        side: BorderSide(color: line),
        labelStyle: base.labelSmall!.copyWith(color: muted),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent, linearTrackColor: surface2),
    );
  }
}

/// Хранит выбранную тему (тёмная по умолчанию) и сохраняет выбор на устройстве.
class ThemeController {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  static const _key = 'theme_mode';
  final ValueNotifier<ThemeMode> mode = ValueNotifier<ThemeMode>(ThemeMode.dark);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_key);
    mode.value = v == 'light' ? ThemeMode.light : ThemeMode.dark;
  }

  Future<void> setTheme(ThemeMode m) async {
    mode.value = m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, m == ThemeMode.light ? 'light' : 'dark');
  }

  bool get isLight => mode.value == ThemeMode.light;
}
