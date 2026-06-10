import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
// Re-exports flutter_blue_plus and adds a WinRT backend on Windows.
import 'package:flutter_blue_plus_windows/flutter_blue_plus_windows.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wifi_scan/wifi_scan.dart';

import '../core/app_colors.dart';
import '../services/ble_constants.dart';
import '../widgets/provisioning_widgets.dart';
import 'plant_setup_screen.dart';
import '../secrets.dart';

const Duration _kPollInterval = Duration(seconds: 2);
const int _kRegistrationTimeout = 90;

SupabaseClient get _db => Supabase.instance.client;

enum _ProvStep { connecting, form, sending, waiting, error }

/// Platform-neutral WiFi network entry; [level] is signal strength in dBm.
class _WifiNetwork {
  final String ssid;
  final int level;
  const _WifiNetwork(this.ssid, this.level);
}

class ProvisioningScreen extends StatefulWidget {
  final BluetoothDevice device;
  const ProvisioningScreen({super.key, required this.device});

  @override
  State<ProvisioningScreen> createState() => _ProvisioningScreenState();
}

class _ProvisioningScreenState extends State<ProvisioningScreen> {
  _ProvStep _step = _ProvStep.connecting;
  String _statusMsg = 'Connecting…';

  final _ssidCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscurePass = true;
  bool _formBusy = false;

  List<_WifiNetwork> _networks = [];
  bool _scanningWifi = false;
  String? _selectedSsid;

  Timer? _pollTimer;
  int _pollSeconds = 0;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _ssidCtrl.dispose();
    _passCtrl.dispose();
    widget.device.disconnect();
    super.dispose();
  }

  Future<void> _scanWifi() async {
    setState(() => _scanningWifi = true);
    try {
      final results = Platform.isWindows
          ? await _scanWifiWindows()
          : await _scanWifiAndroid();
      final seen = <String>{};
      final unique = results
          .where((n) => n.ssid.isNotEmpty && seen.add(n.ssid))
          .toList()
        ..sort((a, b) => b.level.compareTo(a.level));
      if (mounted) setState(() => _networks = unique);
    } catch (_) {
      // user can still type manually
    } finally {
      if (mounted) setState(() => _scanningWifi = false);
    }
  }

  Future<List<_WifiNetwork>> _scanWifiAndroid() async {
    await Permission.locationWhenInUse.request();
    final can = await WiFiScan.instance.canStartScan(askPermissions: true);
    if (can == CanStartScan.yes) await WiFiScan.instance.startScan();
    final results = await WiFiScan.instance.getScannedResults();
    return results.map((n) => _WifiNetwork(n.ssid, n.level)).toList();
  }

  /// wifi_scan has no Windows support, so parse `netsh wlan show networks`.
  Future<List<_WifiNetwork>> _scanWifiWindows() async {
    final res = await Process.run(
      'netsh',
      ['wlan', 'show', 'networks', 'mode=bssid'],
      stdoutEncoding: const SystemEncoding(),
    );
    if (res.exitCode != 0) return [];

    final networks = <_WifiNetwork>[];
    String? ssid;
    for (final raw in const LineSplitter().convert(res.stdout as String)) {
      final line = raw.trim();
      // Locale-independent enough: "SSID 1 : name" / "Signal : 87%".
      final ssidMatch = RegExp(r'^SSID\s+\d+\s*:\s*(.*)$').firstMatch(line);
      if (ssidMatch != null) {
        ssid = ssidMatch.group(1)!.trim();
        continue;
      }
      final signalMatch = RegExp(r':\s*(\d+)%$').firstMatch(line);
      if (signalMatch != null && ssid != null && ssid.isNotEmpty) {
        final percent = int.parse(signalMatch.group(1)!);
        // Approximate netsh quality % as dBm to match Android's scale.
        networks.add(_WifiNetwork(ssid, (percent ~/ 2) - 100));
        ssid = null;
      }
    }
    return networks;
  }

  Future<void> _connect() async {
    try {
      await widget.device.connect(timeout: const Duration(seconds: 10));
      if (!mounted) return;
      setState(() {
        _step = _ProvStep.form;
        _statusMsg = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _ProvStep.error;
        _statusMsg = 'Failed to connect: $e';
      });
    }
  }

  Future<void> _provision() async {
    final ssid = _ssidCtrl.text.trim();
    if (ssid.isEmpty) {
      _showSnack('Please enter a WiFi network name.');
      return;
    }
    setState(() {
      _formBusy = true;
      _step = _ProvStep.sending;
      _statusMsg = 'Discovering BLE services…';
    });

    try {
      final services = await widget.device.discoverServices();
      final service = services.firstWhere(
        (s) => s.serviceUuid.toString().toLowerCase() == kProvisionServiceUuid,
        orElse: () => throw 'Provisioning service not found on device.',
      );

      BluetoothCharacteristic findChar(String uuid) =>
          service.characteristics.firstWhere(
            (c) => c.characteristicUuid.toString().toLowerCase() == uuid,
            orElse: () => throw 'Characteristic $uuid not found.',
          );

      setState(() => _statusMsg = 'Reading device ID…');
      final rawId = await findChar(kDeviceIdCharUuid).read();
      final deviceId = utf8.decode(rawId).trim();
      if (deviceId.isEmpty) throw 'Device returned an empty device ID.';

      setState(() => _statusMsg = 'Sending WiFi credentials and configuration…');
      await findChar(kSsidCharUuid).write(utf8.encode(ssid), withoutResponse: false);
      await findChar(kPasswordCharUuid).write(utf8.encode(_passCtrl.text), withoutResponse: false);
      await findChar(kApiKeyCharUuid).write(utf8.encode(supabaseAnonKey), withoutResponse: false);
      await findChar(kSupabaseUrlCharUuid).write(utf8.encode(supabaseUrl), withoutResponse: false);

      setState(() {
        _step = _ProvStep.waiting;
        _statusMsg = 'Waiting for device to connect to WiFi…';
        _pollSeconds = 0;
      });

      await widget.device.disconnect();
      _startPolling(deviceId);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _step = _ProvStep.error;
        _statusMsg = 'Provisioning failed: $e';
        _formBusy = false;
      });
    }
  }

  void _startPolling(String deviceId) {
    _pollTimer = Timer.periodic(_kPollInterval, (t) async {
      _pollSeconds += _kPollInterval.inSeconds;

      if (_pollSeconds >= _kRegistrationTimeout) {
        t.cancel();
        if (mounted) {
          setState(() {
            _step = _ProvStep.error;
            _statusMsg =
                'Timed out waiting for device registration.\nCheck the WiFi credentials and try again.';
          });
        }
        return;
      }

      try {
        final res = await _db
            .from('devices')
            .select('device_id')
            .eq('device_id', deviceId)
            .limit(1);
        if (res.isNotEmpty) {
          t.cancel();
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => PlantSetupScreen(deviceId: deviceId)),
          );
          return;
        }
      } catch (_) {}

      if (mounted) {
        setState(() => _statusMsg =
            'Waiting for device to register… ($_pollSeconds s / $_kRegistrationTimeout s)');
      }
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: provTs(13, color: AppColors.textHigh)),
      backgroundColor: AppColors.surface2,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: provAppBar('Provision Device'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: switch (_step) {
            _ProvStep.connecting => _buildSpinner('Connecting to device…'),
            _ProvStep.form      => _buildForm(),
            _ProvStep.sending   => _buildSpinner(_statusMsg),
            _ProvStep.waiting   => _buildSpinner(_statusMsg),
            _ProvStep.error     => _buildError(_statusMsg),
          },
        ),
      ),
    );
  }

  Widget _buildSpinner(String msg) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.accent),
            const SizedBox(height: 20),
            Text(msg, textAlign: TextAlign.center, style: provTs(14)),
          ],
        ),
      );

  Widget _buildForm() => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProvSectionHeader(
              icon: Icons.wifi,
              title: 'Select WiFi network',
              subtitle: 'These credentials will be sent to your ESP32 device over BLE.',
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _networks.isEmpty
                      ? ProvOutlineField(
                          controller: _ssidCtrl,
                          label: 'WiFi Network (SSID)',
                          hint: 'My Home WiFi',
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              dropdownColor: AppColors.surface,
                              hint: Text('Select a network',
                                  style: provTs(13, color: AppColors.textLow)),
                              value: _selectedSsid,
                              items: _networks.map((n) {
                                final bars = n.level >= -60 ? 3 : n.level >= -80 ? 2 : 1;
                                final icon = bars == 3
                                    ? Icons.signal_wifi_4_bar
                                    : bars == 2
                                        ? Icons.network_wifi_2_bar
                                        : Icons.signal_wifi_0_bar;
                                return DropdownMenuItem(
                                  value: n.ssid,
                                  child: Row(
                                    children: [
                                      Icon(icon, size: 16, color: AppColors.textLow),
                                      const SizedBox(width: 10),
                                      Expanded(
                                          child: Text(n.ssid,
                                              style: provTs(14),
                                              overflow: TextOverflow.ellipsis)),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: (v) => setState(() {
                                _selectedSsid = v;
                                _ssidCtrl.text = v ?? '';
                              }),
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 54,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textMid,
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    onPressed: _scanningWifi ? null : _scanWifi,
                    child: _scanningWifi
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                          )
                        : const Icon(Icons.wifi_find, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _networks.isEmpty
                  ? 'Tap the scan button to find nearby networks.'
                  : '${_networks.length} networks found. Tap scan to refresh.',
              style: provTs(12, color: AppColors.textLow),
            ),
            const SizedBox(height: 16),
            ProvPasswordField(
              controller: _passCtrl,
              obscure: _obscurePass,
              onToggle: () => setState(() => _obscurePass = !_obscurePass),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.bg,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _formBusy ? null : _provision,
                child: Text('Provision Device',
                    style: provTs(15, color: AppColors.bg, fw: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textMid,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                // Nothing has been sent to the device yet, so cancelling just
                // returns to the device list.
                onPressed: _formBusy ? null : () => Navigator.of(context).pop(),
                child: Text('Cancel',
                    style: provTs(15, color: AppColors.textMid, fw: FontWeight.w600)),
              ),
            ),
          ],
        ),
      );

  Widget _buildError(String msg) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.high, size: 48),
            const SizedBox(height: 16),
            Text(msg, textAlign: TextAlign.center, style: provTs(14)),
            const SizedBox(height: 24),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textMid,
                side: const BorderSide(color: AppColors.border),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Go Back'),
            ),
          ],
        ),
      );
}
