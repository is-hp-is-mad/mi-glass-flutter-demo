import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Procedural wallpapers: slow mesh gradients with crisp shapes, which is what shows off refraction.
class Wallpaper extends StatefulWidget {
  const Wallpaper({super.key, required this.index, required this.dark, this.animate = true});
  final int index;
  final bool dark, animate;
  static const names = ['幻彩', '深海', '极光', '琥珀'];
  static const sky = 4;
  @override
  State<Wallpaper> createState() => _WallpaperState();
}

class _WallpaperState extends State<Wallpaper> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 40));

  void _sync() {
    if (widget.animate && !_c.isAnimating) _c.repeat();
    if (!widget.animate && _c.isAnimating) _c.stop();
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(Wallpaper old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: _c,
      builder: (_, _) => CustomPaint(painter: _WallPainter(_c.value, widget.index, widget.dark), child: const SizedBox.expand()),
    ),
  );
}

const _palettes = [
  [Color(0xff2b64d8), Color(0xff72b6ff), Color(0xffffb37e), Color(0xffff6f91), Color(0xff8c6bff)],
  [Color(0xff04213f), Color(0xff0a6ea8), Color(0xff19c4c4), Color(0xff2b3f9e), Color(0xff77ffd1)],
  [Color(0xff0f1d3a), Color(0xff1fbf8f), Color(0xff4f7cff), Color(0xffa24bff), Color(0xff9dffb0)],
  [Color(0xff5a2410), Color(0xffff9a3d), Color(0xffffd76a), Color(0xffd8435a), Color(0xfffff0c0)],
  [Color(0xff0f3f8c), Color(0xff2a78d6), Color(0xff6fb1ee), Color(0xff3a6fd8), Color(0xff5a8cf0)], // the weather app's sky
];

class _WallPainter extends CustomPainter {
  _WallPainter(this.t, this.index, this.dark);
  final double t;
  final int index;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final p = _palettes[index % _palettes.length];
    final rect = Offset.zero & size;
    canvas.clipRect(rect); // the blobs and arcs reach well past the wallpaper's box
    if (index == 0) return _paintCrescents(canvas, size);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [p[0], p[1], p[2]]).createShader(rect),
    );
    final a = t * 2 * math.pi;
    void blob(double cx, double cy, double r, Color c) {
      final o = Offset(size.width * cx, size.height * cy);
      final rad = size.shortestSide * r;
      canvas.drawCircle(
        o,
        rad,
        Paint()..shader = RadialGradient(colors: [c, c.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: o, radius: rad)),
      );
    }

    blob(0.2 + 0.18 * math.sin(a), 0.22 + 0.08 * math.cos(a), 1.1, p[3]);
    blob(0.85 + 0.12 * math.cos(a), 0.5 + 0.12 * math.sin(a * 2), 1.0, p[4]);
    blob(0.4 + 0.25 * math.sin(a * 2), 0.92, 1.2, p[2]);
    // crisp arcs give refraction something to bend
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.16;
    for (var i = 0; i < 3; i++) {
      final c = Offset(size.width * (0.75 - i * 0.28), size.height * (0.32 + i * 0.26) + 24 * math.sin(a + i));
      arc.color = Colors.white.withValues(alpha: 0.13 + i * 0.03);
      canvas.drawArc(Rect.fromCircle(center: c, radius: size.width * (0.42 + i * 0.1)), a + i * 2, 3.6, false, arc);
    }
    for (var i = 0; i < 16; i++) {
      final x = (0.08 * i + 0.13 * math.sin(i * 7.3)) % 1, y = (0.067 * i + 0.3 * math.cos(i * 3.1) + t * 0.2) % 1;
      canvas.drawCircle(Offset(size.width * x, size.height * y), 3 + i % 4 * 3.0, Paint()..color = Colors.white.withValues(alpha: 0.32));
    }
    if (dark) canvas.drawRect(rect, Paint()..color = const Color(0x8c000000));
  }

  // Near-black with lit crescents, the look of OS4's stock wallpapers: glass needs dark ground and hard
  // bright edges to read as clear, a pastel field only turns it milky.
  void _paintCrescents(Canvas canvas, Size size) {
    final a = t * 2 * math.pi;
    canvas.drawColor(const Color(0xff040807), BlendMode.src);
    void crescent(Offset lit, double r, Offset cut, double cutR, List<Color> colors, double turn) {
      final box = Rect.fromCircle(center: lit, radius: r);
      canvas.drawCircle(lit, r, Paint()..shader = SweepGradient(colors: colors, transform: GradientRotation(turn)).createShader(box));
      final hole = Rect.fromCircle(center: cut, radius: cutR);
      canvas.drawCircle(
        cut,
        cutR,
        Paint()
          ..shader = RadialGradient(
            colors: const [Color(0xff0b1411), Color(0xff040807)],
            center: const Alignment(0.3, 0.2),
          ).createShader(hole),
      );
      canvas.drawCircle(
        cut,
        cutR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = const Color(0x8cffffff),
      );
    }

    final w = size.width, h = size.height;
    crescent(Offset(w * 0.56, h * 0.36), w * 0.74, Offset(w * 0.68 + 10 * math.sin(a), h * 0.42), w * 0.68, const [
      Color(0xff0fd27a),
      Color(0xffe6f25a),
      Color(0xff14b8ff),
      Color(0xff5a3dff),
      Color(0xff0fd27a),
    ], a);
    crescent(Offset(w * 0.2, h * 0.86), w * 0.62, Offset(w * 0.08, h * 0.92 + 10 * math.cos(a)), w * 0.56, const [
      Color(0xffff4d8d),
      Color(0xff7a3dff),
      Color(0xff14b8ff),
      Color(0xffff9d3d),
      Color(0xffff4d8d),
    ], -a);
    if (dark) canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0x40000000));
  }

  @override
  bool shouldRepaint(_WallPainter old) => old.t != t || old.index != index || old.dark != dark;
}

/// Procedural "photo": a landscape / portrait-ish scene derived from [seed].
class PhotoArt extends StatelessWidget {
  const PhotoArt(this.seed, {super.key, this.fit = true});
  final int seed;
  final bool fit;
  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: CustomPaint(painter: _PhotoPainter(seed), child: const SizedBox.expand()),
  );
}

class _PhotoPainter extends CustomPainter {
  _PhotoPainter(this.seed);
  final int seed;

  static const _skies = [
    [Color(0xff2c78e4), Color(0xffbfe3ff)],
    [Color(0xfff77f5e), Color(0xffffd9a0)],
    [Color(0xff14213d), Color(0xff5a4fcf)],
    [Color(0xff0fb5ba), Color(0xffe5fff4)],
    [Color(0xffff6fa5), Color(0xfffff0b8)],
    [Color(0xff28324e), Color(0xfff2a65a)],
  ];
  static const _land = [Color(0xff27593f), Color(0xff1b3a4b), Color(0xff5c3a21), Color(0xff304d6d), Color(0xff6a2c70), Color(0xff1f2933)];

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.Random(seed * 7919 + 13);
    final rect = Offset.zero & size;
    final sky = _skies[seed % _skies.length];
    canvas.drawRect(
      rect,
      Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: sky).createShader(rect),
    );
    final sun = Offset(size.width * (0.2 + r.nextDouble() * 0.6), size.height * (0.2 + r.nextDouble() * 0.3));
    canvas.drawCircle(sun, size.shortestSide * (0.08 + r.nextDouble() * 0.1), Paint()..color = const Color(0xeeffffff));
    final kind = seed % 3;
    for (var l = 0; l < 3; l++) {
      final base = size.height * (0.5 + l * 0.17);
      final path = Path()..moveTo(0, size.height);
      final step = size.width / 8;
      for (var i = 0; i <= 8; i++) {
        final h = kind == 1 ? (i.isEven ? 1.0 : 0.15) : r.nextDouble();
        path.lineTo(i * step, base - h * size.height * 0.17);
      }
      path
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(path, Paint()..color = Color.lerp(_land[(seed + l) % _land.length], sky[1], 0.34 - l * 0.14)!);
    }
    if (kind == 2) {
      for (var i = 0; i < 5; i++) {
        final x = r.nextDouble() * size.width, w = size.width * (0.06 + r.nextDouble() * 0.09);
        final h = size.height * (0.18 + r.nextDouble() * 0.3);
        canvas.drawRect(Rect.fromLTWH(x, size.height - h, w, h), Paint()..color = const Color(0xaa10151f));
      }
    }
  }

  @override
  bool shouldRepaint(_PhotoPainter old) => old.seed != seed;
}
