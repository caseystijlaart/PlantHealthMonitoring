import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/timezone.dart' as tz;
import 'app_settings.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static String? _lastNotifiedKey;

  static bool get _supported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  static Future<void> init() async {
    if (!_supported || _initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(const InitializationSettings(android: android, iOS: ios));
    _initialized = true;
  }

  static Future<void> maybeNotify(String plantName, int risk, List<String> actions) async {
    if (!_supported || !_initialized) return;
    if (!AppSettings.notificationsEnabled) return;
    if (risk == 0 || actions.isEmpty) return;

    final key = '$plantName:$risk:${actions.join(",")}';
    if (key == _lastNotifiedKey) return;
    _lastNotifiedKey = key;

    final riskWord = risk == 2 ? 'High risk' : 'Moderate risk';
    const androidDetails = AndroidNotificationDetails(
      'plant_alerts',
      'Plant Alerts',
      channelDescription: 'Alerts when your plant needs attention',
      importance: Importance.high,
      priority: Priority.high,
    );
    await _plugin.show(
      0,
      'PlantHealth: $plantName',
      '$riskWord detected — ${actions.join(", ")}',
      const NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails()),
    );
  }

  static Future<void> scheduleDailyReport({
    required List<String> plants,
    required int hour,
    required int minute,
  }) async {
    if (!_supported || !_initialized) return;
    await _plugin.cancel(2);
    if (plants.isEmpty) return;

    final lines = <String>[];
    for (final plant in plants) {
      final res = await Supabase.instance.client
          .from('plant_readings')
          .select('risk_class')
          .eq('plant_label', plant)
          .order('timestamp', ascending: false)
          .limit(1);
      if (res.isNotEmpty) {
        final risk = (res[0]['risk_class'] ?? 0) as int;
        final status = switch (risk) {
          0 => 'Healthy',
          1 => 'Moderate risk',
          2 => 'High risk',
          _ => 'Unknown',
        };
        lines.add('$plant: $status');
      }
    }
    if (lines.isEmpty) return;

    final location = tz.local;
    final now = tz.TZDateTime.now(location);
    var scheduled = tz.TZDateTime(location, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) scheduled = scheduled.add(const Duration(days: 1));

    const androidDetails = AndroidNotificationDetails(
      'daily_report',
      'Daily Plant Report',
      channelDescription: 'Daily summary of all plant statuses',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    await _plugin.zonedSchedule(
      2,
      'Daily plant report',
      lines.join(' · '),
      scheduled,
      const NotificationDetails(android: androidDetails, iOS: DarwinNotificationDetails()),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static Future<void> cancelDailyReport() async {
    if (!_supported || !_initialized) return;
    await _plugin.cancel(2);
  }
}
