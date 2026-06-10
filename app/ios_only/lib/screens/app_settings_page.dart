import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/app_colors.dart';
import '../services/app_settings.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../widgets/grid_painter.dart';
import 'dev_dash.dart';

class AppSettingsPage extends StatefulWidget {
  const AppSettingsPage({super.key});

  @override
  State<AppSettingsPage> createState() => _AppSettingsPageState();
}

class _AppSettingsPageState extends State<AppSettingsPage> {
  bool _notifications = AppSettings.notificationsEnabled;
  bool _dailyReport = AppSettings.dailyReportEnabled;
  int _reportHour = AppSettings.dailyReportHour;
  int _reportMinute = const [0, 15, 30, 45].reduce(
    (a, b) =>
        (AppSettings.dailyReportMinute - a).abs() <=
            (AppSettings.dailyReportMinute - b).abs()
        ? a
        : b,
  );

  List<String> _plants = [];
  List<Map<String, dynamic>> _devices = [];
  bool _devicesLoading = true;

  /// Device IDs whose tile is expanded to reveal the full UUID.
  final Set<String> _expandedDevices = {};

  @override
  void initState() {
    super.initState();
    _loadPlants();
    _loadDevices();
  }

  Future<void> _loadPlants() async {
    final res = await supabase.from('plant_settings').select('plant_label');
    if (!mounted) return;
    setState(
      () => _plants = (res as List)
          .map((e) => e['plant_label'] as String)
          .toList(),
    );
  }

  Future<void> _loadDevices() async {
    setState(() => _devicesLoading = true);
    // Two separate queries merged client-side: an embedded select
    // (devices(...)) needs a foreign key in PostgREST's schema cache, which
    // breaks when the FK migration step was skipped or the cache is stale.
    final settings = await supabase
        .from('plant_settings')
        .select('plant_label, device_id')
        .not('device_id', 'is', null);
    if (!mounted) return;

    final deviceIds = (settings as List)
        .map((e) => e['device_id'] as String?)
        .whereType<String>()
        .toList();
    final deviceRows = deviceIds.isEmpty
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(
            await supabase
                .from('devices')
                .select('device_id, last_seen, device_name')
                .inFilter('device_id', deviceIds),
          );
    if (!mounted) return;
    final byId = {for (final d in deviceRows) d['device_id'] as String: d};

    final cutoff = DateTime.now().toUtc().subtract(const Duration(hours: 4));
    final results = settings.cast<Map<String, dynamic>>().map((d) {
      final deviceRow = byId[d['device_id']];
      final lastSeenStr = deviceRow?['last_seen'] as String?;
      bool online = false;
      if (lastSeenStr != null) {
        final lastSeen = DateTime.tryParse(lastSeenStr);
        online = lastSeen != null && lastSeen.isAfter(cutoff);
      }
      return {...d, 'online': online, 'devices': deviceRow};
    }).toList();

    if (!mounted) return;
    setState(() {
      _devices = results;
      _devicesLoading = false;
    });
  }

  Future<void> _deleteDevice(Map<String, dynamic> device) async {
    final deviceId = device['device_id'] as String?;
    final plantLabel = device['plant_label'] as String? ?? 'this plant';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: Text(
          'Remove device?',
          style: GoogleFonts.outfit(
            color: AppColors.textHigh,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          'This will remove "$plantLabel" and reset the ESP32 back to provisioning mode. The device will need to be paired again.',
          style: GoogleFonts.outfit(color: AppColors.textMid, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: GoogleFonts.outfit(color: AppColors.textLow),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Remove',
              style: GoogleFonts.outfit(
                color: const Color(0xFFF87171),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (deviceId == null) return;

    try {
      await supabase
          .from('devices')
          .update({'trigger_reset': true})
          .eq('device_id', deviceId);
      await supabase.from('plant_settings').delete().eq('device_id', deviceId);
      await _loadDevices();
      await _loadPlants();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to remove device: $e',
            style: GoogleFonts.outfit(color: AppColors.textHigh),
          ),
          backgroundColor: const Color(0xFFF87171),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _applyDailyReport(bool enabled) async {
    setState(() => _dailyReport = enabled);
    await AppSettings.setDailyReport(
      enabled: enabled,
      hour: _reportHour,
      minute: _reportMinute,
    );
    if (enabled) {
      await NotificationService.scheduleDailyReport(
        plants: _plants,
        hour: _reportHour,
        minute: _reportMinute,
      );
    } else {
      await NotificationService.cancelDailyReport();
    }
  }

  Future<void> _updateTime({int? hour, int? minute}) async {
    setState(() {
      if (hour != null) _reportHour = hour;
      if (minute != null) _reportMinute = minute;
    });
    await AppSettings.setDailyReport(
      enabled: _dailyReport,
      hour: _reportHour,
      minute: _reportMinute,
    );
    if (_dailyReport) {
      await NotificationService.scheduleDailyReport(
        plants: _plants,
        hour: _reportHour,
        minute: _reportMinute,
      );
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
        leading: IconButton(
          tooltip: "Back",
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(CupertinoIcons.back),
        ),
        title: const Text("App Settings"),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: GridPainter())),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      "DEVICES",
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textLow,
                        letterSpacing: 1.8,
                      ),
                    ),
                    const SizedBox(height: 12),

                    _settingsTile(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline,
                              size: 18,
                              color: AppColors.textLow,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'New devices are added from the Android app. Devices provisioned there appear here automatically.',
                                style: GoogleFonts.outfit(
                                  color: AppColors.textLow,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    if (_devicesLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.accent,
                            strokeWidth: 2,
                          ),
                        ),
                      )
                    else if (_devices.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No connected devices.',
                          style: GoogleFonts.outfit(
                            color: AppColors.textLow,
                            fontSize: 13,
                          ),
                        ),
                      )
                    else
                      ...(_devices.map((device) {
                        final online = device['online'] as bool? ?? false;
                        final label =
                            device['plant_label'] as String? ?? 'Unknown';
                        final id = device['device_id'] as String? ?? '';
                        final deviceName =
                            (device['devices']
                                    as Map<String, dynamic>?)?['device_name']
                                as String?;
                        final displayName =
                            (deviceName != null && deviceName.isNotEmpty)
                            ? deviceName
                            : (id.length >= 8
                                  ? '${id.substring(0, 8)}…'
                                  : id);
                        final expanded = _expandedDevices.contains(id);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _settingsTile(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => setState(() {
                                expanded
                                    ? _expandedDevices.remove(id)
                                    : _expandedDevices.add(id);
                              }),
                              child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 0,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: online
                                          ? AppColors.accent
                                          : AppColors.textLow,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          label,
                                          style: GoogleFonts.outfit(
                                            color: online
                                                ? AppColors.textHigh
                                                : AppColors.textMid,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          online
                                              ? 'Online · $displayName'
                                              : 'Offline · $displayName',
                                          style: GoogleFonts.outfit(
                                            color: online
                                                ? AppColors.accent
                                                : AppColors.textLow,
                                            fontSize: 11,
                                          ),
                                        ),
                                        if (expanded)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              top: 6,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'DEVICE ID',
                                                  style: GoogleFonts.outfit(
                                                    color: AppColors.textLow,
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w600,
                                                    letterSpacing: 1.2,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  id,
                                                  style: GoogleFonts.outfit(
                                                    color: AppColors.textLow,
                                                    fontSize: 10,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Remove device',
                                    onPressed: () => _deleteDevice(device),
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 18,
                                      color: Color(0xFFF87171),
                                    ),
                                  ),
                                ],
                              ),
                              ),
                            ),
                          ),
                        );
                      })),

                    const SizedBox(height: 20),

                    Text(
                      "NOTIFICATIONS",
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textLow,
                        letterSpacing: 1.8,
                      ),
                    ),
                    const SizedBox(height: 12),

                    _settingsTile(
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          "Plant alerts",
                          style: GoogleFonts.outfit(
                            color: AppColors.textHigh,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Text(
                          "Get notified when your plant needs watering, light adjustment, or temperature changes.",
                          style: GoogleFonts.outfit(
                            color: AppColors.textLow,
                            fontSize: 12,
                          ),
                        ),
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

                    _settingsTile(
                      child: Column(
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              "Daily plant report",
                              style: GoogleFonts.outfit(
                                color: AppColors.textHigh,
                                fontSize: 15,
                              ),
                            ),
                            subtitle: Text(
                              "Receive a daily notification with the status of each plant.",
                              style: GoogleFonts.outfit(
                                color: AppColors.textLow,
                                fontSize: 12,
                              ),
                            ),
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
                                  Text(
                                    "Report time",
                                    style: GoogleFonts.outfit(
                                      color: AppColors.textMid,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const Spacer(),
                                  DropdownButton<int>(
                                    value: _reportHour,
                                    dropdownColor: AppColors.surface2,
                                    style: GoogleFonts.outfit(
                                      color: AppColors.accent,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    underline: const SizedBox.shrink(),
                                    items: List.generate(
                                      24,
                                      (h) => DropdownMenuItem(
                                        value: h,
                                        child: Text(
                                          h.toString().padLeft(2, '0'),
                                        ),
                                      ),
                                    ),
                                    onChanged: (h) => _updateTime(hour: h),
                                  ),
                                  Text(
                                    ":",
                                    style: GoogleFonts.outfit(
                                      color: AppColors.textMid,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  DropdownButton<int>(
                                    value: _reportMinute,
                                    dropdownColor: AppColors.surface2,
                                    style: GoogleFonts.outfit(
                                      color: AppColors.accent,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    underline: const SizedBox.shrink(),
                                    items: [0, 15, 30, 45]
                                        .map(
                                          (m) => DropdownMenuItem(
                                            value: m,
                                            child: Text(
                                              m.toString().padLeft(2, '0'),
                                            ),
                                          ),
                                        )
                                        .toList(),
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

                    // 👇 NEW SECTION
                    Text(
                      "DEVELOPER PAGE",
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textLow,
                        letterSpacing: 1.8,
                      ),
                    ),

                    const SizedBox(height: 12),

                    _settingsTile(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const DevDash()),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.developer_mode,
                                size: 18,
                                color: AppColors.accent,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Open Developer Page',
                                  style: GoogleFonts.outfit(
                                    color: AppColors.textHigh,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: AppColors.textLow,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    Text(
                      "Plant alerts fire automatically when a new reading with moderate or high risk is detected. The daily report sends one notification per day at your chosen time with the status of every plant.",
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: AppColors.textLow,
                      ),
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
