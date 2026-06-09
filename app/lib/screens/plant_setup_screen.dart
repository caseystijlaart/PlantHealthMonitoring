import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_colors.dart';
import '../widgets/provisioning_widgets.dart';

SupabaseClient get _db => Supabase.instance.client;

class _PlantType {
  final String label;
  final String soil, temp, humidity, light;
  const _PlantType(this.label,
      {required this.soil,
      required this.temp,
      required this.humidity,
      required this.light});
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
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text('Set Up Plant',
            style: provTs(18, color: AppColors.textHigh, fw: FontWeight.w600)),
        iconTheme: const IconThemeData(color: AppColors.textMid),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: AppColors.accent, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Device is online!',
                              style: provTs(14, color: AppColors.accent, fw: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('Now give your plant a name.',
                              style: provTs(13, color: AppColors.textLow)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              ProvSectionHeader(
                icon: Icons.eco,
                title: 'Plant details',
                subtitle: 'Name your plant and pick a type to set initial care thresholds.',
              ),
              const SizedBox(height: 24),
              ProvOutlineField(
                controller: _nameCtrl,
                label: 'Plant Name',
                hint: 'e.g. "Living Room Pothos"',
              ),
              const SizedBox(height: 20),
              Text('Plant Type', style: provTs(13, color: AppColors.textLow)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<_PlantType>(
                    value: _type,
                    isExpanded: true,
                    dropdownColor: AppColors.surface,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    style: provTs(14),
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
                style: provTs(12, color: AppColors.textLow),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                provErrorBox(_error!),
              ],
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
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.bg),
                        )
                      : Text('Add Plant',
                          style: provTs(15, color: AppColors.bg, fw: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
