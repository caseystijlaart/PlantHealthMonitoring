import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── BLE UUIDs — must match ESP32 firmware ────────────────────────────────────
//
// Service UUID identifies the PHM provisioning service type — it is the same
// on every device and is how the app finds PHM devices during scanning.
// Characteristic UUIDs are like field names; also the same on every device.
//
// The device_id UUID is *generated on the ESP32* (hardware RNG) and exposed
// as a READ characteristic.  The app reads it; it never writes it.
//
//   Service:   4fafc201-1fb5-459e-8fcc-c5c9c331914b
//   SSID:      beb5483e-36e1-4688-b7f5-ea07361b26a8  (WRITE)
//   Password:  beb5483e-36e1-4688-b7f5-ea07361b26a9  (WRITE, no read)
//   Device ID: beb5483e-36e1-4688-b7f5-ea07361b26aa  (READ)
const String kProvisionServiceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
const String kSsidCharUuid         = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';
const String kPasswordCharUuid     = 'beb5483e-36e1-4688-b7f5-ea07361b26a9';
const String kDeviceIdCharUuid     = 'beb5483e-36e1-4688-b7f5-ea07361b26aa';

// Required Supabase migrations — see supabase/migrations.sql in the repo root.

const Duration _kPollInterval       = Duration(seconds: 3);
const int      _kRegistrationTimeout = 90; // seconds

SupabaseClient get _db => Supabase.instance.client;

// App colors — keep in sync with AppColors in main.dart
const _bg       = Color(0xFF0C1A10);
const _surface  = Color(0xFF152A1C);
const _surface2 = Color(0xFF1C3526);
const _border   = Color(0xFF2A3D2E);
const _accent   = Color(0xFF4ADE80);
const _textHigh = Color(0xFFE4F5E9);
const _textMid  = Color(0xFFB4E6C3);
const _textLow  = Color(0xFF4A6B52);
const _red      = Color(0xFFF87171);

bool _bleSupported() =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.android;

TextStyle _ts(double size, {Color color = _textMid, FontWeight fw = FontWeight.w400}) =>
    GoogleFonts.outfit(fontSize: size, color: color, fontWeight: fw);

// ═══════════════════════════════════════════════════════════════════════════════
//  DEVICE SCAN SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class DeviceScanScreen extends StatefulWidget {
  const DeviceScanScreen({super.key});

  @override
  State<DeviceScanScreen> createState() => _DeviceScanScreenState();
}

class _DeviceScanScreenState extends State<DeviceScanScreen> {
  final List<ScanResult> _results = [];
  bool _isScanning = false;
  String? _error;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _isScanSub;

  @override
  void initState() {
    super.initState();
    if (_bleSupported()) {
      _isScanSub = FlutterBluePlus.isScanning.listen((v) {
        if (mounted) setState(() => _isScanning = v);
      });
      _startScan();
    }
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _isScanSub?.cancel();
    if (_bleSupported()) FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() {
      _results.clear();
      _error = null;
    });

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      setState(() => _error = 'Bluetooth is off. Please enable it and try again.');
      return;
    }

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      if (!mounted) return;
      setState(() {
        for (final r in results) {
          final idx = _results.indexWhere((x) => x.device.remoteId == r.device.remoteId);
          if (idx >= 0) {
            _results[idx] = r;
          } else {
            _results.add(r);
          }
        }
      });
    });

    try {
      await FlutterBluePlus.startScan(
        withServices: [Guid(kProvisionServiceUuid)],
        timeout: const Duration(seconds: 30),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Scan failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _appBar('Add Device'),
      body: !_bleSupported() ? _unsupportedBody() : _scanBody(),
    );
  }

  Widget _unsupportedBody() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bluetooth_disabled, size: 48, color: _textLow),
          const SizedBox(height: 16),
          Text(
            'BLE provisioning is only available on iOS and Android.',
            textAlign: TextAlign.center,
            style: _ts(15),
          ),
        ],
      ),
    ),
  );

  Widget _scanBody() => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Power on your ESP32 device and make sure it is in provisioning mode.',
              style: _ts(13, color: _textLow),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _errorBox(_error!),
            ],
          ],
        ),
      ),
      Expanded(
        child: _results.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isScanning)
                      const CircularProgressIndicator(color: _accent)
                    else
                      const Icon(Icons.bluetooth_searching, size: 48, color: _textLow),
                    const SizedBox(height: 16),
                    Text(
                      _isScanning ? 'Scanning for devices…' : 'No devices found.',
                      style: _ts(14, color: _textLow),
                    ),
                  ],
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: _results.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final r = _results[i];
                  final name = r.device.platformName.isNotEmpty
                      ? r.device.platformName
                      : 'PHM Device (${r.device.remoteId.str.substring(0, 8)})';
                  return _DeviceTile(
                    name: name,
                    rssi: r.rssi,
                    onTap: () async {
                      await FlutterBluePlus.stopScan();
                      if (!ctx.mounted) return;
                      Navigator.of(ctx).push(MaterialPageRoute(
                        builder: (_) => ProvisioningScreen(device: r.device),
                      ));
                    },
                  );
                },
              ),
      ),
      Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _textMid,
              side: const BorderSide(color: _border),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _isScanning ? null : _startScan,
            icon: _isScanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
                  )
                : const Icon(Icons.refresh, size: 18),
            label: Text(_isScanning ? 'Scanning…' : 'Scan Again', style: _ts(14)),
          ),
        ),
      ),
    ],
  );
}

class _DeviceTile extends StatelessWidget {
  final String name;
  final int rssi;
  final VoidCallback onTap;

  const _DeviceTile({required this.name, required this.rssi, required this.onTap});

  IconData get _signalIcon {
    if (rssi > -60) return Icons.signal_wifi_4_bar;
    if (rssi > -80) return Icons.network_wifi_2_bar;
    return Icons.signal_wifi_0_bar;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _accent.withOpacity(0.3)),
                ),
                child: const Icon(Icons.sensors, color: _accent, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: _ts(14, color: _textHigh, fw: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text('Signal: $rssi dBm', style: _ts(12, color: _textLow)),
                  ],
                ),
              ),
              Icon(_signalIcon, color: _textLow, size: 18),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: _textLow, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  PROVISIONING SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

enum _ProvStep { connecting, form, sending, waiting, error }

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

      // Read the device UUID generated on the ESP32 — we never write it
      setState(() => _statusMsg = 'Reading device ID…');
      final rawId = await findChar(kDeviceIdCharUuid).read();
      final deviceId = utf8.decode(rawId).trim();
      if (deviceId.isEmpty) throw 'Device returned an empty device ID.';
      debugPrint('[Prov] Device ID: $deviceId');

      // Write WiFi credentials to the device
      setState(() => _statusMsg = 'Sending WiFi credentials…');
      await findChar(kSsidCharUuid).write(utf8.encode(ssid), withoutResponse: false);
      await findChar(kPasswordCharUuid).write(utf8.encode(_passCtrl.text), withoutResponse: false);

      setState(() {
        _step = _ProvStep.waiting;
        _statusMsg = 'Device is connecting to WiFi…';
        _pollSeconds = 0;
      });

      // Disconnect BLE — the ESP32 exits provisioning mode on its own
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
            _statusMsg = 'Timed out waiting for device registration.\nCheck the WiFi credentials and try again.';
          });
        }
        return;
      }

      try {
        final res = await _db
            .from('devices')
            .select('status')
            .eq('device_id', deviceId)
            .limit(1);

        if (res.isNotEmpty && res[0]['status'] == 'active') {
          t.cancel();
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => PlantSetupScreen(deviceId: deviceId)),
          );
          return;
        }
      } catch (_) {
        // ignore transient poll errors
      }

      if (mounted) {
        setState(() => _statusMsg = 'Waiting for device to register… (${_pollSeconds}s / ${_kRegistrationTimeout}s)');
      }
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: _ts(13, color: _textHigh)),
      backgroundColor: _surface2,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _border),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _appBar('Provision Device'),
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
        const CircularProgressIndicator(color: _accent),
        const SizedBox(height: 20),
        Text(msg, textAlign: TextAlign.center, style: _ts(14)),
      ],
    ),
  );

  Widget _buildForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _SectionHeader(
        icon: Icons.wifi,
        title: 'Enter WiFi credentials',
        subtitle: 'These will be sent to your ESP32 device over BLE.',
      ),
      const SizedBox(height: 24),
      _OutlineField(controller: _ssidCtrl, label: 'WiFi Network (SSID)', hint: 'My Home WiFi'),
      const SizedBox(height: 16),
      _PasswordField(
        controller: _passCtrl,
        obscure: _obscurePass,
        onToggle: () => setState(() => _obscurePass = !_obscurePass),
      ),
      const SizedBox(height: 32),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: _bg,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _formBusy ? null : _provision,
          child: Text('Provision Device', style: _ts(15, color: _bg, fw: FontWeight.w600)),
        ),
      ),
    ],
  );

  Widget _buildError(String msg) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, color: _red, size: 48),
        const SizedBox(height: 16),
        Text(msg, textAlign: TextAlign.center, style: _ts(14)),
        const SizedBox(height: 24),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: _textMid,
            side: const BorderSide(color: _border),
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Go Back'),
        ),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
//  PLANT SETUP SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class _PlantType {
  final String label;
  final String soil, temp, humidity, light;
  const _PlantType(
    this.label, {
    required this.soil,
    required this.temp,
    required this.humidity,
    required this.light,
  });
}

const _kPlantTypes = [
  _PlantType('Pothos',    soil: 'pMid',  temp: 'pMid',  humidity: 'pMid',  light: 'pLow'),
  _PlantType('Fern',      soil: 'pHigh', temp: 'pMid',  humidity: 'pHigh', light: 'pLow'),
  _PlantType('Cactus',    soil: 'pLow',  temp: 'pHigh', humidity: 'pLow',  light: 'pHigh'),
  _PlantType('Succulent', soil: 'pLow',  temp: 'pMid',  humidity: 'pLow',  light: 'pHigh'),
  _PlantType('Tropical',  soil: 'pMid',  temp: 'pHigh', humidity: 'pHigh', light: 'pMid'),
  _PlantType('Vegetable', soil: 'pMid',  temp: 'pMid',  humidity: 'pMid',  light: 'pHigh'),
  _PlantType('Custom',    soil: 'pMid',  temp: 'pMid',  humidity: 'pMid',  light: 'pMid'),
];

class PlantSetupScreen extends StatefulWidget {
  final String deviceId;
  const PlantSetupScreen({super.key, required this.deviceId});

  @override
  State<PlantSetupScreen> createState() => _PlantSetupScreenState();
}

class _PlantSetupScreenState extends State<PlantSetupScreen> {
  final _nameCtrl = TextEditingController();
  _PlantType _type = _kPlantTypes.first;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a plant name.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await _db.from('plant_settings').insert({
        'plant_label':            name,
        'device_id':              widget.deviceId,
        'soil_preference':        _type.soil,
        'temperature_preference': _type.temp,
        'humidity_preference':    _type.humidity,
        'light_preference':       _type.light,
        'version':                1,
      });
      if (!mounted) return;
      // Pop all the way back to the dashboard, which will reload its plant list
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Failed to save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text('Set Up Plant', style: _ts(18, color: _textHigh, fw: FontWeight.w600)),
        iconTheme: const IconThemeData(color: _textMid),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Online confirmation banner
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _accent.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _accent.withOpacity(0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: _accent, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Device is online!',
                              style: _ts(14, color: _accent, fw: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('Now give your plant a name.',
                              style: _ts(13, color: _textLow)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              _SectionHeader(
                icon: Icons.eco,
                title: 'Plant details',
                subtitle: 'Name your plant and pick a type to set initial care thresholds.',
              ),
              const SizedBox(height: 24),
              _OutlineField(
                controller: _nameCtrl,
                label: 'Plant Name',
                hint: 'e.g. "Living Room Pothos"',
              ),
              const SizedBox(height: 20),
              Text('Plant Type', style: _ts(13, color: _textLow)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<_PlantType>(
                    value: _type,
                    isExpanded: true,
                    dropdownColor: _surface,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    style: _ts(14),
                    items: _kPlantTypes
                        .map((t) => DropdownMenuItem(value: t, child: Text(t.label)))
                        .toList(),
                    onChanged: (v) => setState(() => _type = v!),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'You can adjust thresholds in Plant Preferences later.',
                style: _ts(12, color: _textLow),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                _errorBox(_error!),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: _bg,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: _bg),
                        )
                      : Text('Add Plant', style: _ts(15, color: _bg, fw: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

AppBar _appBar(String title) => AppBar(
  backgroundColor: _bg,
  surfaceTintColor: Colors.transparent,
  elevation: 0,
  title: Text(title, style: _ts(18, color: _textHigh, fw: FontWeight.w600)),
  iconTheme: const IconThemeData(color: _textMid),
  bottom: PreferredSize(
    preferredSize: const Size.fromHeight(1),
    child: Container(height: 1, color: _border),
  ),
);

Widget _errorBox(String msg) => Container(
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: _red.withOpacity(0.08),
    borderRadius: BorderRadius.circular(10),
    border: Border.all(color: _red.withOpacity(0.4)),
  ),
  child: Text(msg, style: _ts(13, color: _red)),
);

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _SectionHeader({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: _accent.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _accent.withOpacity(0.3)),
        ),
        child: Icon(icon, color: _accent, size: 18),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: _ts(15, color: _textHigh, fw: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(subtitle, style: _ts(13, color: _textLow)),
          ],
        ),
      ),
    ],
  );
}

class _OutlineField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  const _OutlineField({required this.controller, required this.label, this.hint});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    style: _ts(14, color: _textHigh),
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: _ts(13, color: _textLow),
      hintStyle: _ts(13, color: _textLow),
      filled: true,
      fillColor: _surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _accent, width: 1.5),
      ),
    ),
  );
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggle;
  const _PasswordField({required this.controller, required this.obscure, required this.onToggle});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    obscureText: obscure,
    style: _ts(14, color: _textHigh),
    decoration: InputDecoration(
      labelText: 'WiFi Password',
      labelStyle: _ts(13, color: _textLow),
      filled: true,
      fillColor: _surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _accent, width: 1.5),
      ),
      suffixIcon: IconButton(
        icon: Icon(
          obscure ? Icons.visibility_off : Icons.visibility,
          size: 18,
          color: _textLow,
        ),
        onPressed: onToggle,
      ),
    ),
  );
}
