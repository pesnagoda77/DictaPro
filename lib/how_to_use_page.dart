// Task 116 (Славан 24.10): «Как пользоваться» — плитки-аккордеоны.
// Шапка = 2 строки слогана. Дальше раскрывающиеся плитки по разделам
// инструкции; внутри — краткий текст для пользователя.
import 'package:flutter/material.dart';

import 'app_strings.dart';
import 'theme/app_theme.dart';
import 'widgets/dicta_ui.dart';

class _Section {
  final String title;
  final IconData icon;
  final List<String> lines;
  const _Section(this.title, this.icon, this.lines);
}

class HowToUsePage extends StatelessWidget {
  const HowToUsePage({super.key});

  static const List<_Section> _sections = [
    _Section('Запись', Icons.mic_rounded, [
      'Круглая кнопка — начать, ещё раз — остановить.',
      'Можно свернуть: запись идёт в фоне.',
      'Таймер сна остановит запись сам через выбранное время.',
      'Записи хранятся в «Документы/DictaPro/Записи».',
    ]),
    _Section('Импорт файлов', Icons.upload_file_rounded, [
      'Кнопка «Импорт»: mp3, m4a, wav, ogg, flac — с диктофона,',
      'из мессенджера или почты.',
      'Формат приведётся сам, битые wav починятся.',
    ]),
    _Section('Расшифровка', Icons.graphic_eq_rounded, [
      'Откройте запись → «Расшифровать» → язык речи.',
      'Считается в телефоне, интернет не нужен.',
      'Фоновая расшифровка пришлёт уведомление «Готово».',
      'Обрыв не страшен: «Продолжить с места обрыва».',
      'Термины (имена, специальные слова) — в карточке текста,',
      'затем «Заново».',
    ]),
    _Section('Текст и диалог', Icons.edit_note_rounded, [
      'Правка, поиск, копирование, поделиться.',
      'Диалог: фразы «Фраза 1, 2…» — исправить, разделить,',
      'слить, пометить говорящего.',
    ]),
    _Section('Итоги', Icons.auto_awesome_rounded, [
      'Локальные итоги: быстро, без сети, бесплатно.',
      'ИИ-итоги: точнее, расходуют ИИ-часы.',
      'Повторное открытие итога бесплатно (кэш).',
      'Тип текста определится сам: совещание, лекция,',
      'интервью, заметки, сказка. Решения — в карточке записи.',
    ]),
    _Section('Плеер и фрагменты', Icons.content_cut_rounded, [
      'Плеер с таймкодами и подсветкой фразы.',
      'Ножницы: отметить строки → «Вырезать и отправить» —',
      'аудиофайл только из выбранных фраз, сразу в мессенджер.',
    ]),
    _Section('Экспорт', Icons.ios_share_rounded, [
      'TXT с таймкодами, HTML, PDF («Фраза N») или просто текст.',
      'Файлы — в «Документы/DictaPro», можно сразу отправить.',
    ]),
    _Section('Тарифы и часы', Icons.workspace_premium_rounded, [
      'Бесплатно: 30 минут расшифровки в день.',
      'Дневник: 24 ч/мес + 10 ИИ-часов.',
      'Ассистент: 120 ч/мес + 20 ИИ-часов.',
      'Безлимит: без ограничений + 40 ИИ-часов.',
      'Месяц считается от дня активации, не с 1-го числа.',
      'Купленные пакеты часов не сгорают.',
      'Код активации: экран подписки → «Ввести код».',
      'Отмена подписки в Play — мгновенный возврат к бесплатным',
      '30 минутам; купленные пакеты остаются.',
    ]),
    _Section('Настройки', Icons.tune_rounded, [
      'Язык интерфейса (6 языков) и язык расшифровки.',
      'Качество записи: битрейт, каналы.',
      'Папка записей: открыть / очистить.',
      '«Работа без ограничений» — чтобы система не убивала',
      'фоновую расшифровку (важно на Xiaomi).',
      'Диагностика: скорость расшифровки по фазам.',
    ]),
    _Section('Частые вопросы', Icons.help_outline_rounded, [
      'Медленно? Длинный файл считается долго — это нормально.',
      'Ошибки в именах? «Термины» → «Заново».',
      'Часы кончились? Завтра вернутся 30 минут или купите пакет.',
      'Удалил приложение? Записи остались в «Документы/DictaPro».',
    ]),
  ];

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
              Expanded(
                child: Text(AppStrings.t('help_title', context),
                    style: Theme.of(context).textTheme.headlineMedium),
              ),
            ]),
            const SizedBox(height: 8),
            // Task 116 (Славан): шапка — две строки вместо старого пункта.
            Text(
              'Без интернета. Без регистрации. Бесплатно.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 2),
            Text(
              '20+ функций. Расшифровка 10+ языков.',
              style: TextStyle(fontSize: 12.5, color: tk.ink2),
            ),
            const SizedBox(height: 16),
            for (final s in _sections) _SectionTile(section: s),
          ],
        ),
      ),
    );
  }
}

class _SectionTile extends StatefulWidget {
  const _SectionTile({required this.section});
  final _Section section;

  @override
  State<_SectionTile> createState() => _SectionTileState();
}

class _SectionTileState extends State<_SectionTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final tk = DictaTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DictaCard(
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => _open = !_open),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Icon(widget.section.icon, size: 20, color: tk.mint),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(widget.section.title,
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child:
                          Icon(Icons.expand_more_rounded, size: 22, color: tk.ink3),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 180),
              crossFadeState:
                  _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 2, left: 2, bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final line in widget.section.lines)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1.5),
                        child: Text(line,
                            style: TextStyle(
                                fontSize: 12.5, color: tk.ink2, height: 1.45)),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
