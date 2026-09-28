import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import 'app_strings.dart';
import 'theme/app_theme.dart';

/// Задача 068: сплэш в новом стиле — минимализм, три строки, каждая закончена
/// по смыслу: ДиктаПро · Голос → Текст · Не покидая телефон.
class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const SplashScreen({super.key, required this.onComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fade;
  late Animation<double> _rise;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
    );
    _rise = Tween<double>(begin: 14, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
      ),
    );

    // Полноэкранный сплэш (поведение сохраняем с прежней версии).
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);

    _controller.forward();

    Timer(const Duration(milliseconds: 2200), () {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
      widget.onComplete();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tk = DictaTokens.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: DictaBackground(
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => Opacity(
              opacity: _fade.value,
              child: Transform.translate(
                offset: Offset(0, _rise.value),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'ДиктаПро',
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            letterSpacing: -0.5,
                          ),
                    ),
                    const SizedBox(height: 13),
                    Text(
                      'Голос → Текст',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: tk.mint,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      AppStrings.splashSlogan(context),
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: tk.ink2,
                      ),
                    ),
                    const SizedBox(height: 64),
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor: AlwaysStoppedAnimation<Color>(tk.mint),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'модель внутри · интернет не нужен',
                      style: TextStyle(fontSize: 11, color: tk.ink3),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
