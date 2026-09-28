import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Дизайн-система ДиктаПро v2 (задача 068).
/// Источник: макет `V3 ДиктаПро-бесконечный холст.html` + docs/design/DESIGN_SYSTEM.md.
///
/// Тон: «тихий инструмент-ноутбук» — глубокий сине-графитовый фон, мятный рабочий
/// акцент, тёплый красный ТОЛЬКО для главного действия. Цифры — моно.
class AppColors {
  // ── тёмная (основная) ────────────────────────────────────────────────
  static const bg0 = Color(0xFF111A24); // «дно» экрана (низ градиента)
  static const bg1 = Color(0xFF182532); // основной фон (верх градиента)
  static const bg2 = Color(0xFF1F2E3D); // поля ввода, непрозрачные подложки
  static const surface = Color(0xFF25313D); // карточки (белый 5.5% на bg1)
  static const surface2 = Color(0xFF1C2836); // вторичная подложка

  static const line = Color(0xFF2D3944); // границы, разделители (белый 9%)
  static const line2 = Color(0xFF3D4853); // границы активных/важных блоков (16%)

  static const ink = Color(0xFFEAF2F5); // основной текст
  static const ink2 = Color(0xFFA2ACB2); // вторичный текст (66%)
  static const ink3 = Color(0xFF7A8792); // служебное: мета, статус-бар (42%)

  static const mint = Color(0xFF8FE3D2); // акцент: активные состояния, статусы
  static const mint2 = Color(0xFF4FB3A5); // тёмная мята (градиенты, прогресс)
  static const red = Color(0xFFFF6B6B); // ТОЛЬКО главное действие (запись, покупка)
  static const redInk = Color(0xFF2A0E0E); // текст на красном
  static const gold = Color(0xFFFFD166); // бейдж «лучшая цена за год»
  static const mintInk = Color(0xFF0E2A26); // текст на мяте

  // ── светлая (из тех же семантических токенов) ────────────────────────
  static const lBg0 = Color(0xFFE6EDF2);
  static const lBg1 = Color(0xFFF4F7F9);
  static const lSurface = Color(0xFFFFFFFF);
  static const lSurface2 = Color(0xFFEDF2F6);
  static const lLine = Color(0xFFD8E1E8);
  static const lLine2 = Color(0xFFC3CFD9);
  static const lInk = Color(0xFF16222E);
  static const lInk2 = Color(0xFF55636F);
  static const lInk3 = Color(0xFF7C8A96);
  static const lMint = Color(0xFF2E7D6E); // затемнённая мята: контраст на светлом
  static const lMint2 = Color(0xFF1F5F53);
  static const lRed = Color(0xFFE05A5A);

  // ── алиасы: старые имена, чтобы существующий код не ломался ──────────
  static const darkBg = bg0;
  static const darkSurface = surface;
  static const darkSurface2 = surface2;
  static const darkLine = line;
  static const darkText = ink;
  static const darkMuted = ink2;
  static const darkAccent = mint;
  static const lightBg = lBg1;
  static const lightSurface = lSurface;
  static const lightSurface2 = lSurface2;
  static const lightLine = lLine;
  static const lightText = lInk;
  static const lightMuted = lInk2;
  static const lightAccent = lMint;
  static const record = red;
  static const ok = mint;
  static const info = mint2;
}

/// Фон экрана: градиент bg1→bg0 + два мягких радиальных свечения (мята сверху,
/// тёплый красный снизу-справа). Плоских однотонных фонов в приложении нет.
class DictaBackground extends StatelessWidget {
  const DictaBackground({super.key, required this.child, this.scrollable = false});

  final Widget child;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    final content = scrollable ? child : SafeArea(child: child);
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: light
                    ? const [AppColors.lBg1, AppColors.lBg0]
                    : const [AppColors.bg1, AppColors.bg0],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -1.15),
                radius: 1.0,
                colors: light
                    ? const [Color(0x1F4FB3A5), Color(0x004FB3A5)]
                    : const [Color(0x218FE3D2), Color(0x008FE3D2)],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(1.15, 1.2),
                radius: 0.95,
                colors: light
                    ? const [Color(0x12E05A5A), Color(0x00E05A5A)]
                    : const [Color(0x1AFF6B6B), Color(0x00FF6B6B)],
              ),
            ),
          ),
        ),
        Positioned.fill(child: content),
      ],
    );
  }
}

class AppTheme {
  /// Семейства шрифтов (вшиваются в приложение, работают офлайн).
  static const fontUi = 'Onest';
  static const fontMono = 'JetBrains Mono';

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        bg: AppColors.bg0,
        surface: AppColors.surface,
        surface2: AppColors.bg2,
        line: AppColors.line,
        text: AppColors.ink,
        muted: AppColors.ink2,
        faint: AppColors.ink3,
        accent: AppColors.mint,
        accentInk: AppColors.mintInk,
        gold: AppColors.gold,
      );

  static ThemeData light() => _build(
        brightness: Brightness.light,
        bg: AppColors.lBg1,
        surface: AppColors.lSurface,
        surface2: AppColors.lSurface2,
        line: AppColors.lLine,
        text: AppColors.lInk,
        muted: AppColors.lInk2,
        faint: AppColors.lInk3,
        accent: AppColors.lMint,
        accentInk: Colors.white,
        gold: const Color(0xFF9A7B18),
      );

  static ThemeData _build({
    required Brightness brightness,
    required Color bg,
    required Color surface,
    required Color surface2,
    required Color line,
    required Color text,
    required Color muted,
    required Color faint,
    required Color accent,
    required Color accentInk,
    required Color gold,
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: accentInk,
      secondary: accent,
      onSecondary: accentInk,
      error: isDark ? AppColors.red : AppColors.lRed,
      onError: Colors.white,
      surface: surface,
      onSurface: text,
      surfaceContainerHighest: surface2,
      outline: line,
      outlineVariant: line,
    );

    // Шкала из дизайн-системы: H1 20/800 · H2 16/700 · body 13.5/400 · мета mono 11.
    // Onest подключён переменным шрифтом → вес задаём через ось wght (fontVariations),
    // иначе система рисует только Regular с синтетическим жирным.
    List<FontVariation> w(double v) => <FontVariation>[FontVariation('wght', v)];
    final t = TextTheme(
      displaySmall: TextStyle(fontFamily: fontUi, fontSize: 26, fontWeight: FontWeight.w800, height: 1.15, letterSpacing: -0.4, fontVariations: w(800)),
      headlineMedium: TextStyle(fontFamily: fontUi, fontSize: 20, fontWeight: FontWeight.w800, height: 1.22, letterSpacing: -0.2, fontVariations: w(800)),
      titleLarge: TextStyle(fontFamily: fontUi, fontSize: 16, fontWeight: FontWeight.w700, fontVariations: w(700)),
      titleMedium: TextStyle(fontFamily: fontUi, fontSize: 14.5, fontWeight: FontWeight.w700, fontVariations: w(700)),
      bodyLarge: TextStyle(fontFamily: fontUi, fontSize: 15, height: 1.45, fontVariations: w(400)),
      bodyMedium: TextStyle(fontFamily: fontUi, fontSize: 14, height: 1.45, fontVariations: w(400)),
      bodySmall: TextStyle(fontFamily: fontUi, fontSize: 12.5, height: 1.4, fontVariations: w(400)),
      labelLarge: TextStyle(fontFamily: fontUi, fontSize: 14.5, fontWeight: FontWeight.w700, fontVariations: w(700)),
      labelMedium: TextStyle(fontFamily: fontUi, fontSize: 12.5, fontWeight: FontWeight.w600, fontVariations: w(600)),
      labelSmall: TextStyle(fontFamily: fontUi, fontSize: 11, fontWeight: FontWeight.w500, fontVariations: w(500)),
    ).apply(bodyColor: text, displayColor: text);

    /// Моно-стиль для цифр, таймеров, длительностей и меты.
    TextStyle mono([double size = 12, FontWeight weight = FontWeight.w600, Color? color]) =>
        TextStyle(fontFamily: fontMono, fontSize: size, fontWeight: weight, color: color ?? muted, letterSpacing: 0.2);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      fontFamily: fontUi,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      dividerColor: line,
      textTheme: t,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: t.titleLarge!.copyWith(color: text),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: line)),
      ),
      dividerTheme: DividerThemeData(color: line, thickness: 1, space: 18),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        textColor: text,
        minVerticalPadding: 10,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        titleTextStyle: t.titleMedium!.copyWith(color: text),
        subtitleTextStyle: t.bodySmall!.copyWith(color: faint),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: accentInk,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: t.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      /// Главное действие (запись, покупка) — единственное красное в интерфейсе.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? AppColors.red : AppColors.lRed,
          foregroundColor: AppColors.redInk,
          elevation: 0,
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          textStyle: t.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          minimumSize: const Size(0, 48),
          side: BorderSide(color: line),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          textStyle: t.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          minimumSize: const Size(0, 44),
          textStyle: t.labelMedium,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? accentInk : muted),
        trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? accent : surface2),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? accent : muted),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface2,
        hintStyle: t.bodyMedium!.copyWith(color: faint),
        labelStyle: t.bodyMedium!.copyWith(color: muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: accent, width: 1.6)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surface2,
        contentTextStyle: t.bodyMedium!.copyWith(color: text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: isDark ? AppColors.bg1.withValues(alpha: 0.92) : surface,
        selectedItemColor: accent,
        unselectedItemColor: faint,
        selectedLabelStyle: t.labelSmall,
        unselectedLabelStyle: t.labelSmall,
        elevation: 0,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface2,
        side: BorderSide(color: line),
        labelStyle: t.labelMedium!.copyWith(color: muted),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: isDark ? AppColors.bg2 : AppColors.lSurface2,
        linearMinHeight: 5,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? const Color(0xFF1C2A38) : surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: t.titleLarge!.copyWith(color: text),
        contentTextStyle: t.bodyMedium!.copyWith(color: muted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? const Color(0xFF1C2A38) : surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[
        DictaTokens(
          accent: accent,
          mint: isDark ? AppColors.mint : AppColors.lMint,
          red: isDark ? AppColors.red : AppColors.lRed,
          gold: gold,
          ink: text,
          ink2: muted,
          ink3: faint,
          line: line,
          line2: isDark ? AppColors.line2 : AppColors.lLine2,
          surface: surface,
          surface2: surface2,
          mono: mono,
        ),
      ],
    );
  }
}

/// Дополнительные токены, которых нет в MaterialTheme (мята/красный/золото,
/// моно-стиль для цифр). Доступ: `DictaTokens.of(context)`.
class DictaTokens extends ThemeExtension<DictaTokens> {
  const DictaTokens({
    required this.accent,
    required this.mint,
    required this.red,
    required this.gold,
    required this.ink,
    required this.ink2,
    required this.ink3,
    required this.line,
    required this.line2,
    required this.surface,
    required this.surface2,
    required this.mono,
  });

  final Color accent;
  final Color mint;
  final Color red;
  final Color gold;
  final Color ink;
  final Color ink2;
  final Color ink3;
  final Color line;
  final Color line2;
  final Color surface;
  final Color surface2;
  final TextStyle Function([double size, FontWeight weight, Color? color]) mono;

  static DictaTokens of(BuildContext context) =>
      Theme.of(context).extension<DictaTokens>()!;

  @override
  DictaTokens copyWith({
    Color? accent, Color? mint, Color? red, Color? gold, Color? ink, Color? ink2,
    Color? ink3, Color? line, Color? line2, Color? surface, Color? surface2,
    TextStyle Function([double, FontWeight, Color?])? mono,
  }) =>
      DictaTokens(
        accent: accent ?? this.accent,
        mint: mint ?? this.mint,
        red: red ?? this.red,
        gold: gold ?? this.gold,
        ink: ink ?? this.ink,
        ink2: ink2 ?? this.ink2,
        ink3: ink3 ?? this.ink3,
        line: line ?? this.line,
        line2: line2 ?? this.line2,
        surface: surface ?? this.surface,
        surface2: surface2 ?? this.surface2,
        mono: mono ?? this.mono,
      );

  @override
  DictaTokens lerp(ThemeExtension<DictaTokens>? other, double t) {
    if (other is! DictaTokens) return this;
    return DictaTokens(
      accent: Color.lerp(accent, other.accent, t)!,
      mint: Color.lerp(mint, other.mint, t)!,
      red: Color.lerp(red, other.red, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      ink2: Color.lerp(ink2, other.ink2, t)!,
      ink3: Color.lerp(ink3, other.ink3, t)!,
      line: Color.lerp(line, other.line, t)!,
      line2: Color.lerp(line2, other.line2, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      mono: t < 0.5 ? mono : other.mono,
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
