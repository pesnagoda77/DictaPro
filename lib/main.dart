import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'audio_service.dart';
import 'home_page.dart';
import 'splash_screen.dart';
import 'theme/app_theme.dart';
import 'services/purchase_service.dart';
import 'services/local_notify.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Foreground-сервис: запись продолжается при выключенном экране
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'dictapro_recording',
      channelName: 'Запись DictaPro',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
    ),
  );
  await Hive.initFlutter();
  await AudioService().init();
  // Task 054: права на полную версию из локального кэша + перепроверка
  // в Store (без сети — остаёмся на кэше).
  await PurchaseService.instance.init();
  // Task 056: локальные уведомления «Расшифровка готова» (работают офлайн).
  await LocalNotify.instance.init();
  // Выбранная тема (тёмная/светлая) — из памяти устройства
  await ThemeController.instance.load();
  // Модель GigaAM готовится лениво при первой расшифровке
  // (GigaamService.ensureModelReady) — старт приложения не блокируем.
  runApp(const DictaProApp());
}

class DictaProApp extends StatelessWidget {
  const DictaProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeController.instance.mode,
      builder: (context, mode, _) => MaterialApp(
        title: 'ДиктаПро',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        home: const SplashWrapper(),
      ),
    );
  }
}

class SplashWrapper extends StatefulWidget {
  const SplashWrapper({super.key});

  @override
  State<SplashWrapper> createState() => _SplashWrapperState();
}

class _SplashWrapperState extends State<SplashWrapper> {
  bool _showSplash = true;

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return SplashScreen(
        onComplete: () {
          setState(() {
            _showSplash = false;
          });
        },
      );
    }
    return const HomePage();
  }
}
