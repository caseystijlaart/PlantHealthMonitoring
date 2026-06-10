import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// Re-exports flutter_blue_plus and adds a WinRT backend on Windows.
import 'package:flutter_blue_plus_windows/flutter_blue_plus_windows.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/app_colors.dart';
import '../services/ble_constants.dart';
import '../widgets/provisioning_widgets.dart';
import 'provisioning_screen.dart';

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

  static bool get _bleSupported =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    if (_bleSupported) {
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
    if (_bleSupported) FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() {
      _results.clear();
      _error = null;
    });

    // Runtime BLE permissions are an Android concept; Windows has none.
    if (defaultTargetPlatform == TargetPlatform.android) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      if (statuses.values.any((s) => s == PermissionStatus.permanentlyDenied)) {
        await openAppSettings();
        return;
      }
      if (statuses.values.any((s) => s == PermissionStatus.denied)) {
        setState(() => _error = 'Bluetooth permission denied. Please allow it when prompted.');
        return;
      }
    }

    // The Windows backend emits unknown/off first while the WinRT radio
    // state is still being queried, so wait for "on" instead of sampling
    // the first value.
    try {
      await FlutterBluePlus.adapterState
          .firstWhere((s) => s == BluetoothAdapterState.on)
          .timeout(const Duration(seconds: 5));
    } on TimeoutException {
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

  Future<void> _cancelScan() async {
    await FlutterBluePlus.stopScan();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancelScan();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: provAppBar('Add Device'),
        body: !_bleSupported ? _unsupportedBody() : _scanBody(),
      ),
    );
  }

  Widget _unsupportedBody() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bluetooth_disabled, size: 48, color: AppColors.textLow),
              const SizedBox(height: 16),
              Text('BLE provisioning is only available on Android and Windows.',
                  textAlign: TextAlign.center, style: provTs(15)),
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
                  style: provTs(13, color: AppColors.textLow),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  provErrorBox(_error!),
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
                          const CircularProgressIndicator(color: AppColors.accent)
                        else
                          const Icon(Icons.bluetooth_searching, size: 48, color: AppColors.textLow),
                        const SizedBox(height: 16),
                        Text(
                          _isScanning ? 'Scanning for devices…' : 'No devices found.',
                          style: provTs(14, color: AppColors.textLow),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _results.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final r = _results[i];
                      final name = r.device.platformName.isNotEmpty
                          ? r.device.platformName
                          : 'PHM Device (${r.device.remoteId.str.substring(0, 8)})';
                      return ProvDeviceTile(
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
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textMid,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _isScanning ? null : _startScan,
                    icon: _isScanning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    label: Text(_isScanning ? 'Scanning…' : 'Scan Again', style: provTs(14)),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.high,
                      side: const BorderSide(color: AppColors.high),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _cancelScan,
                    child: Text('Cancel', style: provTs(14, color: AppColors.high)),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}
