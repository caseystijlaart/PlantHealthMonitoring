import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'provisioning.dart';
import 'secrets.dart';

// ─── Brand palette (matches the HTML splash) ───────────────────────────────
class AppColors {
  static const bg = Color(0xFF0C1A10); // very dark green-black
  static const surface = Color(0xFF152A1C); // card surface
  static const surface2 = Color(0xFF1C3526); // slightly lighter surface
  static const border = Color(0xFF2A3D2E); // subtle border
  static const accent = Color(0xFF4ADE80); // bright green
  static const accentDim = Color(0xFF2EA05A); // mid green
  static const textHigh = Color(0xFFE4F5E9); // near-white
  static const textMid = Color(0xFFB4E6C3); // medium
  static const textLow = Color(0xFF4A6B52); // muted
  static const gridLine = Color(0x0D4ADE80); // 5% green for grid
  static const healthy = Color(0xFF4ADE80);
  static const moderate = Color(0xFFFBBF24);
  static const high = Color(0xFFF87171);
}

// ─── Theme ──────────────────────────────────────────────────────────────────
ThemeData buildAppTheme(TargetPlatform platform) {
  final isDesktop =
      platform == TargetPlatform.windows ||
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.linux;

  final base = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: AppColors.bg,
      secondary: AppColors.accentDim,
      surface: AppColors.surface,
      onSurface: AppColors.textHigh,
      outline: AppColors.border,
    ),
    platform: platform,
    useMaterial3: true,
    visualDensity: isDesktop ? VisualDensity.compact : VisualDensity.standard,
  );

  final outfitText = GoogleFonts.outfitTextTheme(
    base.textTheme,
  ).apply(bodyColor: AppColors.textMid, displayColor: AppColors.textHigh);

  return base.copyWith(
    textTheme: outfitText,

    // AppBar
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: GoogleFonts.outfit(
        color: AppColors.textHigh,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      iconTheme: const IconThemeData(color: AppColors.textMid),
    ),

    // Cards
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.border),
      ),
    ),

    // Dropdowns
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: GoogleFonts.outfit(color: AppColors.textMid, fontSize: 14),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        labelStyle: GoogleFonts.outfit(color: AppColors.textLow, fontSize: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      labelStyle: GoogleFonts.outfit(color: AppColors.textLow, fontSize: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
    ),

    // Chips
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surface,
      selectedColor: const Color(0xFF1C3D28),
      side: const BorderSide(color: AppColors.border),
      labelStyle: GoogleFonts.outfit(color: AppColors.textMid, fontSize: 13),
      secondaryLabelStyle: GoogleFonts.outfit(
        color: AppColors.accent,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      checkmarkColor: AppColors.accent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),

    // Filled buttons
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.bg,
        textStyle: GoogleFonts.outfit(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),

    // Outlined buttons
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textMid,
        side: const BorderSide(color: AppColors.border),
        textStyle: GoogleFonts.outfit(
          fontWeight: FontWeight.w400,
          fontSize: 14,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),

    dividerTheme: const DividerThemeData(
      color: Color(0xFF2A3D2E),
      thickness: 1,
    ),
  );
}

// ─── Entry point ─────────────────────────────────────────────────────────────
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  try {
    final localTz = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTz));
  } catch (_) {
    // Fall back to UTC if timezone detection fails.
  }
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  await AppSettings.load();
  await NotificationService.init();
  runApp(const MyApp());
}

final supabase = Supabase.instance.client;

// ─── App settings (persisted) ────────────────────────────────────────────────
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

  static Future<void> setDailyReport({required bool enabled, int? hour, int? minute}) async {
    dailyReportEnabled = enabled;
    if (hour != null)   dailyReportHour   = hour;
    if (minute != null) dailyReportMinute = minute;
    await _prefs?.setBool('daily_report_enabled', dailyReportEnabled);
    await _prefs?.setInt('daily_report_hour',     dailyReportHour);
    await _prefs?.setInt('daily_report_minute',   dailyReportMinute);
  }
}

// ─── Local notification service ──────────────────────────────────────────────
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static String? _lastNotifiedKey;

  /// Notifications are only supported on Android and iOS.
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
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
    _initialized = true;
  }

  static Future<void> maybeNotify(
    String plantName,
    int risk,
    List<String> actions,
  ) async {
    if (!_supported || !_initialized) return;
    if (!AppSettings.notificationsEnabled) return;
    if (risk == 0 || actions.isEmpty) return;

    final key = '$plantName:$risk:${actions.join(",")}';
    if (key == _lastNotifiedKey) return;
    _lastNotifiedKey = key;

    final riskWord = risk == 2 ? 'High risk' : 'Moderate risk';
    final body = '$riskWord detected — ${actions.join(", ")}';

    const androidDetails = AndroidNotificationDetails(
      'plant_alerts',
      'Plant Alerts',
      channelDescription: 'Alerts when your plant needs attention',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    await _plugin.show(
      0,
      'PlantHealth: $plantName',
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  /// Schedules (or reschedules) the daily plant status report notification.
  /// Fetches the latest risk for every plant in [plants] and fires at [hour]:[minute] each day.
  static Future<void> scheduleDailyReport({
    required List<String> plants,
    required int hour,
    required int minute,
  }) async {
    if (!_supported || !_initialized) return;
    // Cancel any existing daily report first.
    await _plugin.cancel(2);
    if (plants.isEmpty) return;

    // Build the body by querying each plant's latest risk.
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
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    const androidDetails = AndroidNotificationDetails(
      'daily_report',
      'Daily Plant Report',
      channelDescription: 'Daily summary of all plant statuses',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const iosDetails = DarwinNotificationDetails();

    await _plugin.zonedSchedule(
      2,
      'Daily plant report',
      lines.join(' · '),
      scheduled,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  static Future<void> cancelDailyReport() async {
    if (!_supported || !_initialized) return;
    await _plugin.cancel(2);
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(defaultTargetPlatform),
      home: const SplashScreen(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  SPLASH SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Animation controllers
  late final AnimationController _gridCtrl;
  late final AnimationController _ringCtrl;
  late final AnimationController _iconCtrl;
  late final AnimationController _fadeCtrl;
  late final AnimationController _barCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _dotCtrl;

  // Animations
  late final Animation<double> _gridOpacity;
  late final Animation<double> _ring1Scale;
  late final Animation<double> _ring1Opacity;
  late final Animation<double> _ring2Scale;
  late final Animation<double> _ring2Opacity;
  late final Animation<double> _iconScale;
  late final Animation<double> _iconOpacity;
  late final Animation<double> _iconY;
  late final Animation<double> _titleOpacity;
  late final Animation<double> _titleY;
  late final Animation<double> _taglineOpacity;
  late final Animation<double> _pillsOpacity;
  late final Animation<double> _pillsY;
  late final Animation<double> _barProgress;
  late final Animation<double> _glowPulse;
  late final Animation<double> _dotScale;

  @override
  void initState() {
    super.initState();

    // Grid fade in (0–2500ms)
    _gridCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    _gridOpacity = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _gridCtrl, curve: Curves.easeIn));

    // Rings burst in then pulse
    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _ring1Scale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _ringCtrl,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );
    _ring1Opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _ringCtrl,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );
    _ring2Scale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(
        parent: _ringCtrl,
        curve: const Interval(0.2, 0.8, curve: Curves.easeOut),
      ),
    );
    _ring2Opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _ringCtrl,
        curve: const Interval(0.2, 0.8, curve: Curves.easeOut),
      ),
    );

    // Icon pop in (delay 500ms)
    _iconCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _iconScale = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _iconCtrl, curve: Curves.elasticOut));
    _iconOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _iconCtrl, curve: const Interval(0, 0.4)),
    );
    _iconY = Tween<double>(
      begin: 16,
      end: 0,
    ).animate(CurvedAnimation(parent: _iconCtrl, curve: Curves.easeOut));

    // Title + tagline + pills (staggered via single controller)
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _titleOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _fadeCtrl,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );
    _titleY = Tween<double>(begin: 12, end: 0).animate(
      CurvedAnimation(
        parent: _fadeCtrl,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );
    _taglineOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _fadeCtrl,
        curve: const Interval(0.25, 0.85, curve: Curves.easeOut),
      ),
    );
    _pillsOpacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _fadeCtrl,
        curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
      ),
    );
    _pillsY = Tween<double>(begin: 12, end: 0).animate(
      CurvedAnimation(
        parent: _fadeCtrl,
        curve: const Interval(0.5, 1.0, curve: Curves.easeOut),
      ),
    );

    // Progress bar
    _barCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    _barProgress = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _barCtrl, curve: Curves.easeInOut));

    // Radial glow pulse (continuous)
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);
    _glowPulse = Tween<double>(
      begin: 0.9,
      end: 1.1,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    // Status dot ping
    _dotCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    _dotScale = Tween<double>(
      begin: 1.0,
      end: 2.2,
    ).animate(CurvedAnimation(parent: _dotCtrl, curve: Curves.easeOut));

    // Kick off the sequence
    _runSequence();
  }

  Future<void> _runSequence() async {
    _gridCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 200));
    _ringCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 300));
    _iconCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 400));
    _fadeCtrl.forward();
    await Future.delayed(const Duration(milliseconds: 300));
    _barCtrl.forward();

    // Navigate after bar completes
    _barCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _navigateToDashboard();
      }
    });
  }

  void _navigateToDashboard() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const Dashboard(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  void dispose() {
    _gridCtrl.dispose();
    _ringCtrl.dispose();
    _iconCtrl.dispose();
    _fadeCtrl.dispose();
    _barCtrl.dispose();
    _pulseCtrl.dispose();
    _dotCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // ── Grid background ──────────────────────────────────────────
          AnimatedBuilder(
            animation: _gridOpacity,
            builder: (_, __) => Opacity(
              opacity: _gridOpacity.value,
              child: CustomPaint(size: size, painter: _GridPainter()),
            ),
          ),

          // ── Radial glow ──────────────────────────────────────────────
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _glowPulse,
              builder: (_, __) => Center(
                child: Transform.scale(
                  scale: _glowPulse.value,
                  child: Container(
                    width: size.width * 0.7,
                    height: size.width * 0.7,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [Color(0x242EA05A), Colors.transparent],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Concentric rings ─────────────────────────────────────────
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _ringCtrl,
              builder: (_, __) => Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // outer ring
                    Opacity(
                      opacity: _ring2Opacity.value,
                      child: Transform.scale(
                        scale: _ring2Scale.value,
                        child: Container(
                          width: size.width * 0.72,
                          height: size.width * 0.72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0x124ADE80),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // inner ring
                    Opacity(
                      opacity: _ring1Opacity.value,
                      child: Transform.scale(
                        scale: _ring1Scale.value,
                        child: Container(
                          width: size.width * 0.52,
                          height: size.width * 0.52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0x264ADE80),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Status dot (top right) ────────────────────────────────────
          Positioned(
            top: 56,
            right: 28,
            child: AnimatedBuilder(
              animation: _dotCtrl,
              builder: (_, __) => Stack(
                alignment: Alignment.center,
                children: [
                  Opacity(
                    opacity: 1 - _dotCtrl.value,
                    child: Transform.scale(
                      scale: _dotScale.value,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0x554ADE80),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Main content ─────────────────────────────────────────────
          Positioned.fill(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon
                AnimatedBuilder(
                  animation: _iconCtrl,
                  builder: (_, __) => Opacity(
                    opacity: _iconOpacity.value,
                    child: Transform.translate(
                      offset: Offset(0, _iconY.value),
                      child: Transform.scale(
                        scale: _iconScale.value,
                        child: const _PlantIconBox(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // Title
                AnimatedBuilder(
                  animation: _fadeCtrl,
                  builder: (_, __) => Opacity(
                    opacity: _titleOpacity.value,
                    child: Transform.translate(
                      offset: Offset(0, _titleY.value),
                      child: Column(
                        children: [
                          RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Plant',
                                  style: GoogleFonts.outfit(
                                    fontSize: 38,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textHigh,
                                    letterSpacing: -1.0,
                                  ),
                                ),
                                TextSpan(
                                  text: 'Health',
                                  style: GoogleFonts.outfit(
                                    fontSize: 38,
                                    fontWeight: FontWeight.w300,
                                    color: AppColors.accent,
                                    letterSpacing: -1.0,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Monitor',
                            style: GoogleFonts.outfit(
                              fontSize: 20,
                              fontWeight: FontWeight.w300,
                              color: const Color(0x99E4F5E9),
                              letterSpacing: -0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Tagline
                AnimatedBuilder(
                  animation: _fadeCtrl,
                  builder: (_, __) => Opacity(
                    opacity: _taglineOpacity.value,
                    child: Text(
                      'SMART PLANT COMPANION',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                        color: const Color(0x73B4E6C3),
                        letterSpacing: 3.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Feature pills
                AnimatedBuilder(
                  animation: _fadeCtrl,
                  builder: (_, __) => Opacity(
                    opacity: _pillsOpacity.value,
                    child: Transform.translate(
                      offset: Offset(0, _pillsY.value),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: const [
                          _FeaturePill('Live data'),
                          _FeaturePill('Preferences'),
                          _FeaturePill('Suggestions'),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 44),

                // Progress bar
                AnimatedBuilder(
                  animation: _barCtrl,
                  builder: (_, __) => Opacity(
                    opacity: _barProgress.value > 0 ? 1 : 0,
                    child: SizedBox(
                      width: 160,
                      child: Column(
                        children: [
                          Container(
                            height: 2,
                            decoration: BoxDecoration(
                              color: const Color(0x12FFFFFF),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: _barProgress.value,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.accent,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Initializing dashboard...',
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              color: const Color(0x4DB4E6C3),
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Version tag ──────────────────────────────────────────────
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: Text(
              'v1.1.0',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 11,
                color: const Color(0x2EB4E6C3),
                letterSpacing: 0.5,
              ),
            ),
          ),

          // ── Home bar (iOS look) ───────────────────────────────────────
          Positioned(
            bottom: 18,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 100,
                height: 3,
                decoration: BoxDecoration(
                  color: const Color(0x26FFFFFF),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Grid painter ────────────────────────────────────────────────────────────
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.gridLine
      ..strokeWidth = 1;

    const step = 28.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Plant icon box ──────────────────────────────────────────────────────────
class _PlantIconBox extends StatelessWidget {
  const _PlantIconBox();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x4D4ADE80)),
      ),
      child: Center(child: _PlantSvgIcon()),
    );
  }
}

class _PlantSvgIcon extends StatelessWidget {
  const _PlantSvgIcon();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(44, 44), painter: _PlantIconPainter());
  }
}

class _PlantIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final accent = AppColors.accent;
    final accentFill = const Color(0x384ADE80);
    final accentFill2 = const Color(0x284ADE80);
    final accentFill3 = const Color(0x474ADE80);

    final strokePaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    final fillPaint = Paint()..style = PaintingStyle.fill;

    final cx = size.width / 2;

    // Stem
    canvas.drawLine(
      Offset(cx, size.height * 0.97),
      Offset(cx, size.height * 0.38),
      strokePaint,
    );

    // Left leaf (mid)
    final leftLeafPath = Path()
      ..moveTo(cx, size.height * 0.62)
      ..cubicTo(
        cx - 8,
        size.height * 0.58,
        cx - 12,
        size.height * 0.47,
        cx - 11,
        size.height * 0.38,
      )
      ..cubicTo(
        cx - 4,
        size.height * 0.42,
        cx + 2,
        size.height * 0.52,
        cx,
        size.height * 0.62,
      )
      ..close();
    fillPaint.color = accentFill;
    canvas.drawPath(leftLeafPath, fillPaint);
    canvas.drawPath(leftLeafPath, strokePaint..strokeWidth = 1.4);

    // Right leaf (upper)
    final rightLeafPath = Path()
      ..moveTo(cx, size.height * 0.48)
      ..cubicTo(
        cx + 8,
        size.height * 0.43,
        cx + 12,
        size.height * 0.32,
        cx + 10,
        size.height * 0.23,
      )
      ..cubicTo(
        cx + 3,
        size.height * 0.28,
        cx - 3,
        size.height * 0.38,
        cx,
        size.height * 0.48,
      )
      ..close();
    fillPaint.color = accentFill2;
    canvas.drawPath(rightLeafPath, fillPaint);
    canvas.drawPath(rightLeafPath, strokePaint);

    // Top leaf
    final topLeafPath = Path()
      ..moveTo(cx, size.height * 0.35)
      ..cubicTo(
        cx - 4,
        size.height * 0.25,
        cx - 2,
        size.height * 0.1,
        cx + 2,
        size.height * 0.05,
      )
      ..cubicTo(
        cx + 5,
        size.height * 0.12,
        cx + 4,
        size.height * 0.25,
        cx,
        size.height * 0.35,
      )
      ..close();
    fillPaint.color = accentFill3;
    canvas.drawPath(topLeafPath, fillPaint);
    canvas.drawPath(topLeafPath, strokePaint);

    // Soil line
    final soilPaint = Paint()
      ..color = const Color(0xFF1E4D28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(cx - 10, size.height * 0.97),
      Offset(cx + 10, size.height * 0.97),
      soilPaint,
    );

    // Root dot
    final dotPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, size.height * 0.97), 1.8, dotPaint);

    // Small sensor circles
    final sensorBorder = Paint()
      ..color = const Color(0x724ADE80)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    final sensorFill = Paint()
      ..color = accent
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(cx + 9, size.height * 0.49), 3.2, sensorBorder);
    canvas.drawCircle(Offset(cx + 9, size.height * 0.49), 1.3, sensorFill);

    canvas.drawCircle(Offset(cx - 7, size.height * 0.65), 2.6, sensorBorder);
    canvas.drawCircle(Offset(cx - 7, size.height * 0.65), 1.0, sensorFill);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Feature pill ────────────────────────────────────────────────────────────
class _FeaturePill extends StatelessWidget {
  const _FeaturePill(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x144ADE80),
        border: Border.all(color: const Color(0x334ADE80)),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xB34ADE80),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: const Color(0xB3B4E6C3),
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  DASHBOARD
// ═══════════════════════════════════════════════════════════════════════════════

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  List<String> plants = [];
  String? selectedPlant;

  int _riskClass = 0;
  String _riskLabel = "UNKNOWN";
  String _recommendationText = "No data";
  Map<String, double> _predictions = {};

  double? _soilPct;
  double? _tempC;
  double? _humidityPct;
  double? _lightPct;

  // Plant preferences (for band indicators in sensor tiles)
  String _soilPref     = 'mid';
  String _tempPref     = 'mid';
  String _humidityPref = 'mid';
  String _lightPref    = 'mid';

  // device_id map: plant_label → device_id (null if not linked yet)
  Map<String, String?> _deviceIds = {};
  bool _measuring = false;
  Timer? _measureTimeout;

  Color _statusColor = AppColors.surface;
  bool _loading = false;
  RealtimeChannel? _realtimeChannel;

  // ── Easter egg state ──
  int _iconTapCount = 0;
  Timer? _iconTapTimer;
  int _refreshCount = 0;
  int _readingsTapCount = 0;
  Timer? _readingsTapTimer;

  static const _plantWisdom = [
    "🌱 A plant once outsmarted a botanist. The botanist is still recovering.",
    "🍃 Talking to your plants isn't weird. It's advanced horticulture.",
    "🌿 Did you know plants sleep too? Unlike you at 2am checking this app.",
    "☀️ Your plant doesn't need Wi-Fi to grow. You could learn from that.",
    "🌵 Cacti store water for years. You can't even finish a glass before bed.",
    "🌺 Plants convert CO₂ to oxygen. You're welcome for the CO₂, little guy.",
    "🍀 Some plants live for thousands of years. Your streak is 3 days. Keep going.",
    "🌙 Plants use moonlight too. So don't feel bad about staying up late.",
  ];

  static const _statusMessages = {
    0: [
      "Your plant is basically meditating right now. 🧘",
      "Peak plant performance. Truly inspiring.",
      "It's thriving. Unlike my work-life balance.",
    ],
    1: [
      "Your plant is sending mixed signals. Very millennial of it.",
      "Moderate stress? Relatable. 😅",
      "It'll be fine. Probably. Maybe water it.",
    ],
    2: [
      "Your plant is dramatically wilting. It went to theater school.",
      "HELP. ME. — your plant, probably.",
      "It's not not dying. Please act fast. 🆘",
    ],
  };

  void _onIconTap() {
    _iconTapTimer?.cancel();
    _iconTapCount++;
    if (_iconTapCount >= 3) {
      _iconTapCount = 0;
      final msg = (_plantWisdom..shuffle()).first;
      _showEasterEgg(msg);
    } else {
      _iconTapTimer = Timer(const Duration(milliseconds: 600), () => _iconTapCount = 0);
    }
  }

  void _onStatusDotLongPress() {
    final msgs = _statusMessages[_riskClass] ?? ["Your plant is a mystery. 🌿"];
    final msg = (msgs.toList()..shuffle()).first;
    _showEasterEgg(msg);
  }

  void _onReadingsTap() {
    _readingsTapTimer?.cancel();
    _readingsTapCount++;
    if (_readingsTapCount >= 5) {
      _readingsTapCount = 0;
      _showEasterEgg("👀 The plants know you're watching. They're watching back.");
    } else {
      _readingsTapTimer = Timer(const Duration(milliseconds: 800), () => _readingsTapCount = 0);
    }
  }

  Future<void> _refreshWithEasterEgg() async {
    _refreshCount++;
    if (_refreshCount >= 5) {
      _refreshCount = 0;
      _showEasterEgg("🌱 Okay okay! Plants grow at their own pace. Calm down.");
    }
    await loadLatestStatus();
  }

  void _showEasterEgg(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.outfit(color: AppColors.textHigh, fontSize: 13)),
        backgroundColor: AppColors.surface2,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    await Future.wait([loadPlants(), loadLatestStatus(), _loadPreferences()]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> loadPlants() async {
    final res = await supabase.from('plant_settings').select('plant_label, device_id');
    final list = (res as List).map((e) => e['plant_label'] as String).toList();
    final ids  = Map<String, String?>.fromEntries(
      (res as List).map((e) => MapEntry(e['plant_label'] as String, e['device_id'] as String?)),
    );
    if (!mounted) return;
    setState(() {
      plants     = list;
      _deviceIds = ids;
      if (!plants.contains(selectedPlant)) selectedPlant = null;
    });
  }

  static String _normPref(dynamic v) => switch (v) {
    'pLow'  => 'low',
    'pHigh' => 'high',
    _       => 'mid',
  };

  Future<void> _loadPreferences() async {
    if (selectedPlant == null) return;
    final res = await supabase
        .from('plant_settings')
        .select('soil_preference, temperature_preference, humidity_preference, light_preference')
        .eq('plant_label', selectedPlant!)
        .limit(1);
    if (res.isEmpty || !mounted) return;
    final row = res[0];
    setState(() {
      _soilPref     = _normPref(row['soil_preference']);
      _tempPref     = _normPref(row['temperature_preference']);
      _humidityPref = _normPref(row['humidity_preference']);
      _lightPref    = _normPref(row['light_preference']);
    });
  }

  Future<void> loadLatestStatus() async {
    if (selectedPlant == null) return;

    final res = await supabase
        .from('plant_readings')
        .select()
        .eq('plant_label', selectedPlant!)
        .order('timestamp', ascending: false)
        .limit(1);

    if (res.isEmpty) return;

    final latest = res[0];
    final int risk = latest['risk_class'] ?? 0;
    final actions = <String>[];

    final Map<String, double> parsedPredictions = {};
    final summary = latest['recommendation_summary'] as String?;
    if (summary != null && summary.isNotEmpty) {
      final regex = RegExp(r'pred(\w+?)Min[=:\s]+([\d.]+)');
      for (final m in regex.allMatches(summary)) {
        parsedPredictions[m.group(1)!] = double.parse(m.group(2)!);
      }
    }

    if (latest['action_reduce_temp'] == true || latest['action_reduce_temp'] == "true" || latest['action_reduce_temp'] == 1) {
      actions.add("Reduce temperature");
    }
    if (latest['action_water'] == true || latest['action_water'] == "true" || latest['action_water'] == 1) {
      actions.add("Water the plant");
    }
    if (latest['action_increase_light'] == true || latest['action_increase_light'] == "true" || latest['action_increase_light'] == 1) {
      actions.add("Increase light exposure");
    }

    if (!mounted) return;

    setState(() {
      _riskClass = risk;
      _predictions = parsedPredictions;
      _soilPct = (latest['soil_moisture_pct'] as num?)?.toDouble();
      _tempC = (latest['temperature_c'] as num?)?.toDouble();
      _humidityPct = (latest['humidity_pct'] as num?)?.toDouble();
      _lightPct = (latest['light_level_pct'] as num?)?.toDouble();

      switch (risk) {
        case 0:
          _riskLabel = "HEALTHY";
          _statusColor = AppColors.healthy;
          _recommendationText = "No actions required";
          break;
        case 1:
          _riskLabel = "MODERATE RISK";
          _statusColor = AppColors.moderate;
          _recommendationText = actions.isEmpty ? "No actions required" : actions.join("\n");
          break;
        case 2:
          _riskLabel = "HIGH RISK";
          _statusColor = AppColors.high;
          _recommendationText = actions.isEmpty ? "No actions required" : actions.join("\n");
          break;
        default:
          _riskLabel = "UNKNOWN";
          _statusColor = AppColors.textLow;
          _recommendationText = "No data";
      }
    });

    if (selectedPlant != null) {
      NotificationService.maybeNotify(selectedPlant!, risk, actions);
    }
  }

  @override
  void initState() {
    super.initState();
    _loadAll();
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    _realtimeChannel = supabase
        .channel('plant_readings_inserts')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'plant_readings',
          callback: (payload) async {
            final row = payload.newRecord;
            final plant = row['plant_label'] as String?;
            if (plant == null) return;

            // Always refresh UI if this is the selected plant.
            if (plant == selectedPlant) {
              loadLatestStatus();
              // Clear the "measuring" spinner if it was triggered manually
              if (_measuring) {
                _measureTimeout?.cancel();
                if (mounted) setState(() => _measuring = false);
              }
            }

            // Fire a notification for any non-healthy insert, for any plant.
            final risk = (row['risk_class'] ?? 0) as int;
            if (risk == 0) return;
            if (!AppSettings.notificationsEnabled) return;

            final actions = <String>[];
            if (row['action_reduce_temp'] == true || row['action_reduce_temp'] == 1) actions.add("Reduce temperature");
            if (row['action_water']       == true || row['action_water']       == 1) actions.add("Water the plant");
            if (row['action_increase_light'] == true || row['action_increase_light'] == 1) actions.add("Increase light exposure");

            await NotificationService.maybeNotify(plant, risk, actions);
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_realtimeChannel != null) supabase.removeChannel(_realtimeChannel!);
    _iconTapTimer?.cancel();
    _readingsTapTimer?.cancel();
    _measureTimeout?.cancel();
    super.dispose();
  }

  Future<void> openAppSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AppSettingsPage()),
    );
    if (mounted) setState(() {});
  }

  Future<void> openProfileSettings() async {
    final selected = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            ProfileSettingsPage(plants: plants, selectedPlant: selectedPlant),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => selectedPlant = selected);
    await loadLatestStatus();
  }

  Future<void> _openAddDevice() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DeviceScanScreen()),
    );
    // Reload plants in case a new one was just provisioned
    if (mounted) await loadPlants();
  }

  Future<void> _triggerMeasurement() async {
    final deviceId = _deviceIds[selectedPlant];
    if (deviceId == null || deviceId.isEmpty) {
      _showEasterEgg("⚠️ This plant has no linked device.");
      return;
    }
    setState(() => _measuring = true);
    try {
      await supabase
          .from('devices')
          .update({'trigger_measurement': true})
          .eq('device_id', deviceId);
      // The realtime subscription will pick up the incoming reading and clear
      // _measuring automatically.  Fall back after 2 minutes.
      _measureTimeout?.cancel();
      _measureTimeout = Timer(const Duration(minutes: 2), () {
        if (mounted) setState(() => _measuring = false);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _measuring = false);
        _showEasterEgg("❌ Could not trigger measurement: $e");
      }
    }
  }

  Widget buildPlantSelector() {
    final plantValue = plants.contains(selectedPlant) ? selectedPlant : null;
    return DropdownButtonFormField<String>(
      key: ValueKey("dashboard-plant-$plantValue"),
      initialValue: plantValue,
      decoration: const InputDecoration(labelText: "Plant"),
      hint: Text(
        "Select a plant",
        style: GoogleFonts.outfit(color: AppColors.textLow, fontSize: 14),
      ),
      items: plants
          .map(
            (p) => DropdownMenuItem(
              value: p,
              child: Text(p, style: GoogleFonts.outfit(color: AppColors.textMid)),
            ),
          )
          .toList(),
      onChanged: (v) {
        setState(() => selectedPlant = v);
        loadLatestStatus();
        _loadPreferences();
      },
    );
  }

  Widget _sensorTile(String lbl, String? value, String unit, IconData icon, Color color,
      {String band = '', String pref = ''}) {
    Widget? bandBadge;
    if (band.isNotEmpty && value != null) {
      final matches = band == pref;
      final badgeColor = matches
          ? AppColors.textLow
          : band == 'high'
              ? AppColors.moderate
              : const Color(0xFF60A5FA);
      final badgeLabel = band.toUpperCase();
      bandBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: badgeColor.withAlpha(30),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: badgeColor.withAlpha(70), width: 0.5),
        ),
        child: Text(badgeLabel,
            style: GoogleFonts.outfit(fontSize: 10, color: badgeColor, fontWeight: FontWeight.w600, letterSpacing: 0.6)),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(lbl, style: GoogleFonts.outfit(fontSize: 11, color: AppColors.textLow, letterSpacing: 0.5)),
            if (bandBadge != null) ...[const Spacer(), bandBadge],
          ]),
          const SizedBox(height: 8),
          value == null
              ? Text("—", style: GoogleFonts.outfit(fontSize: 20, color: AppColors.textLow))
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(value, style: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textHigh)),
                    const SizedBox(width: 3),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(unit, style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textLow)),
                    ),
                  ],
                ),
        ],
      ),
    );
  }

  // Returns 'low', 'mid', or 'high' for a value given ESP32 MetricThresholds.
  static String _valueBand(double? v, double lowMax, double midMin, double midMax, double highMin) {
    if (v == null) return '';
    if (v <= lowMax) return 'low';
    if (v >= highMin) return 'high';
    return 'mid'; // includes transition zones
  }

  Widget buildSensorGrid() {
    final soilBand     = _valueBand(_soilPct,     28, 33, 55, 60);
    final tempBand     = _valueBand(_tempC,        16, 18, 26, 28);
    final humidityBand = _valueBand(_humidityPct,  45, 50, 70, 75);
    final lightBand    = _valueBand(_lightPct,     20, 25, 65, 70);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _onReadingsTap,
          child: Text("LIVE READINGS", style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textLow, letterSpacing: 1.8)),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _sensorTile("SOIL", _soilPct?.toStringAsFixed(1), "%", Icons.water_drop_outlined, AppColors.accent, band: soilBand, pref: _soilPref)),
          const SizedBox(width: 10),
          Expanded(child: _sensorTile("TEMP", _tempC?.toStringAsFixed(1), "°C", Icons.thermostat_outlined, AppColors.high, band: tempBand, pref: _tempPref)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _sensorTile("HUMIDITY", _humidityPct?.toStringAsFixed(1), "%", Icons.water_outlined, const Color(0xFF60A5FA), band: humidityBand, pref: _humidityPref)),
          const SizedBox(width: 10),
          Expanded(child: _sensorTile("LIGHT", _lightPct?.toStringAsFixed(1), "%", Icons.light_mode_outlined, const Color(0xFFFBBF24), band: lightBand, pref: _lightPref)),
        ]),
      ],
    );
  }

  String _fmtMinutes(double minutes) {
    if (minutes >= 1440) {
      final days = minutes / 1440;
      return "${days % 1 == 0 ? days.toInt() : days.toStringAsFixed(1)} day${days >= 2 ? 's' : ''}";
    }
    if (minutes >= 60) {
      final hours = minutes / 60;
      return "${hours % 1 == 0 ? hours.toInt() : hours.toStringAsFixed(1)} hour${hours >= 2 ? 's' : ''}";
    }
    return "${minutes.toInt()} min";
  }

  String _predLabel(String key) {
    switch (key.toLowerCase()) {
      case 'water': return 'Water in';
      case 'temp':
      case 'temperature': return 'Temp action in';
      case 'light': return 'Light action in';
      default: return '$key in';
    }
  }

  Widget buildStatusCard() {
    final noPlant = selectedPlant == null;
    final isHealthy = !noPlant && _riskClass == 0;
    final displayColor = noPlant ? AppColors.textLow : _statusColor;
    final displayLabel = noPlant ? "UNKNOWN" : _riskLabel;
    final displayRec   = noPlant ? "Select a plant to see recommendations" : _recommendationText;
    final borderColor = displayColor.withOpacity(0.4);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onLongPress: _onStatusDotLongPress,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: displayColor,
                    boxShadow: [BoxShadow(color: displayColor.withOpacity(0.5), blurRadius: 6)],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                "STATUS: $displayLabel",
                style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w600, color: displayColor, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: AppColors.border),
          const SizedBox(height: 14),
          Text("RECOMMENDATION", style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textLow, letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Text(
            displayRec,
            style: GoogleFonts.outfit(fontSize: 14, color: isHealthy ? AppColors.accent : AppColors.textMid),
          ),
          if (!noPlant && _predictions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(height: 1, color: AppColors.border),
            const SizedBox(height: 14),
            Text("PREDICTIONS", style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textLow, letterSpacing: 1.5)),
            const SizedBox(height: 10),
            ..._predictions.entries.map((e) {
              final timeStr = _fmtMinutes(e.value);
              final urgent = e.value < 60;
              final color = urgent ? AppColors.moderate : AppColors.textMid;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(Icons.schedule, size: 14, color: color),
                    const SizedBox(width: 8),
                    Text("${_predLabel(e.key)}: ", style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textLow)),
                    Text(timeStr, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWide = screenWidth >= 700;
    final showSettingsLabel = screenWidth >= 420;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(onTap: _onIconTap, child: const _MiniPlantIcon()),
            const SizedBox(width: 10),
            const Text("PlantHealthMonitor", overflow: TextOverflow.ellipsis),
          ],
        ),
        actions: [
          if (showSettingsLabel) ...[
            FilledButton.icon(
              onPressed: openProfileSettings,
              icon: const Icon(Icons.tune, size: 16),
              label: const Text("Preferences"),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: openAppSettings,
              icon: const Icon(Icons.settings, size: 16),
              label: const Text("Settings"),
            ),
          ] else ...[
            IconButton(tooltip: "Plant Preferences", onPressed: openProfileSettings, icon: const Icon(Icons.tune)),
            IconButton(tooltip: "App Settings", onPressed: openAppSettings, icon: const Icon(Icons.settings)),
          ],
          const SizedBox(width: 8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isWide ? 1100.0 : double.infinity),
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                    : RefreshIndicator(
                        color: AppColors.accent,
                        onRefresh: _refreshWithEasterEgg,
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            buildPlantSelector(),
                            const SizedBox(height: 12),
                            buildStatusCard(),
                            const SizedBox(height: 20),
                            buildSensorGrid(),
                            if (selectedPlant != null) ...[
                              const SizedBox(height: 20),
                              // ── Measure Now ──────────────────────────────
                              if (_deviceIds[selectedPlant] != null &&
                                  _deviceIds[selectedPlant]!.isNotEmpty)
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _measuring
                                        ? AppColors.surface2
                                        : AppColors.accentDim,
                                    foregroundColor: AppColors.textHigh,
                                    minimumSize: const Size.fromHeight(44),
                                  ),
                                  onPressed: _measuring ? null : _triggerMeasurement,
                                  icon: _measuring
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppColors.accent,
                                          ),
                                        )
                                      : const Icon(Icons.sensors, size: 16),
                                  label: Text(
                                    _measuring ? "Measuring…" : "Measure Now",
                                  ),
                                ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => DataPage(plants: plants, selectedPlant: selectedPlant),
                                  ),
                                ),
                                icon: const Icon(Icons.show_chart, size: 16),
                                label: const Text("View Charts & Data"),
                              ),
                            ],
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Mini plant icon for AppBar ───────────────────────────────────────────────
class _MiniPlantIcon extends StatelessWidget {
  const _MiniPlantIcon();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x334ADE80)),
      ),
      child: Center(
        child: CustomPaint(
          size: const Size(16, 16),
          painter: _PlantIconPainter(),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  APP SETTINGS PAGE
// ═══════════════════════════════════════════════════════════════════════════════

class AppSettingsPage extends StatefulWidget {
  const AppSettingsPage({super.key});

  @override
  State<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends State<AppSettingsPage> {
  bool _notifications  = AppSettings.notificationsEnabled;
  bool _dailyReport    = AppSettings.dailyReportEnabled;
  int  _reportHour     = AppSettings.dailyReportHour;
  // Snap to nearest quarter-hour on load.
  int  _reportMinute   = const [0, 15, 30, 45].reduce((a, b) =>
      (AppSettings.dailyReportMinute - a).abs() <= (AppSettings.dailyReportMinute - b).abs() ? a : b);

  List<String> _plants = [];

  // Connected devices: list of {device_id, plant_label, status, last_seen}
  List<Map<String, dynamic>> _connectedDevices = [];
  bool _devicesLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPlants();
    _loadDevices();
  }

  Future<void> _loadPlants() async {
    final res = await supabase.from('plant_settings').select('plant_label');
    if (!mounted) return;
    setState(() => _plants = (res as List).map((e) => e['plant_label'] as String).toList());
  }

  Future<void> _loadDevices() async {
    if (!mounted) return;
    setState(() => _devicesLoading = true);
    try {
      // Fetch all plant_settings rows that have a device linked
      final psRes = await supabase
          .from('plant_settings')
          .select('plant_label, device_id')
          .not('device_id', 'is', null);

      final List<Map<String, dynamic>> result = [];
      for (final row in psRes as List) {
        final deviceId = row['device_id'] as String?;
        if (deviceId == null || deviceId.isEmpty) continue;
        // Fetch device info
        final devRes = await supabase
            .from('devices')
            .select('status, last_seen')
            .eq('device_id', deviceId)
            .limit(1);
        if (devRes.isNotEmpty) {
          result.add({
            'device_id':   deviceId,
            'plant_label': row['plant_label'],
            'status':      devRes[0]['status'] ?? 'unknown',
            'last_seen':   devRes[0]['last_seen'],
          });
        }
      }
      if (!mounted) return;
      setState(() => _connectedDevices = result);
    } finally {
      if (mounted) setState(() => _devicesLoading = false);
    }
  }

  Future<void> _removeDevice(Map<String, dynamic> device) async {
    final deviceId   = device['device_id']   as String;
    final plantLabel = device['plant_label'] as String;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: Text('Remove device?',
            style: GoogleFonts.outfit(color: AppColors.textHigh, fontSize: 16, fontWeight: FontWeight.w600)),
        content: Text(
          'This will unlink the device from "$plantLabel" and trigger a factory reset on the ESP32 so it can be re-provisioned by someone else.\n\nAll historical readings will be kept.',
          style: GoogleFonts.outfit(color: AppColors.textMid, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: GoogleFonts.outfit(color: AppColors.textLow)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Remove', style: GoogleFonts.outfit(color: AppColors.high, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      // 1. Tell the ESP32 to factory-reset on next wake
      await supabase
          .from('devices')
          .update({'trigger_reset': true})
          .eq('device_id', deviceId);

      // 2. Unlink the device from the plant (keeps the plant_settings row)
      await supabase
          .from('plant_settings')
          .update({'device_id': null})
          .eq('device_id', deviceId);

      // 3. Refresh the list
      await _loadDevices();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to remove device: $e',
            style: GoogleFonts.outfit(color: AppColors.textHigh, fontSize: 13)),
        backgroundColor: AppColors.surface2,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
      ));
    }
  }

  String _fmtLastSeen(String? ts) {
    if (ts == null) return 'Never';
    final t = DateTime.tryParse(ts)?.toLocal();
    if (t == null) return 'Unknown';
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 2)  return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours   < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Future<void> _applyDailyReport(bool enabled) async {
    setState(() => _dailyReport = enabled);
    await AppSettings.setDailyReport(enabled: enabled, hour: _reportHour, minute: _reportMinute);
    if (enabled) {
      await NotificationService.scheduleDailyReport(plants: _plants, hour: _reportHour, minute: _reportMinute);
    } else {
      await NotificationService.cancelDailyReport();
    }
  }

  Future<void> _updateTime({int? hour, int? minute}) async {
    setState(() {
      if (hour   != null) _reportHour   = hour;
      if (minute != null) _reportMinute = minute;
    });
    await AppSettings.setDailyReport(enabled: _dailyReport, hour: _reportHour, minute: _reportMinute);
    if (_dailyReport) {
      await NotificationService.scheduleDailyReport(plants: _plants, hour: _reportHour, minute: _reportMinute);
    }
  }

  Widget _settingsTile({required Widget child}) => Material(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: "Back", onPressed: () => Navigator.of(context).pop(), icon: const Icon(CupertinoIcons.back)),
        title: const Text("App Settings"),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(height: 1, color: AppColors.border)),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text("NOTIFICATIONS", style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textLow, letterSpacing: 1.8)),
                    const SizedBox(height: 12),

                    // ── Plant alerts ──
                    _settingsTile(
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text("Plant alerts", style: GoogleFonts.outfit(color: AppColors.textHigh, fontSize: 15)),
                        subtitle: Text("Get notified when your plant needs watering, light adjustment, or temperature changes.", style: GoogleFonts.outfit(color: AppColors.textLow, fontSize: 12)),
                        value: _notifications,
                        activeThumbColor: AppColors.accent,
                        activeTrackColor: AppColors.accentDim,
                        onChanged: (v) async {
                          setState(() => _notifications = v);
                          await AppSettings.setNotificationsEnabled(v);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Daily report ──
                    _settingsTile(
                      child: Column(
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text("Daily plant report", style: GoogleFonts.outfit(color: AppColors.textHigh, fontSize: 15)),
                            subtitle: Text("Receive a daily notification with the status of each plant.", style: GoogleFonts.outfit(color: AppColors.textLow, fontSize: 12)),
                            value: _dailyReport,
                            activeThumbColor: AppColors.accent,
                            activeTrackColor: AppColors.accentDim,
                            onChanged: _applyDailyReport,
                          ),
                          if (_dailyReport) ...[
                            Container(height: 1, color: AppColors.border),
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Row(
                                children: [
                                  Text("Report time", style: GoogleFonts.outfit(color: AppColors.textMid, fontSize: 14)),
                                  const Spacer(),
                                  // Hour dropdown
                                  DropdownButton<int>(
                                    value: _reportHour,
                                    dropdownColor: AppColors.surface2,
                                    style: GoogleFonts.outfit(color: AppColors.accent, fontSize: 15, fontWeight: FontWeight.w600),
                                    underline: const SizedBox.shrink(),
                                    items: List.generate(24, (h) => DropdownMenuItem(
                                      value: h,
                                      child: Text(h.toString().padLeft(2, '0')),
                                    )),
                                    onChanged: (h) => _updateTime(hour: h),
                                  ),
                                  Text(":", style: GoogleFonts.outfit(color: AppColors.textMid, fontSize: 15, fontWeight: FontWeight.w600)),
                                  // Minute dropdown (0, 15, 30, 45)
                                  DropdownButton<int>(
                                    value: _reportMinute,
                                    dropdownColor: AppColors.surface2,
                                    style: GoogleFonts.outfit(color: AppColors.accent, fontSize: 15, fontWeight: FontWeight.w600),
                                    underline: const SizedBox.shrink(),
                                    items: [0, 15, 30, 45].map((m) => DropdownMenuItem(
                                      value: m,
                                      child: Text(m.toString().padLeft(2, '0')),
                                    )).toList(),
                                    onChanged: (m) => _updateTime(minute: m),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),
                    Text(
                      "Plant alerts fire automatically when a new reading with moderate or high risk is detected. The daily report sends one notification per day at your chosen time with the status of every plant.",
                      style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textLow),
                    ),

                    const SizedBox(height: 28),
                    // ── Connected Devices ──────────────────────────────────
                    Row(
                      children: [
                        Text("CONNECTED DEVICES",
                            style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textLow, letterSpacing: 1.8)),
                        const Spacer(),
                        IconButton(
                          tooltip: "Refresh",
                          icon: const Icon(Icons.refresh, size: 16, color: AppColors.textLow),
                          onPressed: _loadDevices,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const DeviceScanScreen()),
                            );
                            _loadDevices();
                          },
                          icon: const Icon(Icons.add, size: 14),
                          label: const Text("Add Device"),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.accent,
                            side: const BorderSide(color: AppColors.accentDim),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    if (_devicesLoading)
                      const Center(child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2),
                      ))
                    else if (_connectedDevices.isEmpty)
                      _settingsTile(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Row(
                            children: [
                              const Icon(Icons.sensors_off, size: 18, color: AppColors.textLow),
                              const SizedBox(width: 12),
                              Text("No devices connected",
                                  style: GoogleFonts.outfit(color: AppColors.textLow, fontSize: 14)),
                            ],
                          ),
                        ),
                      )
                    else
                      _settingsTile(
                        child: Column(
                          children: [
                            for (int i = 0; i < _connectedDevices.length; i++) ...[
                              if (i > 0) Container(height: 1, color: AppColors.border),
                              _DeviceRow(
                                device: _connectedDevices[i],
                                lastSeenLabel: _fmtLastSeen(_connectedDevices[i]['last_seen'] as String?),
                                onRemove: () => _removeDevice(_connectedDevices[i]),
                              ),
                            ],
                          ],
                        ),
                      ),

                    const SizedBox(height: 10),
                    Text(
                      "Removing a device unlinks it from its plant and sends a factory-reset command to the ESP32 so it can be re-provisioned. Historical readings are never deleted.",
                      style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textLow),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Device row widget ────────────────────────────────────────────────────────
class _DeviceRow extends StatelessWidget {
  final Map<String, dynamic> device;
  final String lastSeenLabel;
  final VoidCallback onRemove;

  const _DeviceRow({
    required this.device,
    required this.lastSeenLabel,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final deviceId   = device['device_id']   as String;
    final plantLabel = device['plant_label'] as String;
    final status     = device['status']      as String;
    final isActive   = status == 'active';
    final statusColor = isActive ? AppColors.accent : AppColors.textLow;
    // Show last 8 chars of device ID to keep it readable
    final shortId = deviceId.length > 8 ? '…${deviceId.substring(deviceId.length - 8)}' : deviceId;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          // Status dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
              boxShadow: isActive
                  ? [BoxShadow(color: statusColor.withOpacity(0.5), blurRadius: 5)]
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(plantLabel,
                    style: GoogleFonts.outfit(color: AppColors.textHigh, fontSize: 14, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text('ID: $shortId',
                        style: GoogleFonts.outfit(color: AppColors.textLow, fontSize: 11)),
                    const SizedBox(width: 8),
                    Text('·', style: GoogleFonts.outfit(color: AppColors.textLow, fontSize: 11)),
                    const SizedBox(width: 8),
                    Text(lastSeenLabel,
                        style: GoogleFonts.outfit(color: AppColors.textLow, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          // Remove button
          TextButton(
            onPressed: onRemove,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.high,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text('Remove', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  PROFILE SETTINGS PAGE
// ═══════════════════════════════════════════════════════════════════════════════

class ProfileSettingsPage extends StatefulWidget {
  const ProfileSettingsPage({
    super.key,
    required this.plants,
    required this.selectedPlant,
  });

  final List<String> plants;
  final String? selectedPlant;

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  late List<String> plants = [...widget.plants];
  late String? selectedPlant = widget.selectedPlant;

  String humidityPref = "mid";
  String temperaturePref = "mid";
  String soilPref = "mid";
  String lightPref = "mid";

  @override
  void initState() {
    super.initState();
    if (plants.isEmpty) loadPlants();
    loadPlantSettings();
  }

  Future<void> loadPlants() async {
    final res = await supabase.from('plant_settings').select('plant_label');
    final list = (res as List).map((e) => e['plant_label'] as String).toList();
    if (!mounted) return;
    setState(() {
      plants = list;
      if (!plants.contains(selectedPlant)) selectedPlant = null;
    });
  }

  void showTopMessage(String message, Color color) {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        top: 50,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.5)),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              message,
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 2), entry.remove);
  }

  String normalize(String? v) {
    switch (v) {
      case "pLow":
        return "low";
      case "pMid":
        return "mid";
      case "pHigh":
        return "high";
      default:
        return "mid";
    }
  }

  String toDbValue(String v) {
    switch (v) {
      case "low":
        return "pLow";
      case "mid":
        return "pMid";
      case "high":
        return "pHigh";
      default:
        return "pMid";
    }
  }

  Future<void> loadPlantSettings() async {
    if (selectedPlant == null) return;
    final res = await supabase
        .from('plant_settings')
        .select()
        .eq('plant_label', selectedPlant!)
        .limit(1);
    if (res.isEmpty) return;
    final row = res[0];
    if (!mounted) return;
    setState(() {
      humidityPref = normalize(row['humidity_preference']);
      temperaturePref = normalize(row['temperature_preference']);
      soilPref = normalize(row['soil_preference']);
      lightPref = normalize(row['light_preference']);
    });
  }

  Future<void> savePlantSettings() async {
    if (selectedPlant == null) {
      showTopMessage("No plant selected", AppColors.high);
      return;
    }
    try {
      final current = await supabase
          .from('plant_settings')
          .select('version')
          .eq('plant_label', selectedPlant!.trim())
          .single();

      final int newVersion = ((current['version'] ?? 0) as num).toInt() + 1;

      final response = await supabase
          .from('plant_settings')
          .update({
            'humidity_preference': toDbValue(humidityPref),
            'temperature_preference': toDbValue(temperaturePref),
            'soil_preference': toDbValue(soilPref),
            'light_preference': toDbValue(lightPref),
            'version': newVersion,
          })
          .eq('plant_label', selectedPlant!.trim())
          .select();

      if (!mounted) return;

      if (response.isEmpty) {
        showTopMessage(
          "Nothing updated. Check plant selection.",
          AppColors.moderate,
        );
        return;
      }
      showTopMessage("Settings saved successfully", AppColors.healthy);
    } catch (_) {
      if (!mounted) return;
      showTopMessage("Failed to save settings", AppColors.high);
    }
  }

  Widget buildPlantSelector() {
    final plantValue = plants.contains(selectedPlant) ? selectedPlant : null;
    return DropdownButtonFormField<String>(
      key: ValueKey("settings-plant-$plantValue"),
      initialValue: plantValue,
      decoration: const InputDecoration(labelText: "Plant"),
      hint: Text(
        "Select a plant",
        style: GoogleFonts.outfit(color: AppColors.textLow, fontSize: 14),
      ),
      items: plants
          .map(
            (p) => DropdownMenuItem(
              value: p,
              child: Text(
                p,
                style: GoogleFonts.outfit(color: AppColors.textMid),
              ),
            ),
          )
          .toList(),
      onChanged: (v) {
        setState(() => selectedPlant = v);
        loadPlantSettings();
      },
    );
  }

  static const _prefRanges = {
    "Humidity":      {"low": "≤ 45%",     "mid": "50 – 70%",   "high": "≥ 75%"},
    "Temperature":   {"low": "≤ 16 °C",   "mid": "18 – 26 °C", "high": "≥ 28 °C"},
    "Soil Moisture": {"low": "≤ 28%",     "mid": "33 – 55%",   "high": "≥ 60%"},
    "Light":         {"low": "≤ 20%",     "mid": "25 – 65%",   "high": "≥ 70%"},
  };

  Widget buildPreferenceDropdown(
    String lbl,
    String value,
    ValueChanged<String?> onChanged,
  ) {
    final ranges = _prefRanges[lbl];
    final band = ["low", "mid", "high"].contains(value) ? value : "mid";

    Widget item(String label, String band) {
      final range = ranges?[band];
      return Row(
        children: [
          Text(label, style: GoogleFonts.outfit(color: AppColors.textMid)),
          if (range != null) ...[
            const SizedBox(width: 8),
            Text(range, style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textLow)),
          ],
        ],
      );
    }

    return DropdownButtonFormField<String>(
      key: ValueKey("preference-$lbl-$value"),
      initialValue: band,
      decoration: InputDecoration(labelText: lbl),
      items: [
        DropdownMenuItem(value: "low",  child: item("Low",  "low")),
        DropdownMenuItem(value: "mid",  child: item("Mid",  "mid")),
        DropdownMenuItem(value: "high", child: item("High", "high")),
      ],
      onChanged: onChanged,
    );
  }

  void goBack() => Navigator.of(context).pop(selectedPlant);

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 700;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: "Back",
          onPressed: goBack,
          icon: const Icon(CupertinoIcons.back),
        ),
        title: const Text("Plant Preferences"),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    buildPlantSelector(),
                    const SizedBox(height: 20),
                    Text(
                      "PREFERENCES",
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textLow,
                        letterSpacing: 1.8,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (isWide)
                      Row(
                        children: [
                          Expanded(
                            child: buildPreferenceDropdown(
                              "Humidity",
                              humidityPref,
                              (v) {
                                if (v != null) setState(() => humidityPref = v);
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: buildPreferenceDropdown(
                              "Temperature",
                              temperaturePref,
                              (v) {
                                if (v != null)
                                  setState(() => temperaturePref = v);
                              },
                            ),
                          ),
                        ],
                      )
                    else ...[
                      buildPreferenceDropdown("Humidity", humidityPref, (v) {
                        if (v != null) setState(() => humidityPref = v);
                      }),
                      const SizedBox(height: 12),
                      buildPreferenceDropdown("Temperature", temperaturePref, (
                        v,
                      ) {
                        if (v != null) setState(() => temperaturePref = v);
                      }),
                    ],
                    const SizedBox(height: 12),
                    if (isWide)
                      Row(
                        children: [
                          Expanded(
                            child: buildPreferenceDropdown(
                              "Soil Moisture",
                              soilPref,
                              (v) {
                                if (v != null) setState(() => soilPref = v);
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: buildPreferenceDropdown("Light", lightPref, (
                              v,
                            ) {
                              if (v != null) setState(() => lightPref = v);
                            }),
                          ),
                        ],
                      )
                    else ...[
                      buildPreferenceDropdown("Soil Moisture", soilPref, (v) {
                        if (v != null) setState(() => soilPref = v);
                      }),
                      const SizedBox(height: 12),
                      buildPreferenceDropdown("Light", lightPref, (v) {
                        if (v != null) setState(() => lightPref = v);
                      }),
                    ],
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: savePlantSettings,
                      icon: const Icon(Icons.save, size: 16),
                      label: const Text("Save Settings"),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: goBack,
                      icon: const Icon(CupertinoIcons.chevron_back, size: 16),
                      label: const Text("Back"),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  DATA PAGE  (charts + table access)
// ═══════════════════════════════════════════════════════════════════════════════

Color _colorFor(String metric) {
  switch (metric) {
    case "soil_moisture_pct": return AppColors.accent;
    case "temperature_c":     return AppColors.high;
    case "humidity_pct":      return const Color(0xFF60A5FA);
    case "light_level_pct":   return const Color(0xFFFBBF24);
    default:                  return AppColors.textMid;
  }
}

String _metricLabel(String m) {
  switch (m) {
    case "soil_moisture_pct": return "Soil Moisture";
    case "temperature_c":     return "Temperature";
    case "humidity_pct":      return "Humidity";
    case "light_level_pct":   return "Light";
    default:                  return m;
  }
}

class DataPage extends StatefulWidget {
  const DataPage({super.key, required this.plants, required this.selectedPlant});
  final List<String> plants;
  final String? selectedPlant;

  @override
  State<DataPage> createState() => _DataPageState();
}

class _DataPageState extends State<DataPage> {
  static const _metrics = ["soil_moisture_pct", "temperature_c", "humidity_pct", "light_level_pct"];
  static const _allColumns = [
    ('soil_moisture_pct', 'Soil %'),
    ('temperature_c',     'Temp °C'),
    ('humidity_pct',      'Humidity %'),
    ('light_level_pct',   'Light %'),
    ('risk_class',        'Risk'),
    ('recommendation_summary', 'Water in'),
  ];

  List<String> selectedMetrics = ["soil_moisture_pct"];
  String timeRange = "24h";
  List<DateTime> timestamps = [];
  Map<String, List<FlSpot>> graphData = {};
  bool _loading = false;

  // ── inline table state ──
  List<String> _tableColumns = ['soil_moisture_pct'];
  List<Map<String, dynamic>> _tableRows = [];
  bool _tableLoading = false;
  bool _tableVisible = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() => Future.wait([loadGraph(), _fetchTable()]);

  bool isInRange(DateTime t) {
    final now = DateTime.now();
    if (timeRange == "24h") return now.difference(t).inHours <= 24;
    if (timeRange == "7d") return now.difference(t).inDays <= 7;
    return true;
  }

  Future<void> loadGraph() async {
    if (widget.selectedPlant == null) return;
    setState(() => _loading = true);

    final response = await supabase
        .from('plant_readings')
        .select()
        .eq('plant_label', widget.selectedPlant!)
        .order('timestamp', ascending: true);

    final data = List<Map<String, dynamic>>.from(response);
    final Map<String, List<FlSpot>> temp = {};
    final List<DateTime> loadedTimestamps = [];

    final filtered = data.where((row) => isInRange(DateTime.parse(row['timestamp']))).toList();

    for (int i = 0; i < filtered.length; i++) {
      final row = filtered[i];
      loadedTimestamps.add(DateTime.parse(row['timestamp']).toLocal());
      for (final m in selectedMetrics) {
        final value = (row[m] ?? 0).toDouble().clamp(0.0, 100.0);
        temp.putIfAbsent(m, () => []);
        temp[m]!.add(FlSpot(i.toDouble(), value));
      }
    }

    if (!mounted) return;
    setState(() {
      timestamps = loadedTimestamps;
      graphData = temp;
      _loading = false;
    });
  }

  Future<void> _fetchTable() async {
    if (widget.selectedPlant == null) return;
    setState(() => _tableLoading = true);

    final cols = ['plant_label', 'timestamp', ..._tableColumns].join(',');
    final res = await supabase
        .from('plant_readings')
        .select(cols)
        .eq('plant_label', widget.selectedPlant!)
        .order('timestamp', ascending: false)
        .limit(200);

    final now = DateTime.now();
    final rows = List<Map<String, dynamic>>.from(res).where((row) {
      final t = DateTime.parse(row['timestamp']);
      if (timeRange == '24h') return now.difference(t).inHours <= 24;
      if (timeRange == '7d') return now.difference(t).inDays <= 7;
      return true;
    }).toList();

    if (!mounted) return;
    setState(() {
      _tableRows = rows;
      _tableLoading = false;
    });
  }

  String _fmtTimestamp(String ts) {
    final t = DateTime.parse(ts).toLocal();
    return "${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')} "
        "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";
  }

  String _fmtValue(dynamic v, String col) {
    if (v == null) return '—';
    if (col == 'risk_class') {
      return switch (v) { 0 => 'Healthy', 1 => 'Moderate', 2 => 'High', _ => '$v' };
    }
    if (col == 'recommendation_summary') {
      final match = RegExp(r'predWaterMin[=:\s]+([\d.]+)').firstMatch(v as String? ?? '');
      if (match == null) return '—';
      final minutes = double.parse(match.group(1)!);
      if (minutes >= 1440) { final d = minutes / 1440; return "${d % 1 == 0 ? d.toInt() : d.toStringAsFixed(1)}d"; }
      if (minutes >= 60)   { final h = minutes / 60;   return "${h % 1 == 0 ? h.toInt() : h.toStringAsFixed(1)}h"; }
      return "${minutes.toInt()} min";
    }
    return (v as num).toStringAsFixed(1);
  }

  Color _riskColor(dynamic v) => switch (v) {
    0 => AppColors.healthy, 1 => AppColors.moderate, 2 => AppColors.high, _ => AppColors.textLow
  };

  Widget buildMetricSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _metrics.map((m) {
        final sel = selectedMetrics.contains(m);
        return FilterChip(
          label: Text(_metricLabel(m)),
          selected: sel,
          onSelected: (v) {
            setState(() { if (v) selectedMetrics.add(m); else selectedMetrics.remove(m); });
            loadGraph();
          },
        );
      }).toList(),
    );
  }

  Widget buildLegend() {
    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: selectedMetrics.map((m) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: _colorFor(m), borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 6),
            Text(_metricLabel(m), style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textMid)),
          ],
        );
      }).toList(),
    );
  }

  Widget buildChart(bool isWide) {
    if (selectedMetrics.isEmpty) {
      return Center(child: Text("Select at least one metric", style: GoogleFonts.outfit(color: AppColors.textLow)));
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (graphData.isEmpty) {
      return Center(child: Text("No data for selected range", style: GoogleFonts.outfit(color: AppColors.textLow)));
    }

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 100,
        backgroundColor: Colors.transparent,
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.surface2,
            getTooltipItems: (spots) {
              final i = spots.first.x.toInt();
              final t = (i >= 0 && i < timestamps.length) ? timestamps[i] : null;
              final dateStr = t != null
                  ? "${t.day}/${t.month}  ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}"
                  : "";
              return List.generate(spots.length, (idx) {
                final spot = spots[idx];
                final metricName = spot.barIndex < selectedMetrics.length ? selectedMetrics[spot.barIndex] : '';
                final isLast = idx == spots.length - 1;
                return LineTooltipItem(
                  "${_metricLabel(metricName)}: ${spot.y.toStringAsFixed(1)}",
                  GoogleFonts.outfit(color: _colorFor(metricName), fontSize: 11),
                  children: isLast && dateStr.isNotEmpty
                      ? [TextSpan(text: '\n$dateStr', style: GoogleFonts.outfit(color: AppColors.textLow, fontSize: 10))]
                      : [],
                );
              });
            },
          ),
        ),
        gridData: FlGridData(
          show: true,
          getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.gridLine, strokeWidth: 1),
          getDrawingVerticalLine: (_) => const FlLine(color: AppColors.gridLine, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: true, border: Border.all(color: AppColors.border)),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: timestamps.isNotEmpty ? (timestamps.length / 5).ceilToDouble() : 1,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= timestamps.length) return const Text("");
                final t = timestamps[i];
                return Text("${t.day}/${t.month}", style: GoogleFonts.outfit(fontSize: 10, color: AppColors.textLow));
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(
                value.toInt().toString(),
                style: GoogleFonts.outfit(fontSize: 10, color: AppColors.textLow),
              ),
            ),
          ),
        ),
        lineBarsData: selectedMetrics.map((m) {
          return LineChartBarData(
            spots: graphData[m] ?? [],
            isCurved: true,
            preventCurveOverShooting: true,
            barWidth: 2,
            color: _colorFor(m),
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: _colorFor(m).withOpacity(0.06)),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInlineTable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("DATA", style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.textLow, letterSpacing: 1.8)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: _allColumns.map((c) {
            final sel = _tableColumns.contains(c.$1);
            final atMax = _tableColumns.length >= 2 && !sel;
            return FilterChip(
              label: Text(c.$2),
              selected: sel,
              onSelected: atMax ? null : (v) {
                setState(() { if (v) _tableColumns.add(c.$1); else _tableColumns.remove(c.$1); });
                _fetchTable();
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        if (_tableLoading)
          const Center(child: CircularProgressIndicator(color: AppColors.accent))
        else if (_tableRows.isEmpty)
          Center(child: Text("No data found", style: GoogleFonts.outfit(color: AppColors.textLow, fontSize: 13)))
        else
          LayoutBuilder(builder: (context, constraints) {
            final totalCols = 1 + _tableColumns.length; // TIME + selected
            const minColWidth = 88.0;
            final minTableWidth = totalCols * minColWidth;
            final tableWidth = minTableWidth > constraints.maxWidth ? minTableWidth : constraints.maxWidth;
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(AppColors.surface),
                  dataRowColor: WidgetStateProperty.all(Colors.transparent),
                  dividerThickness: 1,
                  columnSpacing: 20,
                  headingTextStyle: GoogleFonts.outfit(color: AppColors.textLow, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.2),
                  dataTextStyle: GoogleFonts.outfit(color: AppColors.textMid, fontSize: 13),
                  columns: [
                    const DataColumn(label: Text("TIME")),
                    ..._tableColumns.map((col) {
                      final lbl = _allColumns.firstWhere((c) => c.$1 == col).$2.toUpperCase();
                      return DataColumn(label: Text(lbl));
                    }),
                  ],
                  rows: _tableRows.map((row) {
                    return DataRow(cells: [
                      DataCell(Text(_fmtTimestamp(row['timestamp']), style: GoogleFonts.outfit(color: AppColors.textLow, fontSize: 12))),
                      ..._tableColumns.map((col) {
                        final v = row[col];
                        if (col == 'risk_class') {
                          return DataCell(Text(_fmtValue(v, col), style: GoogleFonts.outfit(color: _riskColor(v), fontSize: 13, fontWeight: FontWeight.w600)));
                        }
                        return DataCell(Text(_fmtValue(v, col)));
                      }),
                    ]);
                  }).toList(),
                ),
              ),
            );
          }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= 700;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: "Back", onPressed: () => Navigator.of(context).pop(), icon: const Icon(CupertinoIcons.back)),
        title: const Text("Charts & Data"),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Container(height: 1, color: AppColors.border)),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isWide ? 1100.0 : double.infinity),
                child: RefreshIndicator(
                  color: AppColors.accent,
                  onRefresh: _loadAll,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      buildMetricSelector(),
                      const SizedBox(height: 12),
                      buildLegend(),
                      const SizedBox(height: 16),
                      Container(
                        height: isWide ? 420 : 320,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: buildChart(isWide),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        key: ValueKey("datapage-range-$timeRange"),
                        initialValue: timeRange,
                        decoration: const InputDecoration(labelText: "Time range"),
                        items: [
                          DropdownMenuItem(value: "24h", child: Text("Past 24 hours", style: GoogleFonts.outfit(color: AppColors.textMid))),
                          DropdownMenuItem(value: "7d",  child: Text("Past 7 days",   style: GoogleFonts.outfit(color: AppColors.textMid))),
                          DropdownMenuItem(value: "all", child: Text("All time",       style: GoogleFonts.outfit(color: AppColors.textMid))),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => timeRange = v);
                          _loadAll();
                        },
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () {
                          setState(() => _tableVisible = !_tableVisible);
                          if (_tableVisible && _tableRows.isEmpty) _fetchTable();
                        },
                        icon: Icon(_tableVisible ? Icons.table_chart : Icons.table_chart_outlined, size: 16),
                        label: Text(_tableVisible ? "Hide Data Table" : "Show Data Table"),
                      ),
                      if (_tableVisible) ...[
                        const SizedBox(height: 16),
                        _buildInlineTable(),
                      ],
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  DATA TABLE PAGE
// ═══════════════════════════════════════════════════════════════════════════════

class DataTablePage extends StatefulWidget {
  const DataTablePage({
    super.key,
    required this.plants,
    required this.initialPlant,
  });

  final List<String> plants;
  final String? initialPlant;

  @override
  State<DataTablePage> createState() => _DataTablePageState();
}

class _DataTablePageState extends State<DataTablePage> {
  late List<String> _selectedPlants;
  List<String> _selectedColumns = ['soil_moisture_pct'];
  String _timeRange = '24h';
  List<Map<String, dynamic>> _rows = [];
  bool _loading = false;

  static const _allColumns = [
    ('soil_moisture_pct', 'Soil %'),
    ('temperature_c', 'Temp °C'),
    ('humidity_pct', 'Humidity %'),
    ('light_level_pct', 'Light %'),
    ('risk_class', 'Risk'),
    ('recommendation_summary', 'Water in'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedPlants =
        widget.initialPlant != null ? [widget.initialPlant!] : [];
    if (_selectedPlants.isNotEmpty) _fetchData();
  }

  Future<void> _fetchData() async {
    if (_selectedPlants.isEmpty || _selectedColumns.isEmpty) return;
    setState(() => _loading = true);

    final cols = ['plant_label', 'timestamp', ..._selectedColumns].join(',');
    final List<Map<String, dynamic>> all = [];

    for (final plant in _selectedPlants) {
      final res = await supabase
          .from('plant_readings')
          .select(cols)
          .eq('plant_label', plant)
          .order('timestamp', ascending: false)
          .limit(200);
      all.addAll(List<Map<String, dynamic>>.from(res));
    }

    final now = DateTime.now();
    final filtered = all.where((row) {
      final t = DateTime.parse(row['timestamp']);
      if (_timeRange == '24h') return now.difference(t).inHours <= 24;
      if (_timeRange == '7d') return now.difference(t).inDays <= 7;
      return true;
    }).toList();

    filtered.sort((a, b) => DateTime.parse(b['timestamp'])
        .compareTo(DateTime.parse(a['timestamp'])));

    if (!mounted) return;
    setState(() {
      _rows = filtered;
      _loading = false;
    });
  }

  String _fmtTimestamp(String ts) {
    final t = DateTime.parse(ts).toLocal();
    return "${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')} "
        "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";
  }

  String _fmtValue(dynamic v, String col) {
    if (v == null) return '—';
    if (col == 'risk_class') {
      return switch (v) {
        0 => 'Healthy',
        1 => 'Moderate',
        2 => 'High',
        _ => '$v',
      };
    }
    if (col == 'recommendation_summary') {
      final summary = v as String? ?? '';
      final match = RegExp(r'predWaterMin[=:\s]+([\d.]+)').firstMatch(summary);
      if (match == null) return '—';
      final minutes = double.parse(match.group(1)!);
      if (minutes >= 1440) {
        final d = minutes / 1440;
        return "${d % 1 == 0 ? d.toInt() : d.toStringAsFixed(1)}d";
      }
      if (minutes >= 60) {
        final h = minutes / 60;
        return "${h % 1 == 0 ? h.toInt() : h.toStringAsFixed(1)}h";
      }
      return "${minutes.toInt()} min";
    }
    return (v as num).toStringAsFixed(1);
  }

  Color _riskColor(dynamic v) => switch (v) {
        0 => AppColors.healthy,
        1 => AppColors.moderate,
        2 => AppColors.high,
        _ => AppColors.textLow,
      };

  bool get _canFetch =>
      _selectedPlants.isNotEmpty && _selectedColumns.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final showPlantCol = _selectedPlants.length > 1;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: "Back",
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(CupertinoIcons.back),
        ),
        title: const Text("Data Table"),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Filters ──────────────────────────────────────────────
                Container(
                  color: AppColors.bg,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "PLANTS",
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textLow,
                          letterSpacing: 1.6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: widget.plants.map((p) {
                          final sel = _selectedPlants.contains(p);
                          return FilterChip(
                            label: Text(p),
                            selected: sel,
                            onSelected: (v) {
                              setState(() {
                                if (v) {
                                  _selectedPlants.add(p);
                                } else {
                                  _selectedPlants.remove(p);
                                }
                              });
                              _fetchData();
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "FEATURES",
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textLow,
                          letterSpacing: 1.6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: _allColumns.map((c) {
                          final sel = _selectedColumns.contains(c.$1);
                          final atMax = _selectedColumns.length >= 2 && !sel;
                          return FilterChip(
                            label: Text(c.$2),
                            selected: sel,
                            onSelected: atMax
                                ? null
                                : (v) {
                                    setState(() {
                                      if (v) {
                                        _selectedColumns.add(c.$1);
                                      } else {
                                        _selectedColumns.remove(c.$1);
                                      }
                                    });
                                    _fetchData();
                                  },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "TIME RANGE",
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textLow,
                          letterSpacing: 1.6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: const [
                          ('24h', 'Past 24 hours'),
                          ('7d', 'Past 7 days'),
                          ('all', 'All time'),
                        ].map((r) {
                          return ChoiceChip(
                            label: Text(r.$2),
                            selected: _timeRange == r.$1,
                            onSelected: (_) {
                              setState(() => _timeRange = r.$1);
                              _fetchData();
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                Container(height: 1, color: AppColors.border),

                // ── Table ─────────────────────────────────────────────────
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: AppColors.accent,
                          ),
                        )
                      : _rows.isEmpty
                          ? Center(
                              child: Text(
                                _canFetch
                                    ? "No data found"
                                    : "Select at least one plant and one column",
                                style: GoogleFonts.outfit(
                                  color: AppColors.textLow,
                                  fontSize: 13,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final totalCols = (showPlantCol ? 1 : 0) +
                                    1 + // TIME column
                                    _selectedColumns.length;
                                const minColWidth = 88.0;
                                final minTableWidth = totalCols * minColWidth;
                                final tableWidth = minTableWidth > constraints.maxWidth
                                    ? minTableWidth
                                    : constraints.maxWidth;
                                return SingleChildScrollView(
                                  scrollDirection: Axis.vertical,
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: SizedBox(
                                      width: tableWidth,
                                      child: DataTable(
                                  headingRowColor: WidgetStateProperty.all(
                                    AppColors.surface,
                                  ),
                                  dataRowColor: WidgetStateProperty.all(
                                    Colors.transparent,
                                  ),
                                  dividerThickness: 1,
                                  columnSpacing: 20,
                                  headingTextStyle: GoogleFonts.outfit(
                                    color: AppColors.textLow,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.2,
                                  ),
                                  dataTextStyle: GoogleFonts.outfit(
                                    color: AppColors.textMid,
                                    fontSize: 13,
                                  ),
                                  columns: [
                                    if (showPlantCol)
                                      const DataColumn(
                                        label: Text("PLANT"),
                                      ),
                                    const DataColumn(label: Text("TIME")),
                                    ..._selectedColumns.map((col) {
                                      final lbl = _allColumns
                                          .firstWhere((c) => c.$1 == col)
                                          .$2
                                          .toUpperCase();
                                      return DataColumn(label: Text(lbl));
                                    }),
                                  ],
                                  rows: _rows.map((row) {
                                    return DataRow(cells: [
                                      if (showPlantCol)
                                        DataCell(Text(
                                          row['plant_label'] ?? '—',
                                          style: GoogleFonts.outfit(
                                            color: AppColors.accent,
                                            fontSize: 13,
                                          ),
                                        )),
                                      DataCell(Text(
                                        _fmtTimestamp(row['timestamp']),
                                        style: GoogleFonts.outfit(
                                          color: AppColors.textLow,
                                          fontSize: 12,
                                        ),
                                      )),
                                      ..._selectedColumns.map((col) {
                                        final v = row[col];
                                        if (col == 'risk_class') {
                                          return DataCell(Text(
                                            _fmtValue(v, col),
                                            style: GoogleFonts.outfit(
                                              color: _riskColor(v),
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ));
                                        }
                                        return DataCell(
                                          Text(_fmtValue(v, col)),
                                        );
                                      }),
                                    ]);
                                  }).toList(),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
