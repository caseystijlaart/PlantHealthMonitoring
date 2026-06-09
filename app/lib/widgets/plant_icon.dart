import 'package:flutter/material.dart';
import '../core/app_colors.dart';

class PlantIconBox extends StatelessWidget {
  const PlantIconBox({super.key});

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
      child: Center(child: CustomPaint(size: const Size(44, 44), painter: PlantIconPainter())),
    );
  }
}

class MiniPlantIcon extends StatelessWidget {
  const MiniPlantIcon({super.key});

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
        child: CustomPaint(size: const Size(16, 16), painter: PlantIconPainter()),
      ),
    );
  }
}

class PlantIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const accent = AppColors.accent;
    const accentFill = Color(0x384ADE80);
    const accentFill2 = Color(0x284ADE80);
    const accentFill3 = Color(0x474ADE80);

    final strokePaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final fillPaint = Paint()..style = PaintingStyle.fill;
    final cx = size.width / 2;

    canvas.drawLine(Offset(cx, size.height * 0.97), Offset(cx, size.height * 0.38), strokePaint);

    final leftLeaf = Path()
      ..moveTo(cx, size.height * 0.62)
      ..cubicTo(cx - 8, size.height * 0.58, cx - 12, size.height * 0.47, cx - 11, size.height * 0.38)
      ..cubicTo(cx - 4, size.height * 0.42, cx + 2, size.height * 0.52, cx, size.height * 0.62)
      ..close();
    fillPaint.color = accentFill;
    canvas.drawPath(leftLeaf, fillPaint);
    canvas.drawPath(leftLeaf, strokePaint..strokeWidth = 1.4);

    final rightLeaf = Path()
      ..moveTo(cx, size.height * 0.48)
      ..cubicTo(cx + 8, size.height * 0.43, cx + 12, size.height * 0.32, cx + 10, size.height * 0.23)
      ..cubicTo(cx + 3, size.height * 0.28, cx - 3, size.height * 0.38, cx, size.height * 0.48)
      ..close();
    fillPaint.color = accentFill2;
    canvas.drawPath(rightLeaf, fillPaint);
    canvas.drawPath(rightLeaf, strokePaint);

    final topLeaf = Path()
      ..moveTo(cx, size.height * 0.35)
      ..cubicTo(cx - 4, size.height * 0.25, cx - 2, size.height * 0.1, cx + 2, size.height * 0.05)
      ..cubicTo(cx + 5, size.height * 0.12, cx + 4, size.height * 0.25, cx, size.height * 0.35)
      ..close();
    fillPaint.color = accentFill3;
    canvas.drawPath(topLeaf, fillPaint);
    canvas.drawPath(topLeaf, strokePaint);

    final soilPaint = Paint()
      ..color = const Color(0xFF1E4D28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
        Offset(cx - 10, size.height * 0.97), Offset(cx + 10, size.height * 0.97), soilPaint);
    canvas.drawCircle(Offset(cx, size.height * 0.97), 1.8, Paint()..color = accent);

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
