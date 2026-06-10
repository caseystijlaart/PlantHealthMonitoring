import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  static bool notificationsEnabled = true;
  static bool dailyReportEnabled = false;
  static int dailyReportHour = 8;
  static int dailyReportMinute = 0;
  static SharedPreferences? _prefs;

  static Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    notificationsEnabled = _prefs?.getBool('notifications_enabled') ?? true;
    dailyReportEnabled   = _prefs?.getBool('daily_report_enabled')   ?? false;
    dailyReportHour      = _prefs?.getInt('daily_report_hour')       ?? 8;
    dailyReportMinute    = _prefs?.getInt('daily_report_minute')     ?? 0;
  }

  static Future<void> setNotificationsEnabled(bool value) async {
    notificationsEnabled = value;
    await _prefs?.setBool('notifications_enabled', value);
  }

  static Future<void> setDailyReport({
    required bool enabled,
    int? hour,
    int? minute,
  }) async {
    dailyReportEnabled = enabled;
    if (hour != null) dailyReportHour = hour;
    if (minute != null) dailyReportMinute = minute;
    await _prefs?.setBool('daily_report_enabled', dailyReportEnabled);
    await _prefs?.setInt('daily_report_hour', dailyReportHour);
    await _prefs?.setInt('daily_report_minute', dailyReportMinute);
  }
}
