// Task 116 (Славан 24.10): «Как пользоваться» — плитки-аккордеоны.
// Все тексты — через AppStrings (6 языков). Шапка-слоган выделена.
import 'package:flutter/material.dart';

import 'app_strings.dart';
import 'main_shell.dart';
import 'theme/app_theme.dart';
import 'widgets/dicta_ui.dart';

class _Section {
  final String titleKey;
  final IconData icon;
  final List<String> lineKeys;
  const _Section(this.titleKey, this.icon, this.lineKeys);
}

class HowToUsePage extends StatelessWidget {
  const HowToUsePage({super.key});

  static const List<_Section> _sections = [
    _Section('hs_rec_t', Icons.mic_rounded,
        ['hs_rec_1', 'hs_rec_2', 'hs_rec_3', 'hs_rec_4']),
    _Section('hs_imp_t', Icons.upload_file_rounded, ['hs_imp_1', 'hs_imp_2']),
    _Section('hs_tr_t', Icons.graphic_eq_rounded,
        ['hs_tr_1', 'hs_tr_2', 'hs_tr_3', 'hs_tr_4', 'hs_tr_5', 'hs_tr_6']),
    _Section('hs_txt_t', Icons.edit_note_rounded,
        ['hs_txt_1', 'hs_txt_2', 'hs_txt_3']),
    _Section('hs_sum_t', Icons.auto_awesome_rounded,
        ['hs_sum_1', 'hs_sum_2', 'hs_sum_3', 'hs_sum_4', 'hs_sum_5']),
    _Section('hs_pl_t', Icons.content_cut_rounded,
        ['hs_pl_1', 'hs_pl_2', 'hs_pl_3']),
    _Section('hs_exp_t', Icons.ios_share_rounded, ['hs_exp_1', 'hs_exp_2']),
    _Section('hs_tar_t', Icons.workspace_premium_rounded, [
      'hs_tar_1',
      'hs_tar_2',
      'hs_tar_3',
      'hs_tar_4',
      'hs_tar_5',
      'hs_tar_6',
      'hs_tar_7',
      'hs_tar_8',
    ]),
    _Section('hs_set_t', Icons.tune_rounded,
        ['hs_set_1', 'hs_set_2', 'hs_set_3', 'hs_set_4', 'hs_set_5']),
    _Section('hs_faq_t', Icons.help_outline_rounded,
        ['hs_faq_1', 'hs_faq_2', 'hs_faq_3', 'hs_faq_4']),
  ];

  @override
  Widget build(BuildContext context) {
    final tk = DictaTokens.of(context);
    return Scaffold(
      bottomNavigationBar: DictaBottomNav(
        index: 3,
        onTap: (i) {
          Navigator.of(context).popUntil((r) => r.isFirst);
          MainShell.requestedTab.value = i;
        },
      ),
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
            const SizedBox(height: 12),
            // Task 116 (Славан): шапка — одним шрифтом, выделена рамкой.
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: tk.surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: tk.mint.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.t('help_slogan_1', context),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700, color: tk.mint),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    AppStrings.t('help_slogan_2', context),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontSize: 13.5, color: tk.ink),
                  ),
                ],
              ),
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
                      child: Text(AppStrings.t(widget.section.titleKey, context),
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    AnimatedRotation(
                      turns: _open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(Icons.expand_more_rounded,
                          size: 22, color: tk.ink3),
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
                    for (final lineKey in widget.section.lineKeys)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1.5),
                        child: Text(AppStrings.t(lineKey, context),
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
