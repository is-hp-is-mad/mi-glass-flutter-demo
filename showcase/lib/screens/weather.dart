import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/art.dart';
import '../ui/kit.dart';

/// MIUIWeather: every card is the reverse-engineered `ImageFilter.glass` surface on the living sky; the
/// app's text stays white in both modes, as the original does.
class WeatherApp extends StatefulWidget {
  const WeatherApp({super.key, required this.onBack});
  final VoidCallback onBack;
  @override
  State<WeatherApp> createState() => _WeatherAppState();
}

class _WeatherAppState extends State<WeatherApp> with TickerProviderStateMixin {
  late final _menu = ArcMotion(this);
  final _scroll = ScrollController();
  double _offset = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => setState(() => _offset = _scroll.offset));
  }

  @override
  void dispose() {
    _menu.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _setMenu(bool v) {
    _menu.set(v);
    setState(() {});
  }

  Widget _card(String title, {required Widget child, double? height}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: SizedBox(
      height: height,
      child: GlassPress(
        radius: Hy.rDemiBig,
        scale: 0.98,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white70, fontSize: Hy.subtitle)),
              const SizedBox(height: 10),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    ),
  );

  static const _white = TextStyle(color: Colors.white);

  @override
  Widget build(BuildContext context) {
    final os = OsScope.of(context);
    final dark = os.dark;
    final top = MediaQuery.paddingOf(context).top + 38;
    final hours = [for (var i = 0; i < 9; i++) (i == 0 ? '现在' : '${(10 + i) % 24}:00', 23 - i ~/ 2, i % 3 == 1)];
    final days = [
      ('今天', '多云', 18, 26),
      ('明天', '小雨', 15, 21),
      ('周二', '阴', 14, 20),
      ('周三', '晴', 16, 24),
      ('周四', '晴', 17, 26),
    ];
    return LayoutBuilder(
      builder: (context, c) => AnimatedBuilder(
        animation: _menu.listenable,
        builder: (context, _) => HyperGlassScene(
          animate: _menu.active,
          background: HyperGlassScene(
            background: Wallpaper(index: Wallpaper.sky, dark: dark),
            child: ListView(
              controller: _scroll,
              padding: EdgeInsets.fromLTRB(16, top + 60, 16, 60),
              children: [
                const Text('北京市', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: Hy.title3, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                const Text(
                  '23°',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 112, fontWeight: FontWeight.w200, height: 1.15),
                ),
                const Text('多云  18° / 26°', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: Hy.body1)),
                const SizedBox(height: 36),
                _card(
                  '未来 24 小时 · 傍晚有小雨',
                  height: 138,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final (t, v, rain) in hours)
                        SizedBox(
                          width: 58,
                          child: Column(
                            children: [
                              Text(t, style: const TextStyle(color: Colors.white70, fontSize: Hy.footnote + 1)),
                              const SizedBox(height: 8),
                              Icon(rain ? Icons.water_drop_rounded : Icons.wb_cloudy_rounded, size: 22, color: Colors.white),
                              const SizedBox(height: 8),
                              Text('$v°', style: _white.copyWith(fontSize: Hy.body1, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                _card(
                  '15 日预报',
                  child: Column(
                    children: [
                      for (final (d, w, lo, hi) in days)
                        SizedBox(
                          height: 40,
                          child: Row(
                            children: [
                              SizedBox(width: 48, child: Text(d, style: _white.copyWith(fontSize: Hy.body1))),
                              SizedBox(width: 44, child: Text(w, style: const TextStyle(color: Colors.white70, fontSize: Hy.body2))),
                              Text('$lo°', style: const TextStyle(color: Colors.white70, fontSize: Hy.body2)),
                              const SizedBox(width: 8),
                              Expanded(child: _tempBar(lo, hi)),
                              const SizedBox(width: 8),
                              Text('$hi°', style: _white.copyWith(fontSize: Hy.body2)),
                            ],
                          ),
                        ),
                    ],
                  ),
                  height: 266,
                ),
                Row(
                  children: [
                    Expanded(
                      child: _card(
                        '空气质量',
                        height: 150,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('32', style: _white.copyWith(fontSize: 38, fontWeight: FontWeight.w300)),
                            const Text('优 · PM2.5', style: TextStyle(color: Colors.white70, fontSize: Hy.subtitle)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _card(
                        '日出日落',
                        height: 150,
                        child: CustomPaint(
                          painter: _SunArc(),
                          child: const Align(
                            alignment: Alignment.bottomCenter,
                            child: Text('06:12 / 17:48', style: TextStyle(color: Colors.white70, fontSize: Hy.subtitle)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    for (final (i, e) in const [('湿度', '62%'), ('体感', '25°'), ('风速', '3 级')].indexed) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(
                        child: _card(
                          e.$1,
                          height: 104,
                          child: Text(e.$2, style: _white.copyWith(fontSize: Hy.title3 + 2, fontWeight: FontWeight.w400)),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          child: Stack(
            children: [
              FloatingBar(
                top: top,
                title: '北京市',
                offset: _offset,
                dark: dark,
                foreground: Colors.white,
                onBack: widget.onBack,
                actions: [
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: GestureDetector(
                      onTap: () => _setMenu(true),
                      behavior: HitTestBehavior.opaque,
                      child: const Icon(Icons.more_horiz, color: Colors.white, size: 24),
                    ),
                  ),
                ],
              ),
              const Positioned(left: 0, right: 0, top: 0, child: StatusBar(color: Colors.white)),
              ArcMenu(
                motion: _menu,
                anchor: Rect.fromLTWH(c.maxWidth - 52, top + 8, 40, 40),
                menu: menuRectFor(Rect.fromLTWH(c.maxWidth - 52, top + 8, 40, 40), c.biggest, 200, ArcMenu.heightFor(3), growUp: false),
                items: [
                  HyperMenuItem('添加城市', icon: Icons.add_location_alt_outlined, () => _setMenu(false)),
                  HyperMenuItem('分享天气', icon: Icons.share_outlined, () => _setMenu(false)),
                  HyperMenuItem(dark ? '浅色模式' : '深色模式', icon: Icons.dark_mode_outlined, () {
                    _setMenu(false);
                    os.setDark(!dark);
                  }),
                ],
                onDismiss: () => _setMenu(false),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tempBar(int lo, int hi) => LayoutBuilder(
    builder: (context, c) {
      final l = (lo - 12) / 16 * c.maxWidth, r = (hi - 12) / 16 * c.maxWidth;
      return Stack(
        alignment: Alignment.centerLeft,
        children: [
          Container(
            height: 4,
            decoration: BoxDecoration(color: const Color(0x33ffffff), borderRadius: BorderRadius.circular(2)),
          ),
          Positioned(
            left: l,
            width: r - l,
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: const LinearGradient(colors: [Color(0xff8fe0ff), Color(0xffffd36b)]),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _SunArc extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromCircle(center: Offset(size.width / 2, size.height - 22), radius: size.width * 0.42);
    canvas.drawArc(
      r,
      math.pi,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0x66ffffff),
    );
    canvas.drawArc(
      r,
      math.pi,
      math.pi * 0.55,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = const Color(0xffffd36b),
    );
    final a = math.pi * 1.55;
    canvas.drawCircle(r.center + Offset(math.cos(a), math.sin(a)) * r.width / 2, 5, Paint()..color = const Color(0xffffe08a));
  }

  @override
  bool shouldRepaint(_SunArc oldDelegate) => false;
}
