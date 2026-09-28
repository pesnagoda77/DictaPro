import 'package:flutter/material.dart';

import 'home_page.dart';
import 'more_page.dart';
import 'theme/app_theme.dart';
import 'widgets/dicta_ui.dart';

/// Задача 068: оболочка приложения с нижней навигацией.
/// Записи · Тексты · Итоги · Ещё. Настройки и подписка переехали в «Ещё».
class MainShell extends StatefulWidget {
  const MainShell({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      HomePage(key: const ValueKey('tab-recordings'), tab: 0),
      HomePage(key: const ValueKey('tab-texts'), tab: 1),
      HomePage(key: const ValueKey('tab-summaries'), tab: 2),
      const MorePage(),
    ];
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DictaBackground(child: pages[_tab]),
      bottomNavigationBar: DictaBottomNav(
        index: _tab,
        onTap: (i) => setState(() => _tab = i),
      ),
    );
  }
}
