import 'package:flutter/material.dart';

import 'app_strings.dart';
import 'theme/app_theme.dart';
import 'widgets/dicta_ui.dart';
import 'settings_page.dart';
import 'subscription_page.dart';

/// Задача 068: вкладка «Ещё» — шкаф приложения.
/// Здесь живут Настройки и Подписка (в шапке главной их больше нет),
/// справка, информация о приложении и диагностика.
class MorePage extends StatelessWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final tk = DictaTokens.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DictaBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            const SizedBox(height: 6),
            Text(AppStrings.t('nav_more', context),
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text(AppStrings.t('more_subtitle', context),
                style: TextStyle(fontSize: 12.5, color: tk.ink2)),
            const SizedBox(height: 16),
            _row(context, Icons.tune_rounded,
                AppStrings.t('settings_title', context),
                AppStrings.t('more_settings_sub', context),
                () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SettingsPage()))),
            _row(context, Icons.workspace_premium_outlined,
                AppStrings.t('sub_row_title', context),
                AppStrings.t('more_subscription_sub', context),
                () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SubscriptionPage()))),
            _row(context, Icons.menu_book_outlined,
                AppStrings.t('help_title', context),
                AppStrings.t('help_row_sub', context),
                () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const HelpPage()))),
            _row(context, Icons.info_outline_rounded,
                AppStrings.t('about_title', context),
                AppStrings.t('about_row_sub', context),
                () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AboutPage()))),
            _row(context, Icons.folder_open_rounded,
                AppStrings.t('share_folder_diag', context),
                AppStrings.t('share_folder_row_sub', context),
                () => _showDiag(context)),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: tk.mint.withValues(alpha: 0.3), style: BorderStyle.solid),
              ),
              child: Text(
                AppStrings.t('more_privacy_note', context),
                style: TextStyle(fontSize: 11.5, color: tk.ink2, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String title, String sub,
      VoidCallback onTap) {
    final tk = DictaTokens.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: tk.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tk.line),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: tk.mint.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: tk.mint.withValues(alpha: 0.24)),
              ),
              child: Icon(icon, size: 17, color: tk.mint),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(sub,
                      style: TextStyle(fontSize: 11, color: tk.ink3, height: 1.35)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: tk.ink3, size: 20),
          ],
        ),
      ),
    );
  }

  void _showDiag(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(AppStrings.t('share_folder_diag', context)),
        content: Text(AppStrings.t('diag_dialog_body', context)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.t('got_it', context)),
          ),
        ],
      ),
    );
  }
}

/// Справка «Как пользоваться» — короткие шаги без воды.
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tk = DictaTokens.of(context);
    final steps = <(IconData, String, String)>[
      (Icons.mic_rounded, AppStrings.t('group_recording', context),
          AppStrings.t('help_record_sub', context)),
      (Icons.folder_open_rounded, AppStrings.t('help_import_title', context),
          AppStrings.t('help_import_sub', context)),
      (Icons.graphic_eq_rounded, AppStrings.t('help_transcribe_title', context),
          AppStrings.t('help_transcribe_sub', context)),
      (Icons.article_outlined, AppStrings.t('help_text_title', context),
          AppStrings.t('help_text_sub', context)),
      (Icons.auto_awesome_outlined, AppStrings.t('nav_summaries', context),
          AppStrings.t('help_summary_sub', context)),
      (Icons.ios_share_rounded, AppStrings.t('help_export_title', context),
          AppStrings.t('help_export_sub', context)),
    ];
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DictaBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Row(children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Text(AppStrings.t('help_title', context),
                  style: Theme.of(context).textTheme.headlineMedium),
            ]),
            const SizedBox(height: 8),
            for (final s in steps)
              DictaCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: tk.mint.withValues(alpha: 0.13),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: tk.mint.withValues(alpha: 0.24)),
                      ),
                      child: Icon(s.$1, size: 17, color: tk.mint),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.$2,
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 3),
                          Text(s.$3,
                              style: TextStyle(
                                  fontSize: 12, color: tk.ink2, height: 1.5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// «О приложении» — версия, приватность, лицензии.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tk = DictaTokens.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DictaBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            Row(children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Text(AppStrings.t('about_title', context),
                  style: Theme.of(context).textTheme.headlineMedium),
            ]),
            const SizedBox(height: 6),
            DictaBrand(subtitle: AppStrings.splashSlogan(context)),
            const SizedBox(height: 16),
            DictaCard(
              child: Text(
                '${AppStrings.t('about_p1', context)}\n\n${AppStrings.t('about_p2', context)}',
                style: TextStyle(fontSize: 12.5, color: tk.ink2, height: 1.6),
              ),
            ),
            DictaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppStrings.t('about_licenses_title', context),
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    AppStrings.t('about_licenses_body', context),
                    style: TextStyle(fontSize: 12, color: tk.ink2, height: 1.5),
                  ),
                ],
              ),
            ),
            DictaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppStrings.t('about_privacy_title', context),
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    AppStrings.t('about_privacy_body', context),
                    style: TextStyle(fontSize: 12, color: tk.ink2, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
