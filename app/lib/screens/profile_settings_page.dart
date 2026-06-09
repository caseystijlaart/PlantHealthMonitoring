import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/app_colors.dart';
import '../services/supabase_service.dart';
import '../widgets/grid_painter.dart';

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

  String humidityPref    = "mid";
  String temperaturePref = "mid";
  String soilPref        = "mid";
  String lightPref       = "mid";

  @override
  void initState() {
    super.initState();
    // Always reload from the database so a plant removed/added elsewhere isn't
    // stale here (the passed-in list is just a snapshot).
    loadPlants();
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
              border: Border.all(color: color.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 4))
              ],
            ),
            child: Text(message,
                style: GoogleFonts.outfit(
                    color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 2), entry.remove);
  }

  String normalize(String? v) => switch (v) {
        "pLow" => "low",
        "pMid" => "mid",
        "pHigh" => "high",
        _ => "mid",
      };

  String toDbValue(String v) => switch (v) {
        "low" => "pLow",
        "mid" => "pMid",
        "high" => "pHigh",
        _ => "pMid",
      };

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
      humidityPref    = normalize(row['humidity_preference']);
      temperaturePref = normalize(row['temperature_preference']);
      soilPref        = normalize(row['soil_preference']);
      lightPref       = normalize(row['light_preference']);
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
            'humidity_preference':    toDbValue(humidityPref),
            'temperature_preference': toDbValue(temperaturePref),
            'soil_preference':        toDbValue(soilPref),
            'light_preference':       toDbValue(lightPref),
            'version':                newVersion,
          })
          .eq('plant_label', selectedPlant!.trim())
          .select();
      if (!mounted) return;
      if (response.isEmpty) {
        showTopMessage("Nothing updated. Check plant selection.", AppColors.moderate);
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
        loadPlantSettings();
      },
    );
  }

  static const _prefRanges = {
    "Humidity":      {"low": "≤ 45%",   "mid": "50 – 70%",   "high": "≥ 75%"},
    "Temperature":   {"low": "≤ 16 °C", "mid": "18 – 26 °C", "high": "≥ 28 °C"},
    "Soil Moisture": {"low": "≤ 28%",   "mid": "33 – 55%",   "high": "≥ 60%"},
    "Light":         {"low": "≤ 20%",   "mid": "25 – 65%",   "high": "≥ 70%"},
  };

  Widget buildPreferenceDropdown(String lbl, String value, ValueChanged<String?> onChanged) {
    final ranges = _prefRanges[lbl];
    final band = ["low", "mid", "high"].contains(value) ? value : "mid";

    Widget item(String label, String b) {
      final range = ranges?[b];
      return Row(children: [
        Text(label, style: GoogleFonts.outfit(color: AppColors.textMid)),
        if (range != null) ...[
          const SizedBox(width: 8),
          Text(range, style: GoogleFonts.outfit(fontSize: 12, color: AppColors.textLow)),
        ],
      ]);
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
            tooltip: "Back", onPressed: goBack, icon: const Icon(CupertinoIcons.back)),
        title: const Text("Plant Preferences"),
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: AppColors.border)),
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
                    buildPlantSelector(),
                    const SizedBox(height: 20),
                    Text("PREFERENCES",
                        style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textLow,
                            letterSpacing: 1.8)),
                    const SizedBox(height: 12),
                    if (isWide)
                      Row(children: [
                        Expanded(
                            child: buildPreferenceDropdown("Humidity", humidityPref,
                                (v) { if (v != null) setState(() => humidityPref = v); })),
                        const SizedBox(width: 12),
                        Expanded(
                            child: buildPreferenceDropdown("Temperature", temperaturePref,
                                (v) { if (v != null) setState(() => temperaturePref = v); })),
                      ])
                    else ...[
                      buildPreferenceDropdown("Humidity", humidityPref,
                          (v) { if (v != null) setState(() => humidityPref = v); }),
                      const SizedBox(height: 12),
                      buildPreferenceDropdown("Temperature", temperaturePref,
                          (v) { if (v != null) setState(() => temperaturePref = v); }),
                    ],
                    const SizedBox(height: 12),
                    if (isWide)
                      Row(children: [
                        Expanded(
                            child: buildPreferenceDropdown("Soil Moisture", soilPref,
                                (v) { if (v != null) setState(() => soilPref = v); })),
                        const SizedBox(width: 12),
                        Expanded(
                            child: buildPreferenceDropdown("Light", lightPref,
                                (v) { if (v != null) setState(() => lightPref = v); })),
                      ])
                    else ...[
                      buildPreferenceDropdown("Soil Moisture", soilPref,
                          (v) { if (v != null) setState(() => soilPref = v); }),
                      const SizedBox(height: 12),
                      buildPreferenceDropdown("Light", lightPref,
                          (v) { if (v != null) setState(() => lightPref = v); }),
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
