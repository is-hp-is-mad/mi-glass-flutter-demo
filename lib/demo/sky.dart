import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Animated sky with moving blobs and large text, so blur, refraction and tint are all visible.
class Sky extends StatefulWidget {
  const Sky({super.key, required this.dark, required this.label});
  final bool dark;

  /// The big temperature drawn into the sky (e.g. "23°").
  final String label;
  @override
  State<Sky> createState() => _SkyState();
}

class _SkyState extends State<Sky> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, _) =>
        CustomPaint(painter: _SkyPainter(_c.value, widget.dark, widget.label), child: const SizedBox.expand()),
  );
}

class _SkyPainter extends CustomPainter {
  _SkyPainter(this.t, this.dark, this.label);
  final double t;
  final bool dark;
  final String label;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? const [Color(0xFF0B1630), Color(0xFF1C2E5A), Color(0xFF3B3060)]
              : const [Color(0xFF2F6FD6), Color(0xFF5FA8F0), Color(0xFFF2B27A)],
        ).createShader(rect),
    );
    final a = t * 2 * math.pi;
    void blob(double cx, double cy, double r, Color c) =>
        canvas.drawCircle(Offset(size.width * cx, size.height * cy), r, Paint()..color = c);
    blob(
      0.25 + 0.15 * math.sin(a),
      0.35 + 0.1 * math.cos(a * 2),
      90,
      dark ? const Color(0xFFE8E2C0) : const Color(0xFFFFE07A),
    );
    blob(0.75 + 0.1 * math.cos(a), 0.55 + 0.15 * math.sin(a), 120, const Color(0xFFE85D75));
    blob(0.5 + 0.3 * math.sin(a * 3), 0.8, 70, const Color(0xFF3BD18A));
    for (var i = 0; i < 12; i++) {
      final y = (i * 0.09 + t) % 1.0;
      canvas.drawRect(Rect.fromLTWH(0, size.height * y, size.width, 3), Paint()..color = const Color(0x66FFFFFF));
    }
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(fontFamily: 'MiSans', color: Colors.white, fontSize: 150, fontWeight: FontWeight.w200),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, 40));
  }

  @override
  bool shouldRepaint(_SkyPainter old) => old.t != t || old.dark != dark || old.label != label;
}
