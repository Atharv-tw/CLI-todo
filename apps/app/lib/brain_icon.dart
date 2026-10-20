import 'package:flutter/material.dart';

/// A human brain, drawn: Material's icon set has none. Sized and coloured
/// like an [Icon].
class BrainIcon extends StatelessWidget {
  const BrainIcon({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _BrainPainter(color ?? IconTheme.of(context).color ?? Colors.white)),
  );
}

class _BrainPainter extends CustomPainter {
  _BrainPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // The left hemisphere's outline, lobe by lobe; the right one mirrors it.
    final half = Path()
      ..moveTo(12, 4.6)
      ..cubicTo(10.6, 3.4, 8.2, 3.6, 7.3, 5.4)
      ..cubicTo(5.3, 5.3, 3.9, 7.0, 4.4, 8.9)
      ..cubicTo(2.8, 9.8, 2.7, 12.1, 4.0, 13.1)
      ..cubicTo(3.4, 15.0, 4.6, 16.8, 6.4, 16.9)
      ..cubicTo(6.8, 18.9, 9.0, 20.0, 10.8, 19.0)
      ..cubicTo(11.2, 19.6, 11.6, 19.9, 12, 19.9);
    // Folds.
    final folds = Path()
      ..moveTo(8.0, 8.6)
      ..cubicTo(9.0, 8.2, 9.9, 8.8, 10.1, 9.7)
      ..moveTo(6.4, 12.1)
      ..cubicTo(7.5, 11.6, 8.6, 12.2, 8.8, 13.2)
      ..moveTo(8.4, 15.7)
      ..cubicTo(9.3, 15.3, 10.2, 15.8, 10.4, 16.6);

    for (final mirror in [false, true]) {
      canvas.save();
      if (mirror) {
        canvas.translate(24, 0);
        canvas.scale(-1, 1);
      }
      canvas.drawPath(half, pen);
      canvas.drawPath(folds, pen);
      canvas.restore();
    }
    // The fissure between the hemispheres.
    canvas.drawLine(const Offset(12, 4.6), const Offset(12, 19.9), pen);
  }

  @override
  bool shouldRepaint(_BrainPainter old) => old.color != color;
}
