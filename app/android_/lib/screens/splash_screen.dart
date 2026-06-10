import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/app_colors.dart';
import '../widgets/grid_painter.dart';
import '../widgets/plant_icon.dart';
import 'dashboard.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _gridCtrl;
  late final AnimationController _ringCtrl;
  late final AnimationController _iconCtrl;
  late final AnimationController _fadeCtrl;
  late final AnimationController _barCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _dotCtrl;

  late final Animation<double> _gridOpacity;
  late final Animation<double> _ring1Scale, _ring1Opacity;
  late final Animation<double> _ring2Scale, _ring2Opacity;
  late final Animation<double> _iconScale, _iconOpacity, _iconY;
  late final Animation<double> _titleOpacity, _titleY;
  late final Animation<double> _taglineOpacity;
  late final Animation<double> _pillsOpacity, _pillsY;
  late final Animation<double> _barProgress;
  late final Animation<double> _glowPulse;
  late final Animation<double> _dotScale;

  @override
  void initState() {
    super.initState();

    _gridCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2500));
    _gridOpacity = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _gridCtrl, curve: Curves.easeIn));

    _ringCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _ring1Scale = Tween<double>(begin: 0.7, end: 1.0).animate(
        CurvedAnimation(parent: _ringCtrl, curve: const Interval(0.0, 0.6, curve: Curves.easeOut)));
    _ring1Opacity = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _ringCtrl, curve: const Interval(0.0, 0.6, curve: Curves.easeOut)));
    _ring2Scale = Tween<double>(begin: 0.7, end: 1.0).animate(
        CurvedAnimation(parent: _ringCtrl, curve: const Interval(0.2, 0.8, curve: Curves.easeOut)));
    _ring2Opacity = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _ringCtrl, curve: const Interval(0.2, 0.8, curve: Curves.easeOut)));

    _iconCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _iconScale = Tween<double>(begin: 0.3, end: 1.0)
        .animate(CurvedAnimation(parent: _iconCtrl, curve: Curves.elasticOut));
    _iconOpacity = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _iconCtrl, curve: const Interval(0, 0.4)));
    _iconY = Tween<double>(begin: 16, end: 0)
        .animate(CurvedAnimation(parent: _iconCtrl, curve: Curves.easeOut));

    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _titleOpacity = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _fadeCtrl, curve: const Interval(0.0, 0.6, curve: Curves.easeOut)));
    _titleY = Tween<double>(begin: 12, end: 0).animate(
        CurvedAnimation(parent: _fadeCtrl, curve: const Interval(0.0, 0.6, curve: Curves.easeOut)));
    _taglineOpacity = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _fadeCtrl, curve: const Interval(0.25, 0.85, curve: Curves.easeOut)));
    _pillsOpacity = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _fadeCtrl, curve: const Interval(0.5, 1.0, curve: Curves.easeOut)));
    _pillsY = Tween<double>(begin: 12, end: 0).animate(
        CurvedAnimation(parent: _fadeCtrl, curve: const Interval(0.5, 1.0, curve: Curves.easeOut)));

    _barCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
    _barProgress = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _barCtrl, curve: Curves.easeInOut));

    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))
      ..repeat(reverse: true);
    _glowPulse = Tween<double>(begin: 0.9, end: 1.1)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _dotCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat();
    _dotScale = Tween<double>(begin: 1.0, end: 2.2)
        .animate(CurvedAnimation(parent: _dotCtrl, curve: Curves.easeOut));

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
    _barCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) _navigateToDashboard();
    });
  }

  void _navigateToDashboard() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const Dashboard(),
        transitionsBuilder: (_, anim, _, child) => FadeTransition(opacity: anim, child: child),
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
          AnimatedBuilder(
            animation: _gridOpacity,
            builder: (_, _) => Opacity(
              opacity: _gridOpacity.value,
              child: CustomPaint(size: size, painter: const GridPainter()),
            ),
          ),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _glowPulse,
              builder: (_, _) => Center(
                child: Transform.scale(
                  scale: _glowPulse.value,
                  child: Container(
                    width: size.width * 0.7,
                    height: size.width * 0.7,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                          colors: [Color(0x242EA05A), Colors.transparent]),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _ringCtrl,
              builder: (_, _) => Center(
                child: Stack(alignment: Alignment.center, children: [
                  Opacity(
                    opacity: _ring2Opacity.value,
                    child: Transform.scale(
                      scale: _ring2Scale.value,
                      child: Container(
                        width: size.width * 0.72,
                        height: size.width * 0.72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0x124ADE80), width: 1),
                        ),
                      ),
                    ),
                  ),
                  Opacity(
                    opacity: _ring1Opacity.value,
                    child: Transform.scale(
                      scale: _ring1Scale.value,
                      child: Container(
                        width: size.width * 0.52,
                        height: size.width * 0.52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0x264ADE80), width: 1),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          Positioned(
            top: 56,
            right: 28,
            child: AnimatedBuilder(
              animation: _dotCtrl,
              builder: (_, _) => Stack(alignment: Alignment.center, children: [
                Opacity(
                  opacity: 1 - _dotCtrl.value,
                  child: Transform.scale(
                    scale: _dotScale.value,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle, color: Color(0x554ADE80)),
                    ),
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: AppColors.accent),
                ),
              ]),
            ),
          ),
          Positioned.fill(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedBuilder(
                  animation: _iconCtrl,
                  builder: (_, _) => Opacity(
                    opacity: _iconOpacity.value,
                    child: Transform.translate(
                      offset: Offset(0, _iconY.value),
                      child: Transform.scale(
                          scale: _iconScale.value, child: const PlantIconBox()),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                AnimatedBuilder(
                  animation: _fadeCtrl,
                  builder: (_, _) => Opacity(
                    opacity: _titleOpacity.value,
                    child: Transform.translate(
                      offset: Offset(0, _titleY.value),
                      child: Column(children: [
                        RichText(
                          text: TextSpan(children: [
                            TextSpan(
                              text: 'Plant',
                              style: GoogleFonts.outfit(
                                  fontSize: 38,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textHigh,
                                  letterSpacing: -1.0),
                            ),
                            TextSpan(
                              text: 'Health',
                              style: GoogleFonts.outfit(
                                  fontSize: 38,
                                  fontWeight: FontWeight.w300,
                                  color: AppColors.accent,
                                  letterSpacing: -1.0),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Monitor',
                          style: GoogleFonts.outfit(
                              fontSize: 20,
                              fontWeight: FontWeight.w300,
                              color: const Color(0x99E4F5E9),
                              letterSpacing: -0.3),
                        ),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                AnimatedBuilder(
                  animation: _fadeCtrl,
                  builder: (_, _) => Opacity(
                    opacity: _taglineOpacity.value,
                    child: Text(
                      'SMART PLANT COMPANION',
                      style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: const Color(0x73B4E6C3),
                          letterSpacing: 3.2),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                AnimatedBuilder(
                  animation: _fadeCtrl,
                  builder: (_, _) => Opacity(
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
                AnimatedBuilder(
                  animation: _barCtrl,
                  builder: (_, _) => Opacity(
                    opacity: _barProgress.value > 0 ? 1 : 0,
                    child: SizedBox(
                      width: 160,
                      child: Column(children: [
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
                              letterSpacing: 0.8),
                        ),
                      ]),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
                  letterSpacing: 0.5),
            ),
          ),
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
                shape: BoxShape.circle, color: Color(0xB34ADE80)),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w400,
                color: const Color(0xB3B4E6C3),
                letterSpacing: 0.3),
          ),
        ],
      ),
    );
  }
}
