import 'package:flutter/material.dart';

import '../app_strings.dart';
import '../theme/app_theme.dart';

/// Задача 068: библиотека элементов нового дизайна (V3).
/// Токены берём из темы/`DictaTokens`, цвета — НЕ хардкодим (кроме градиента кнопки записи).

/// Логотип + название + слоган. Используется в шапках экранов.
class DictaBrand extends StatelessWidget {
  const DictaBrand({super.key, this.title, this.subtitle});

  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final tk = DictaTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [tk.mint, AppColors.mint2],
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.mic_none_rounded, size: 19, color: AppColors.mintInk),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title ?? AppStrings.t('app_title', context),
                style: Theme.of(context).textTheme.titleMedium),
            if (subtitle != null)
              Text(subtitle!, style: TextStyle(fontSize: 10.5, color: tk.mint, fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }
}

/// Статус записи: готово (мята) · ожидание (серый) · ошибка (красный) · тариф (золото).
enum DictaTagKind { done, pending, error, gold }

class DictaStatusTag extends StatelessWidget {
  const DictaStatusTag(this.text, {super.key, this.kind = DictaTagKind.done});

  final String text;
  final DictaTagKind kind;

  @override
  Widget build(BuildContext context) {
    final tk = DictaTokens.of(context);
    late final Color bg;
    late final Color fg;
    switch (kind) {
      case DictaTagKind.done:
        bg = tk.mint;
        fg = AppColors.mintInk;
      case DictaTagKind.pending:
        bg = tk.line;
        fg = tk.ink2;
      case DictaTagKind.error:
        bg = tk.red.withValues(alpha: 0.18);
        fg = tk.red;
      case DictaTagKind.gold:
        bg = tk.gold.withValues(alpha: 0.18);
        fg = tk.gold;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(text,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

/// Карточка в стиле дизайн-системы: мягкая подложка, тонкая граница, без теней.
class DictaCard extends StatelessWidget {
  const DictaCard({super.key, required this.child, this.accented = false, this.padding});

  final Widget child;
  final bool accented; // мятная рамка (главное действие / активная запись)
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final tk = DictaTokens.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: padding ?? const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tk.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: accented ? tk.mint.withValues(alpha: 0.34) : tk.line,
          width: 1,
        ),
      ),
      child: child,
    );
  }
}

/// Круглая кнопка записи. Единственное красное пятно на экране, когда пишем.
class DictaMicButton extends StatelessWidget {
  const DictaMicButton({
    super.key,
    required this.recording,
    required this.onTap,
    this.size = 84,
  });

  final bool recording;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: recording ? AppStrings.t('stop_recording', context) : AppStrings.t('start_recording', context),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(size),
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFF7E7E), AppColors.red],
              ),
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(color: Color(0x52FF6B6B), blurRadius: 26, offset: Offset(0, 12)),
              ],
            ),
            child: Icon(
              recording ? Icons.stop_rounded : Icons.mic_rounded,
              size: size * 0.36,
              color: AppColors.redInk,
            ),
          ),
        ),
      ),
    );
  }
}

/// Плашка прогресса расшифровки: мятная рамка, строка «идёт N · готово K · %», полоса.
class DictaProgressPlate extends StatelessWidget {
  const DictaProgressPlate({
    super.key,
    required this.title,
    required this.line,
    required this.progress, // 0..1
  });

  final String title;
  final String line;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final tk = DictaTokens.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: tk.mint.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tk.mint.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 3),
          Text(line, style: tk.mono(11, FontWeight.w600, tk.ink3)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: tk.line,
              valueColor: AlwaysStoppedAnimation<Color>(tk.mint),
            ),
          ),
        ],
      ),
    );
  }
}

/// Одна ячейка сетки действий записи.
class DictaAction {
  const DictaAction(this.icon, this.title, this.hint, this.onTap, {this.enabled = true});
  final IconData icon;
  final String title;
  final String hint;
  final VoidCallback onTap;
  final bool enabled;
}

/// Сетка действий (10 ячеек: только реально существующий функционал).
class DictaActionGrid extends StatelessWidget {
  const DictaActionGrid({super.key, required this.actions});

  final List<DictaAction> actions;

  @override
  Widget build(BuildContext context) {
    final tk = DictaTokens.of(context);
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 7,
      crossAxisSpacing: 7,
      childAspectRatio: 0.88,
      children: [
        for (final a in actions)
          Opacity(
            opacity: a.enabled ? 1 : 0.45,
            child: InkWell(
              borderRadius: BorderRadius.circular(11),
              onTap: a.enabled ? a.onTap : null,
              child: Container(
                decoration: BoxDecoration(
                  color: tk.surface2,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: tk.line),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(a.icon, size: 17, color: a.enabled ? tk.mint : tk.ink3),
                    const SizedBox(height: 5),
                    Text(a.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: tk.ink)),
                    Text(a.hint,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 9, color: tk.ink3)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Нижняя навигация: Записи · Тексты · Итоги · Ещё.
class DictaBottomNav extends StatelessWidget {
  const DictaBottomNav({super.key, required this.index, required this.onTap});

  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final tk = DictaTokens.of(context);
    // Как в утверждённом макете: только надписи, без иконок.
    const items = ['Записи', 'Тексты', 'Итоги', 'Ещё'];
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tk.line)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(items[i],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: i == index ? FontWeight.w700 : FontWeight.w500,
                          color: i == index ? tk.mint : tk.ink3,
                        )),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Заголовок секции + опциональное действие справа.
class DictaSectionTitle extends StatelessWidget {
  const DictaSectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tk = DictaTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 2),
      child: Row(
        children: [
          Text(text, style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Фильтр-чип (Все / Сегодня / В очереди).
class DictaChip extends StatelessWidget {
  const DictaChip(this.text, {super.key, this.selected = false, this.onTap, this.leading});

  final String text;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? leading;

  @override
  Widget build(BuildContext context) {
    final tk = DictaTokens.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? tk.mint : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? tk.mint : tk.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (leading != null) ...[
              Icon(leading, size: 13, color: selected ? AppColors.mintInk : tk.ink2),
              const SizedBox(width: 5),
            ],
            Text(text,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.mintInk : tk.ink2,
                )),
          ],
        ),
      ),
    );
  }
}
