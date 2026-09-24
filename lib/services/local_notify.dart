// Task 056: локальное уведомление о готовности расшифровки.
// Работает без интернета (локальный пуш). На Android 13+/iOS разрешение
// запрашиваем при инициализации; отказ не ломает расшифровку — просто
// не будет уведомления (интерфейс всё равно покажет баннер при возврате).
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotify {
  LocalNotify._();
  static final LocalNotify instance = LocalNotify._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channelId = 'dictapro_transcribe';
  static const _channelName = 'Расшифровка';

  Future<void> init() async {
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        const InitializationSettings(android: android, iOS: darwin),
      );
      // Android 13+: разрешение на уведомления отдельным запросом.
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.requestNotificationsPermission();
      _ready = true;
    } catch (e) {
      debugPrint('[local_notify] init ОШИБКА: $e');
    }
  }

  /// «Расшифровка готова» + текст сохранён в записи.
  Future<void> showTranscriptionDone() async {
    if (!_ready) return;
    try {
      await _plugin.show(
        1,
        'Расшифровка готова',
        'Текст сохранён в записи',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            importance: Importance.high,
            priority: Priority.high,
            playSound: false,
            enableVibration: false,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: false,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[local_notify] show ОШИБКА: $e');
    }
  }
}
