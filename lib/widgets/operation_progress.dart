import 'dart:async';

import 'package:flutter/material.dart';

/// Task 034: индикатор длительной операции с секундомером.
///
/// Проблема: саммари/транскрипция считаются 20–25+ секунд, а на экране
/// мёртвый спиннер — кажется, что приложение зависло. Теперь спиннер
/// живёт вместе с тикающим счётчиком секунд и текстом текущего этапа.
///
/// Этап меняется извне через [stage] (ValueNotifier) — например
/// «Расшифровка…» → «Считаю саммари…». Счётчик тикает сам, раз в секунду.
class OperationProgressView extends StatefulWidget {
  final ValueNotifier<String> stage;

  const OperationProgressView({super.key, required this.stage});

  @override
  State<OperationProgressView> createState() => _OperationProgressViewState();
}

class _OperationProgressViewState extends State<OperationProgressView> {
  int _elapsed = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Секундомер: тикает в UI-потоке, но операция считается в изоляте,
    // поэтому интерфейс не замерзает и стрелка идёт.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: ValueListenableBuilder<String>(
            valueListenable: widget.stage,
            builder: (_, stageText, __) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(stageText, style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 2),
                Text(
                  'прошло $_elapsed с',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Показать блокирующий диалог прогресса (для батч-потоков после записи).
/// Возвращает будущее, которое завершается закрытием диалога через
/// Navigator.pop на том же rootNavigator.
Future<void> showOperationProgressDialog(
  BuildContext context, {
  required ValueNotifier<String> stage,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      content: OperationProgressView(stage: stage),
    ),
  );
}
