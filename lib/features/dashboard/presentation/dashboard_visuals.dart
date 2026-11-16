import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../data/dashboard_repository.dart';

/// Visual primitives for the approved image-free dashboard reference.
/// All decoration is drawn by Flutter; no school or student photos are used.
abstract final class DashboardColors {
  static const deep = Color(0xFF005451);
  static const teal = Color(0xFF008D7B);
  static const emerald = Color(0xFF069B71);
  static const ink = Color(0xFF16313A);
  static const muted = Color(0xFF60717E);
  static const pale = Color(0xFFE5F7F3);
  static const background = Color(0xFFEEF7FC);
  static const border = Color(0xFFD8E4EC);
  static const amber = Color(0xFFF1AC3E);
  static const danger = Color(0xFFD02F31);
}

class DashboardPanel extends StatelessWidget {
  const DashboardPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 15,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF172C34) : Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: dark ? const Color(0xFF314B50) : DashboardColors.border,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140C5670),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class DashboardIconTile extends StatelessWidget {
  const DashboardIconTile({
    super.key,
    required this.icon,
    this.color = DashboardColors.teal,
    this.background = DashboardColors.pale,
    this.size = 54,
  });

  final IconData icon;
  final Color color;
  final Color background;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(size * .23),
        ),
        child: Icon(icon, size: size * .53, color: color),
      );
}

/// Draws subtle curved blue-green waves like the screenshot, not a bitmap.
class DashboardWaveBackground extends StatelessWidget {
  const DashboardWaveBackground({super.key, this.mobile = false});
  final bool mobile;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(
          painter: _DashboardWavesPainter(mobile),
          child: const SizedBox.expand(),
        ),
      );
}

class _DashboardWavesPainter extends CustomPainter {
  const _DashboardWavesPainter(this.mobile);
  final bool mobile;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint();
    if (mobile) {
      paint.color = const Color(0x55CDE7F8);
      final first = Path()
        ..moveTo(0, h * .18)
        ..quadraticBezierTo(w * .23, h * .52, w * .59, h * .34)
        ..quadraticBezierTo(w * .84, h * .20, w, h * .22)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
      canvas.drawPath(first, paint);
      paint.color = const Color(0x4F9DDAD9);
      final second = Path()
        ..moveTo(0, h * .80)
        ..cubicTo(w * .37, h * .20, w * .61, h * 1.10, w, h * .29)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close();
      canvas.drawPath(second, paint);
    } else {
      paint.color = const Color(0x5ED6EAF3);
      canvas.drawPath(Path()
        ..moveTo(0, 0)
        ..quadraticBezierTo(w * .26, h * .03, w * .51, h * .29)
        ..quadraticBezierTo(w * .80, h * .10, w, h * .08)
        ..lineTo(w, 0)
        ..close(), paint);
      paint.color = const Color(0x5CC4E9F3);
      canvas.drawPath(Path()
        ..moveTo(0, h * .87)
        ..cubicTo(w * .20, h * .70, w * .39, h * 1.05, w * .61, h * .92)
        ..quadraticBezierTo(w * .85, h * .77, w, h * .85)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close(), paint);
      paint.color = const Color(0x4290DAD1);
      canvas.drawPath(Path()
        ..moveTo(0, h * .96)
        ..cubicTo(w * .30, h * .82, w * .49, h * 1.05, w, h * .94)
        ..lineTo(w, h)
        ..lineTo(0, h)
        ..close(), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DashboardWavesPainter oldDelegate) =>
      oldDelegate.mobile != mobile;
}

class DashboardDonutIndicator extends StatelessWidget {
  const DashboardDonutIndicator({
    super.key,
    required this.ratio,
    required this.label,
    this.size = 142,
  });

  final double ratio;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size,
      width: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _DonutPainter(ratio.clamp(0.0, 1.0).toDouble()),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text(label,
                style: const TextStyle(
                    color: DashboardColors.deep,
                    fontSize: 22,
                    fontWeight: FontWeight.w900)),
            const Text('Present',
                style: TextStyle(color: DashboardColors.ink, fontSize: 12)),
          ]),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter(this.ratio);
  final double ratio;

  @override
  void paint(Canvas canvas, Size size) {
    final width = math.min(size.width, size.height) * .135;
    final rect = Rect.fromLTWH(
        width / 2, width / 2, size.width - width, size.height - width);
    final track = Paint()
      ..color = const Color(0xFFD6E4E9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final progress = Paint()
      ..shader = const SweepGradient(colors: [
        Color(0xFF006E65),
        Color(0xFF00B58C),
        Color(0xFF00765C),
      ]).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.butt;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2, false, track);
    if (ratio > 0) {
      canvas.drawArc(
          rect, -math.pi / 2, math.pi * 2 * ratio, false, progress);
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.ratio != ratio;
}

/// Real Flutter chart: axes, bars, trend line, data points and month labels.
/// Uses the dashboard snapshot's actual selected-campus data.
class DashboardTrendChart extends StatelessWidget {
  const DashboardTrendChart({
    super.key,
    required this.months,
    required this.currency,
    this.height = 205,
  });

  final List<DashboardFeeMonth> months;
  final String currency;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _FeeTrendPainter(months, currency),
        ),
      );
}

class _FeeTrendPainter extends CustomPainter {
  const _FeeTrendPainter(this.months, this.currency);
  final List<DashboardFeeMonth> months;
  final String currency;

  @override
  void paint(Canvas canvas, Size size) {
    if (months.isEmpty) return;
    const left = 82.0;
    const top = 11.0;
    const bottom = 26.0;
    const right = 10.0;
    final chartW = math.max(4.0, size.width - left - right);
    final chartH = math.max(8.0, size.height - top - bottom);
    final values = months.map((m) => m.amount.toDouble()).toList();
    final maxValue = values.reduce(math.max);
    final ceiling = math.max(1, maxValue * 1.18);
    final paint = Paint()..strokeWidth = 1;
    final axisColor = const Color(0xFFDCE8ED);

    for (var i = 0; i <= 4; i++) {
      final y = top + chartH * i / 4;
      paint
        ..color = axisColor
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(left, y), Offset(left + chartW, y), paint);
      final amount = ceiling * (4 - i) / 4;
      _text(canvas, '${_shortMoney(amount)}',
          Offset(0, y - 7), const Color(0xFF536779), 10,
          maxWidth: left - 7);
    }
    final n = months.length;
    final cellW = chartW / n;
    final barW = math.min(43.0, cellW * .57);
    final points = <Offset>[];
    for (var i = 0; i < n; i++) {
      final barHeight = chartH * (values[i] / ceiling);
      final center = left + cellW * (i + .5);
      final barRect = Rect.fromLTWH(
          center - barW / 2, top + chartH - barHeight, barW, barHeight);
      final barPaint = Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF007F7A), Color(0xFF35BAA1)],
        ).createShader(barRect);
      canvas.drawRRect(
          RRect.fromRectAndRadius(barRect, const Radius.circular(3)), barPaint);
      points.add(Offset(center, top + chartH - barHeight));
      final label = months[i].label;
      final isLong = label.length >= 7;
      _text(canvas, label,
          Offset(center - cellW * .5, top + chartH + 7),
          const Color(0xFF344F5A), isLong ? 9 : 10,
          maxWidth: cellW,
          align: TextAlign.center);
    }
    if (points.length >= 2) {
      final line = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        line.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(line, Paint()
        ..color = Colors.white
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke);
      canvas.drawPath(line, Paint()
        ..color = const Color(0xFF16A68E)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke);
    }
    for (final p in points) {
      canvas.drawCircle(p, 4.2, Paint()..color = Colors.white);
      canvas.drawCircle(p, 2.3, Paint()..color = const Color(0xFF009988));
    }
  }

  String _shortMoney(double value) {
    final symbol = currency == 'PKR' ? 'Rs' : currency;
    if (value >= 1000000) {
      return '$symbol ${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value >= 1000) {
      return '$symbol ${(value / 1000).toStringAsFixed(0)}k';
    }
    return '$symbol ${value.toStringAsFixed(0)}';
  }

  void _text(Canvas canvas, String value, Offset position, Color color,
      double fontSize, {double maxWidth = 70, TextAlign align = TextAlign.left}) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(
            fontSize: fontSize,
            color: color,
            fontWeight: FontWeight.w500),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(1, maxWidth));
    textPainter.paint(canvas, position);
  }

  @override
  bool shouldRepaint(covariant _FeeTrendPainter oldDelegate) =>
      oldDelegate.currency != currency || oldDelegate.months != months;
}