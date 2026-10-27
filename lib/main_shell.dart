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

  /// Task 116 (Славан): любой экран может попросить «покажи главную».
  /// Нужно после открытия аудиофайла из проводника.
  static final ValueNotifier<int?> requestedTab = ValueNotifier<int?>(null);

  /// Task 117 П.3: после перехода из «Папки записей» главная прокручивается
  /// к этой записи и подсвечивает её рамкой. Сюда передаётся id записи.
  static final ValueNotifier<String?> focusRecordingId =
      ValueNotifier<String?>(null);

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _tab = widget.initialTab;

  @override
  void initState() {
    super.initState();
    MainShell.requestedTab.addListener(_onRequestedTab);
  }

  void _onRequestedTab() {
    final v = MainShell.requestedTab.value;
    if (v == null || !mounted) return;
    MainShell.requestedTab.value = null;
    setState(() => _tab = v.clamp(0, 3));
  }

  @override
  void dispose() {
    MainShell.requestedTab.removeListener(_onRequestedTab);
    super.dispose();
  }

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
