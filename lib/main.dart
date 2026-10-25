import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'ci/capture_stub.dart' if (dart.library.io) 'ci/capture_io.dart';
import 'ci/driver.dart';
import 'hyper_glass.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  limitSkiaResourceCache();
  runApp(const DemoApp());
}

class DemoApp extends StatefulWidget {
  const DemoApp({super.key});

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  ThemeMode _mode = ThemeMode.system;
  final _root = GlobalKey(); // whole-app boundary, used by the CI capture script

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'HyperGlass',
    themeMode: _mode,
    theme: ThemeData(brightness: Brightness.light, fontFamily: 'MiSans'),
    darkTheme: ThemeData(brightness: Brightness.dark, fontFamily: 'MiSans'),
    builder: (context, child) => RepaintBoundary(key: _root, child: child),
    home: WeatherDemo(
      captureRoot: _root,
      onToggleDark: (dark) => setState(() => _mode = dark ? ThemeMode.dark : ThemeMode.light),
    ),
  );
}

class WeatherDemo extends StatefulWidget {
  const WeatherDemo({super.key, required this.onToggleDark, required this.captureRoot});

  final ValueChanged<bool> onToggleDark;
  final GlobalKey captureRoot;

  @override
  State<WeatherDemo> createState() => _WeatherDemoState();
}

// Unbounded controllers driven by springs so menu and dialog can overshoot like HyperOS.
class _WeatherDemoState extends State<WeatherDemo> with TickerProviderStateMixin implements DemoDriver {
  @override
  void initState() {
    super.initState();
    if (captureRequested) WidgetsBinding.instance.addPostFrameCallback((_) => runCapture(widget.captureRoot, this));
  }

  @override
  void setMenu(bool open) => _setMenu(open);
  @override
  void setDialog(bool open) => _setDialog(open);
  @override
  void setDark(bool dark) => widget.onToggleDark(dark);

  late final _menu = AnimationController.unbounded(vsync: this);
  late final _dialog = AnimationController.unbounded(vsync: this);
  bool _menuOpen = false, _dialogOpen = false;

  static const _menuSpring = SpringDescription(mass: 1, stiffness: 380, damping: 26);
  static const _dialogSpring = SpringDescription(mass: 1, stiffness: 300, damping: 26);

  void _setMenu(bool open) {
    _menuOpen = open;
    _menu.animateWith(SpringSimulation(_menuSpring, _menu.value, open ? 1 : 0, _menu.velocity));
    setState(() {});
  }

  void _setDialog(bool open) {
    _dialogOpen = open;
    _dialog.animateWith(SpringSimulation(_dialogSpring, _dialog.value, open ? 1 : 0, _dialog.velocity));
    setState(() {});
  }

  @override
  void dispose() {
    _menu.dispose();
    _dialog.dispose();
    super.dispose();
  }

  /// Cross-fade between the glass button and the frosted menu while the menu is still about the
  /// button's size (first 15% of the morph). The spring settles around 0 when closing; there the
  /// menu is fully transparent, so the button never shows through a frosted layer.
  double get _menuSwap => (_menu.value / 0.15).clamp(0.0, 1.0);

  bool get _overlayActive => _menuOpen || _dialogOpen || _menu.value > 0.001 || _dialog.value > 0.001;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, c) {
          // Inner scene: sky + weather cards + the glass button. Outer scene: everything below the
          // overlays (inner scene and the dialog dim), so menu and dialog blur what is really under them.
          final page = HyperGlassScene(
            background: _Sky(dark: dark),
            child: Stack(children: [_cards(), _button(c)]),
          );
          return AnimatedBuilder(
            animation: Listenable.merge([_menu, _dialog]),
            builder: (context, _) => HyperGlassScene(
              animate: _overlayActive,
              background: Stack(
                fit: StackFit.expand,
                children: [
                  page,
                  IgnorePointer(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: (dark ? 0.45 : 0.3) * _dialog.value.clamp(0.0, 1.0)),
                    ),
                  ),
                ],
              ),
              child: Stack(children: [_menuLayer(c, dark), _dialogLayer(c, dark)]),
            ),
          );
        },
      ),
    );
  }

  Widget _cards() {
    const white = TextStyle(color: Colors.white);
    Widget card(String title, String body, {double height = 120}) => HyperGlass(
      borderRadius: 24,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: white.copyWith(fontSize: 13, color: Colors.white70)),
              const SizedBox(height: 8),
              Text(body, style: white.copyWith(fontSize: 20, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const SizedBox(height: 200),
              card('空气质量', '优 32'),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: card('湿度', '62%', height: 150)),
                  const SizedBox(width: 14),
                  Expanded(child: card('体感', '25°', height: 150)),
                ],
              ),
              const SizedBox(height: 14),
              card('15 日预报', '多云转晴  18° / 26°', height: 220),
              const SizedBox(height: 14),
              card('日出日落', '06:12  ·  17:48'),
              const SizedBox(height: 400),
            ],
          ),
        ),
      ),
    );
  }

  static const _buttonSize = Size(64, 64);
  // HyperOS puts such buttons at a screen edge / corner; the menu then bursts out of that corner.
  Rect _buttonRect(BoxConstraints c) => Rect.fromLTWH(
    c.maxWidth - 24 - _buttonSize.width,
    c.maxHeight - 24 - _buttonSize.height,
    _buttonSize.width,
    _buttonSize.height,
  );

  // The menu grows out of the button and replaces it, so the button hides as soon as the menu starts.
  Widget _button(BoxConstraints c) => Positioned.fromRect(
    rect: _buttonRect(c),
    child: AnimatedBuilder(
      animation: _menu,
      builder: (context, child) => IgnorePointer(
        ignoring: _menuOpen,
        child: Opacity(opacity: 1 - _menuSwap, child: child),
      ),
      child: GestureDetector(
        onTap: () => _setMenu(true),
        child: const HyperGlass(
          borderRadius: 32,
          child: Center(child: Icon(Icons.more_horiz, color: Colors.white, size: 28)),
        ),
      ),
    ),
  );

  // ---------------------------------------------------------------- popup menu (hyperos.popup_menu)
  Widget _menuLayer(BoxConstraints c, bool dark) {
    final t = _menu.value;
    if (t <= 0.001 && !_menuOpen) return const SizedBox.shrink();
    final fg = dark ? Colors.white.withValues(alpha: 0.9) : Colors.black.withValues(alpha: 0.9);
    final items = <(IconData, String, VoidCallback)>[
      (
        Icons.umbrella_outlined,
        '降雨提醒',
        () {
          _setMenu(false);
          _setDialog(true);
        },
      ),
      (
        dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        dark ? '浅色模式' : '深色模式',
        () {
          _setMenu(false);
          widget.onToggleDark(!dark);
        },
      ),
      (Icons.share_outlined, '分享天气', () => _setMenu(false)),
      (Icons.settings_outlined, '设置', () => _setMenu(false)),
    ];
    const itemH = 56.0, width = 220.0;
    final anchor = _buttonRect(c);
    // Final menu: shares the button's bottom edge, kept inside the screen.
    final menuH = itemH * items.length + 16;
    // Align the menu with the button's own edge when it sits near a screen edge, so the menu (and
    // its items, see _popItem) spreads out of the corner towards the screen centre.
    final double left;
    if (anchor.center.dx > c.maxWidth * 2 / 3) {
      left = anchor.right - width; // right edge / corner
    } else if (anchor.center.dx < c.maxWidth / 3) {
      left = anchor.left; // left edge / corner
    } else {
      left = anchor.center.dx - width / 2;
    }
    final menu = Rect.fromLTWH(left.clamp(12.0, c.maxWidth - width - 12), anchor.bottom - menuH, width, menuH);
    // Real geometry morph (not a scale transform): the blur surface keeps sampling what is under it.
    final rect = Rect.lerp(anchor, menu, t)!;
    return Stack(
      children: [
        if (_menuOpen) Positioned.fill(child: GestureDetector(onTap: () => _setMenu(false))),
        Positioned.fromRect(
          rect: rect,
          child: ClipRect(
            child: HyperBlendBlur(
              material: dark ? BlendMaterial.popupMenuDark : BlendMaterial.popupMenuLight,
              borderRadius: 32 + (24 - 32) * t.clamp(0.0, 1.0),
              opacity: _menuSwap,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // items are laid out at the final size and revealed by the growing clip
                  OverflowBox(
                    alignment: Alignment.bottomCenter,
                    minWidth: width,
                    maxWidth: width,
                    minHeight: menuH,
                    maxHeight: menuH,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          for (final (i, (icon, label, onTap)) in items.indexed)
                            InkWell(
                              onTap: onTap,
                              child: SizedBox(
                                height: itemH,
                                child: _popItem(
                                  t,
                                  // from the tap point (button centre) to this item's content
                                  anchor.center - menu.topLeft - Offset(_itemContentX, 8 + itemH * (i + 0.5)),
                                  Row(
                                    children: [
                                      const SizedBox(width: 22),
                                      Icon(icon, color: fg, size: 22),
                                      const SizedBox(width: 14),
                                      Text(
                                        label,
                                        style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// x of an item's icon+label centre inside the menu (22 inset, 22 icon, 14 gap, ~4 CJK chars).
  static const _itemContentX = 72.0;

  /// Items burst out of the tap point: each starts at the button centre ([fromTap] is the offset from
  /// its resting place to there), small and transparent, and flies outward to its slot while growing,
  /// all driven by the menu spring (its overshoot makes them pop slightly past 100%). Closing replays
  /// it backwards, so they collapse into the button again.
  Widget _popItem(double t, Offset fromTap, Widget child) {
    final q = math.max(0.0, t); // 1 at rest, slightly >1 while overshooting
    return Opacity(
      opacity: ((t - 0.1) / 0.4).clamp(0.0, 1.0),
      child: Transform.translate(
        offset: fromTap * (1 - q).clamp(0.0, 1.0),
        child: Transform.scale(
          scale: 0.3 + 0.7 * q,
          alignment: const Alignment(_itemContentX / 110 - 1, 0),
          child: child,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- dialog (launcher uninstall style)
  Widget _dialogLayer(BoxConstraints c, bool dark) {
    final t = _dialog.value;
    if (t <= 0.001 && !_dialogOpen) return const SizedBox.shrink();
    final fg = dark ? Colors.white.withValues(alpha: 0.9) : Colors.black.withValues(alpha: 0.9);
    final sub = dark ? Colors.white.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.6);
    final w = math.min(420.0, c.maxWidth - 24);
    const h = 236.0;
    final rect = Rect.fromLTWH((c.maxWidth - w) / 2, c.maxHeight - h - 12 + (1 - t) * (h + 24), w, h);
    Widget button(String label, bool primary, VoidCallback onTap) => Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary
                ? const Color(0xff3482ff)
                : (dark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.06)),
            borderRadius: BorderRadius.circular(25),
          ),
          child: Text(
            label,
            style: TextStyle(color: primary ? Colors.white : fg, fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
    return Stack(
      children: [
        if (_dialogOpen) Positioned.fill(child: GestureDetector(onTap: () => _setDialog(false))),
        Positioned.fromRect(
          rect: rect,
          child: HyperBlendBlur(
            material: dark ? BlendMaterial.dialogDark : BlendMaterial.dialogLight,
            borderRadius: 32,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Column(
                children: [
                  Text(
                    '开启降雨提醒？',
                    style: TextStyle(color: fg, fontSize: 19, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '未来 2 小时内有小雨。开启后，降雨前 15 分钟会通知你带伞。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: sub, fontSize: 15, height: 1.5),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      button('取消', false, () => _setDialog(false)),
                      const SizedBox(width: 12),
                      button('开启', true, () => _setDialog(false)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Animated sky with moving blobs and large text, so blur, refraction and tint are all visible.
class _Sky extends StatefulWidget {
  const _Sky({required this.dark});
  final bool dark;
  @override
  State<_Sky> createState() => _SkyState();
}

class _SkyState extends State<_Sky> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(seconds: 20))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, _) => CustomPaint(painter: _SkyPainter(_c.value, widget.dark), child: const SizedBox.expand()),
  );
}

class _SkyPainter extends CustomPainter {
  _SkyPainter(this.t, this.dark);
  final double t;
  final bool dark;

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
      text: const TextSpan(
        text: '23°',
        style: TextStyle(fontFamily: 'MiSans', color: Colors.white, fontSize: 150, fontWeight: FontWeight.w200),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, 40));
  }

  @override
  bool shouldRepaint(_SkyPainter old) => old.t != t || old.dark != dark;
}
