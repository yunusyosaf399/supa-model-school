import 'package:flutter/material.dart';
import 'school_theme.dart';
import '../features/owner/data/school_logo_service.dart';

class SchoolMark extends StatelessWidget {
  const SchoolMark({super.key, this.size = 68, this.logoService});
  final double size;
  final SchoolLogoService? logoService;

  @override
  Widget build(BuildContext context) {
    final service = logoService;
    if (service != null) {
      return AnimatedBuilder(
        animation: service,
        builder: (context, _) {
          final bytes = service.bytes;
          if (bytes == null) return SchoolMark(size: size);
          return ClipRRect(
            borderRadius: BorderRadius.circular(size * .18),
            child: Image.memory(bytes, width: size, height: size,
              fit: BoxFit.contain, gaplessPlayback: true),
          );
        },
      );
    }
    final primary = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF65DCCF)
        : SchoolPalette.teal;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.shield_outlined, size: size, color: primary),
          Icon(Icons.menu_book_rounded, size: size * .47, color: primary),
          Positioned(
            top: size * .12,
            child: Icon(Icons.star_rounded,
                size: size * .19, color: const Color(0xFFF2B935)),
          ),
        ],
      ),
    );
  }
}

/// Vector-only school illustration. This is a visual placeholder until the
/// licensed photograph/logo can be committed as a separate school asset.
class SchoolScene extends StatelessWidget {
  const SchoolScene({super.key, this.height = 290});
  final double height;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: 'Illustration of a school building',
      image: true,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: CustomPaint(
            painter: _SchoolScenePainter(dark),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _SchoolScenePainter extends CustomPainter {
  const _SchoolScenePainter(this.dark);
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final sky = Paint()
      ..shader = LinearGradient(
        colors: dark
            ? [const Color(0xFF15323E), const Color(0xFF25626A)]
            : [const Color(0xFFDCF0FA), const Color(0xFFAADCE8)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, sky);
    final hill = Paint()..color = dark ? const Color(0xFF215B53) : const Color(0xFF87C5AB);
    canvas.drawOval(Rect.fromLTWH(-w * .15, h * .69, w * 1.35, h * .40), hill);

    final building = Paint()..color = dark ? const Color(0xFFE3E5DA) : const Color(0xFFF5FAF5);
    final trim = Paint()..color = const Color(0xFF00776D);
    final glass = Paint()..color = dark ? const Color(0xFF487B8A) : const Color(0xFF77B6C7);
    final x = w * .13, y = h * .31, bw = w * .74, bh = h * .58;
    canvas.drawRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(x, y, bw, bh), const Radius.circular(5)), building);
    canvas.drawRect(Rect.fromLTWH(x, y, bw, h * .025), trim);
    for (var row = 0; row < 2; row++) {
      for (var col = 0; col < 8; col++) {
        final wx = x + bw * (.045 + col * .118);
        final wy = y + bh * (.14 + row * .39);
        canvas.drawRect(Rect.fromLTWH(wx, wy, bw * .078, bh * .25), glass);
      }
    }
    canvas.drawRect(Rect.fromLTWH(w * .405, y - h * .06, w * .19, bh + h * .06), trim);
    canvas.drawRect(Rect.fromLTWH(w * .431, y + h * .015, w * .138, h * .20), building);
    canvas.drawRect(Rect.fromLTWH(w * .451, y + h * .41, w * .098, h * .22), glass);
    final flagpole = Paint()..color = const Color(0xFF6A8384)..strokeWidth = 2;
    canvas.drawLine(Offset(w * .5, y - h * .06), Offset(w * .5, y - h * .19), flagpole);
    final flag = Path()
      ..moveTo(w * .50, y - h * .19)
      ..lineTo(w * .59, y - h * .16)
      ..lineTo(w * .50, y - h * .13)
      ..close();
    canvas.drawPath(flag, trim);
    final tree = Paint()..color = dark ? const Color(0xFF1F7060) : const Color(0xFF4B9975);
    final trunk = Paint()..color = const Color(0xFF785F4D);
    for (final t in [w * .055, w * .93]) {
      canvas.drawRect(Rect.fromLTWH(t, h * .56, w * .014, h * .31), trunk);
      canvas.drawCircle(Offset(t + w * .007, h * .54), h * .13, tree);
    }
  }

  @override
  bool shouldRepaint(covariant _SchoolScenePainter oldDelegate) =>
      dark != oldDelegate.dark;
}
