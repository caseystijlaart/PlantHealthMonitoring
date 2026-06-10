import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_colors.dart';
import '../services/app_settings.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../widgets/grid_painter.dart';
import '../widgets/plant_icon.dart';
import 'app_settings_page.dart';
import 'data_page.dart';
import 'profile_settings_page.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  List<String> plants = [];
  String? selectedPlant;

  int _riskClass = 0;
  String _riskLabel = 'UNKNOWN';
  String _recommendationText = 'No data';
  Map<String, double> _predictions = {};

  double? _soilPct, _tempC, _humidityPct, _lightPct;
  String _soilPref = 'mid', _tempPref = 'mid', _humidityPref = 'mid', _lightPref = 'mid';

  Color _statusColor = AppColors.surface;
  bool _loading = false;
  bool _triggeringMeasurement = false;
  DateTime? _lastReadingTime;
  RealtimeChannel? _realtimeChannel;

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
      _showEasterEgg((_plantWisdom.toList()..shuffle()).first);
    } else {
      _iconTapTimer = Timer(const Duration(milliseconds: 600), () => _iconTapCount = 0);
    }
  }

  void _onStatusDotLongPress() {
    final msgs = _statusMessages[_riskClass] ?? ["Your plant is a mystery. 🌿"];
    _showEasterEgg((msgs.toList()..shuffle()).first);
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
    // Reload the plant list too, not just the selected plant's status — a plant
    // added (or removed) elsewhere must appear/disappear on a manual refresh.
    await loadPlants();
    if (mounted && selectedPlant == null && plants.isNotEmpty) {
      setState(() => selectedPlant = plants.first);
    }
    await loadLatestStatus();
  }

  void _showEasterEgg(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message,
          style: GoogleFonts.outfit(color: AppColors.textHigh, fontSize: 13)),
      backgroundColor: AppColors.surface2,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border)),
      duration: const Duration(seconds: 4),
    ));
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    await Future.wait([loadPlants(), loadLatestStatus(), _loadPreferences()]);
    if (mounted) setState(() => _loading = false);
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

  static String _normPref(dynamic v) => switch (v) {
        'pLow' => 'low',
        'pHigh' => 'high',
        _ => 'mid',
      };

  Future<void> _loadPreferences() async {
    if (selectedPlant == null) return;
    final res = await supabase
        .from('plant_settings')
        .select(
            'soil_preference, temperature_preference, humidity_preference, light_preference')
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

    if (latest['action_reduce_temp'] == true ||
        latest['action_reduce_temp'] == "true" ||
        latest['action_reduce_temp'] == 1) { actions.add("Reduce temperature"); }
    if (latest['action_water'] == true ||
        latest['action_water'] == "true" ||
        latest['action_water'] == 1) { actions.add("Water the plant"); }
    if (latest['action_increase_light'] == true ||
        latest['action_increase_light'] == "true" ||
        latest['action_increase_light'] == 1) { actions.add("Increase light exposure"); }

    if (!mounted) return;
    setState(() {
      _riskClass = risk;
      _predictions = parsedPredictions;
      _soilPct = (latest['soil_moisture_pct'] as num?)?.toDouble();
      _tempC = (latest['temperature_c'] as num?)?.toDouble();
      _humidityPct = (latest['humidity_pct'] as num?)?.toDouble();
      _lightPct = (latest['light_level_pct'] as num?)?.toDouble();
      final tsRaw = latest['timestamp'] as String?;
      _lastReadingTime = tsRaw != null ? DateTime.tryParse(tsRaw)?.toLocal() : null;

      switch (risk) {
        case 0:
          _riskLabel = "HEALTHY";
          _statusColor = AppColors.healthy;
          _recommendationText = "No actions required";
        case 1:
          _riskLabel = "MODERATE RISK";
          _statusColor = AppColors.moderate;
          _recommendationText = actions.isEmpty ? "No actions required" : actions.join("\n");
        case 2:
          _riskLabel = "HIGH RISK";
          _statusColor = AppColors.high;
          _recommendationText = actions.isEmpty ? "No actions required" : actions.join("\n");
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

  Future<void> _triggerMeasurement() async {
    if (selectedPlant == null) return;
    setState(() => _triggeringMeasurement = true);
    try {
      final res = await supabase
          .from('plant_settings')
          .select('device_id')
          .eq('plant_label', selectedPlant!)
          .limit(1);
      if (res.isEmpty || res[0]['device_id'] == null) {
        _showEasterEgg('No device linked to this plant.');
        return;
      }
      final deviceId = res[0]['device_id'] as String;
      await supabase
          .from('devices')
          .update({'trigger_measurement': true}).eq('device_id', deviceId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Measurement requested — updating shortly…',
              style: GoogleFonts.outfit(color: AppColors.textHigh, fontSize: 13)),
          backgroundColor: AppColors.surface2,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.border)),
          duration: const Duration(seconds: 3),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to request measurement: $e',
              style: GoogleFonts.outfit(color: AppColors.textHigh, fontSize: 13)),
          backgroundColor: AppColors.high,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _triggeringMeasurement = false);
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
            if (plant == selectedPlant) loadLatestStatus();
            final risk = (row['risk_class'] ?? 0) as int;
            if (risk == 0 || !AppSettings.notificationsEnabled) return;
            final actions = <String>[];
            if (row['action_reduce_temp'] == true || row['action_reduce_temp'] == 1) {
              actions.add("Reduce temperature");
            }
            if (row['action_water'] == true || row['action_water'] == 1) {
              actions.add("Water the plant");
            }
            if (row['action_increase_light'] == true || row['action_increase_light'] == 1) {
              actions.add("Increase light exposure");
            }
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
    super.dispose();
  }

  Future<void> openAppSettings() async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AppSettingsPage()));
    if (!mounted) return;
    // The add-device flow pops all the way back here after a plant is created,
    // and devices can be removed in settings — so reload the plant list. Select
    // the new plant if nothing is selected, so it shows right away.
    await loadPlants();
    if (!mounted) return;
    if (selectedPlant == null && plants.isNotEmpty) {
      setState(() => selectedPlant = plants.first);
      await loadLatestStatus();
    }
  }

  Future<void> openProfileSettings() async {
    final selected = await Navigator.of(context).push<String>(
      MaterialPageRoute(
          builder: (_) => ProfileSettingsPage(plants: plants, selectedPlant: selectedPlant)),
    );
    if (!mounted || selected == null) return;
    setState(() => selectedPlant = selected);
    await loadLatestStatus();
  }

  Widget buildPlantSelector() {
    final plantValue = plants.contains(selectedPlant) ? selectedPlant : null;
    return DropdownButtonFormField<String>(
      key: ValueKey("dashboard-plant-$plantValue"),
      initialValue: plantValue,
      decoration: const InputDecoration(labelText: "Plant"),
      hint: Text("Select a plant",
          style: GoogleFonts.outfit(color: AppColors.textLow, fontSize: 14)),
      items: plants
          .map((p) => DropdownMenuItem(
                value: p,
                child: Text(p, style: GoogleFonts.outfit(color: AppColors.textMid)),
              ))
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
      bandBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: badgeColor.withAlpha(30),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: badgeColor.withAlpha(70), width: 0.5),
        ),
        child: Text(band.toUpperCase(),
            style: GoogleFonts.outfit(
                fontSize: 10,
                color: badgeColor,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6)),
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
            Text(lbl,
                style: GoogleFonts.outfit(
                    fontSize: 11, color: AppColors.textLow, letterSpacing: 0.5)),
            if (bandBadge != null) ...[const Spacer(), bandBadge],
          ]),
          const SizedBox(height: 8),
          value == null
              ? Text("—",
                  style: GoogleFonts.outfit(fontSize: 20, color: AppColors.textLow))
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(value,
                        style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textHigh)),
                    const SizedBox(width: 3),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(unit,
                          style: GoogleFonts.outfit(
                              fontSize: 12, color: AppColors.textLow)),
                    ),
                  ],
                ),
        ],
      ),
    );
  }

  static String _valueBand(double? v, double lowMax, double midMin, double midMax, double highMin) {
    if (v == null) return '';
    if (v <= lowMax) return 'low';
    if (v >= highMin) return 'high';
    return 'mid';
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
          child: Row(children: [
            Text("LAST READING",
                style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textLow,
                    letterSpacing: 1.8)),
            if (_lastReadingTime != null) ...[
              Text(": ",
                  style: GoogleFonts.outfit(
                      fontSize: 11, color: AppColors.textLow, letterSpacing: 1.8)),
              Text(_formatReadingTime(_lastReadingTime!),
                  style: GoogleFonts.outfit(
                      fontSize: 11,
                      color: AppColors.textMid,
                      fontWeight: FontWeight.w500)),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _sensorTile("SOIL", _soilPct?.toStringAsFixed(1), "%",
              Icons.water_drop_outlined, AppColors.accent,
              band: soilBand, pref: _soilPref)),
          const SizedBox(width: 10),
          Expanded(child: _sensorTile("TEMP", _tempC?.toStringAsFixed(1), "°C",
              Icons.thermostat_outlined, AppColors.high,
              band: tempBand, pref: _tempPref)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _sensorTile("HUMIDITY", _humidityPct?.toStringAsFixed(1), "%",
              Icons.water_outlined, const Color(0xFF60A5FA),
              band: humidityBand, pref: _humidityPref)),
          const SizedBox(width: 10),
          Expanded(child: _sensorTile("LIGHT", _lightPct?.toStringAsFixed(1), "%",
              Icons.light_mode_outlined, const Color(0xFFFBBF24),
              band: lightBand, pref: _lightPref)),
        ]),
      ],
    );
  }

  String _formatReadingTime(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1)  return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours   < 24) return '${diff.inHours}h ago';
    if (diff.inDays    < 7)  return '${diff.inDays}d ago';
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${t.day}/${t.month} ${pad(t.hour)}:${pad(t.minute)}';
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
    final displayRec =
        noPlant ? "Select a plant to see recommendations" : _recommendationText;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: displayColor.withValues(alpha: 0.4), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            GestureDetector(
              onLongPress: _onStatusDotLongPress,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: displayColor,
                  boxShadow: [
                    BoxShadow(
                        color: displayColor.withValues(alpha: 0.5), blurRadius: 6)
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text("STATUS: $displayLabel",
                style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: displayColor,
                    letterSpacing: 0.5)),
          ]),
          const SizedBox(height: 16),
          Container(height: 1, color: AppColors.border),
          const SizedBox(height: 14),
          Text("RECOMMENDATION",
              style: GoogleFonts.outfit(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textLow,
                  letterSpacing: 1.5)),
          const SizedBox(height: 8),
          Text(displayRec,
              style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: isHealthy ? AppColors.accent : AppColors.textMid)),
          if (!noPlant && _predictions.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(height: 1, color: AppColors.border),
            const SizedBox(height: 14),
            Text("PREDICTIONS",
                style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textLow,
                    letterSpacing: 1.5)),
            const SizedBox(height: 10),
            ..._predictions.entries.map((e) {
              final timeStr = _fmtMinutes(e.value);
              final urgent = e.value < 60;
              final color = urgent ? AppColors.moderate : AppColors.textMid;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Icon(Icons.schedule, size: 14, color: color),
                  const SizedBox(width: 8),
                  Text("${_predLabel(e.key)}: ",
                      style: GoogleFonts.outfit(fontSize: 13, color: AppColors.textLow)),
                  Text(timeStr,
                      style: GoogleFonts.outfit(
                          fontSize: 13, fontWeight: FontWeight.w600, color: color)),
                ]),
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
            GestureDetector(onTap: _onIconTap, child: const MiniPlantIcon()),
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
            IconButton(
                tooltip: "Plant Preferences",
                onPressed: openProfileSettings,
                icon: const Icon(Icons.tune)),
            IconButton(
                tooltip: "App Settings",
                onPressed: openAppSettings,
                icon: const Icon(Icons.settings)),
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
          const Positioned.fill(child: CustomPaint(painter: GridPainter())),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: isWide ? 1100.0 : double.infinity),
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: AppColors.accent))
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
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.surface2,
                                  foregroundColor: AppColors.accent,
                                  side: const BorderSide(color: AppColors.border),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: _triggeringMeasurement ? null : _triggerMeasurement,
                                icon: _triggeringMeasurement
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: AppColors.accent),
                                      )
                                    : const Icon(Icons.sensors, size: 16),
                                label: Text(
                                  _triggeringMeasurement
                                      ? "Requesting…"
                                      : "Get Live Measurement",
                                  style: GoogleFonts.outfit(fontWeight: FontWeight.w500),
                                ),
                              ),
                              const SizedBox(height: 10),
                              OutlinedButton.icon(
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => DataPage(
                                        plants: plants, selectedPlant: selectedPlant),
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
