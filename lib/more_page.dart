import 'package:flutter/material.dart';

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
            Text('Ещё', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text('Настройки, подписка, справка и служебное',
                style: TextStyle(fontSize: 12.5, color: tk.ink2)),
            const SizedBox(height: 16),
            _row(context, Icons.tune_rounded, 'Настройки',
                'оформление · запись · распознавание · фон · данные',
                () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SettingsPage()))),
            _row(context, Icons.workspace_premium_outlined, 'Подписка и ИИ-часы',
                'тарифы, пакеты часов, промокод, восстановление',
                () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SubscriptionPage()))),
            _row(context, Icons.menu_book_outlined, 'Как пользоваться',
                'короткие подсказки по записи и расшифровке',
                () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const HelpPage()))),
            _row(context, Icons.info_outline_rounded, 'О приложении',
                'что считается на устройстве, лицензии, политика',
                () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AboutPage()))),
            _row(context, Icons.folder_open_rounded, 'Папка обмена (диагностика)',
                'тексты и временные файлы для проверки', () => _showDiag(context)),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: tk.mint.withValues(alpha: 0.3), style: BorderStyle.solid),
              ),
              child: Text(
                'Всё хранится на устройстве: записи, тексты и ключи не покидают телефон.',
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
        title: const Text('Папка обмена (диагностика)'),
        content: const Text(
            'Android/data/com.dictapro.app/files\n\nЗдесь лежат тексты и временные WAV — '
            'чтобы проверить, что расшифровка сохраняется. В обычной работе папка не нужна.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Понятно'),
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
    const steps = <(IconData, String, String)>[
      (Icons.mic_rounded, 'Запись', 'Нажмите круглую кнопку. Можно свернуть приложение — запись продолжится в фоне. Таймер сна остановит её сам.'),
      (Icons.folder_open_rounded, 'Импорт готовых файлов', 'Кнопка «Импорт» — выберите mp3, m4a, wav и другие. Приложение расшифрует их на устройстве.'),
      (Icons.graphic_eq_rounded, 'Расшифровка', 'Считается прямо в телефоне, интернет не нужен. Длинную запись можно продолжить с места обрыва.'),
      (Icons.article_outlined, 'Текст и диалог', 'Текст можно править, разделять по говорящим, искать по словам и копировать.'),
      (Icons.auto_awesome_outlined, 'Итоги', 'Локально — быстро и без сети. Онлайн — точнее, расходует ИИ-часы и повторно показывается бесплатно из кэша.'),
      (Icons.ios_share_rounded, 'Экспорт и отправка', 'TXT с таймкодами, HTML, PDF — или сразу отправить в мессенджер.'),
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
              Text('Как пользоваться',
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
              Text('О приложении',
                  style: Theme.of(context).textTheme.headlineMedium),
            ]),
            const SizedBox(height: 6),
            const DictaBrand(subtitle: 'Не покидая телефон'),
            const SizedBox(height: 16),
            DictaCard(
              child: Text(
                'ДиктаПро превращает речь в текст на самом телефоне. Запись, расшифровка, поиск и итоги '
                'считаются на устройстве; модель распознавания хранится внутри приложения.\n\n'
                'Онлайн-расшифровка и онлайн-итоги выключены по умолчанию и включаются только вашим решением: '
                'тогда текст записи уходит на выбранный вами сервис по защищённому соединению.',
                style: TextStyle(fontSize: 12.5, color: tk.ink2, height: 1.6),
              ),
            ),
            DictaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Лицензии', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Шрифты Onest и JetBrains Mono — SIL Open Font License 1.1.\n'
                    'Модель распознавания GigaAM — по лицензии правообладателя (см. карточку модели).',
                    style: TextStyle(fontSize: 12, color: tk.ink2, height: 1.5),
                  ),
                ],
              ),
            ),
            DictaCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Приватность', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Рекламы нет, рекламный идентификатор не используется, аккаунт не нужен. '
                    'Удаление записей и всех данных — средствами приложения или системы.',
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
