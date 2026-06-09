import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'core/app_theme.dart';
import 'screens/splash_screen.dart';
import 'secrets.dart';
import 'services/app_settings.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  try {
    final localTz = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTz.identifier));
  } catch (_) {}
  // ignore: deprecated_member_use
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  await AppSettings.load();
  await NotificationService.init();
  runApp(const PlantHealthApp());
}

class PlantHealthApp extends StatelessWidget {
  const PlantHealthApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(defaultTargetPlatform),
      home: const SplashScreen(),
    );
  }
}
