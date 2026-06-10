import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';

TextStyle provTs(double size,
        {Color color = AppColors.textMid, FontWeight fw = FontWeight.w400}) =>
    GoogleFonts.outfit(fontSize: size, color: color, fontWeight: fw);

AppBar provAppBar(String title) => AppBar(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      title: Text(title, style: provTs(18, color: AppColors.textHigh, fw: FontWeight.w600)),
      iconTheme: const IconThemeData(color: AppColors.textMid),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.border),
      ),
    );

Widget provErrorBox(String msg) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.high.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.high.withValues(alpha: 0.4)),
      ),
      child: Text(msg, style: provTs(13, color: AppColors.high)),
    );

class ProvSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const ProvSectionHeader(
      {super.key, required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, color: AppColors.accent, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: provTs(15, color: AppColors.textHigh, fw: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(subtitle, style: provTs(13, color: AppColors.textLow)),
              ],
            ),
          ),
        ],
      );
}

class ProvOutlineField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  const ProvOutlineField(
      {super.key, required this.controller, required this.label, this.hint});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        style: provTs(14, color: AppColors.textHigh),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: provTs(13, color: AppColors.textLow),
          hintStyle: provTs(13, color: AppColors.textLow),
          filled: true,
          fillColor: AppColors.surface,
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
      );
}

class ProvPasswordField extends StatelessWidget {
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggle;
  const ProvPasswordField(
      {super.key,
      required this.controller,
      required this.obscure,
      required this.onToggle});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        obscureText: obscure,
        style: provTs(14, color: AppColors.textHigh),
        decoration: InputDecoration(
          labelText: 'WiFi Password',
          labelStyle: provTs(13, color: AppColors.textLow),
          filled: true,
          fillColor: AppColors.surface,
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
          suffixIcon: IconButton(
            icon: Icon(
              obscure ? Icons.visibility_off : Icons.visibility,
              size: 18,
              color: AppColors.textLow,
            ),
            onPressed: onToggle,
          ),
        ),
      );
}

class ProvDeviceTile extends StatelessWidget {
  final String name;
  final int rssi;
  final VoidCallback onTap;
  const ProvDeviceTile(
      {super.key, required this.name, required this.rssi, required this.onTap});

  IconData get _signalIcon {
    if (rssi > -60) return Icons.signal_wifi_4_bar;
    if (rssi > -80) return Icons.network_wifi_2_bar;
    return Icons.signal_wifi_0_bar;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.sensors, color: AppColors.accent, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: provTs(14, color: AppColors.textHigh, fw: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text('Signal: $rssi dBm', style: provTs(12, color: AppColors.textLow)),
                  ],
                ),
              ),
              Icon(_signalIcon, color: AppColors.textLow, size: 18),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: AppColors.textLow, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
