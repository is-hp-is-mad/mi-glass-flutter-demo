import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../hyper_glass.dart';
import '../ui/kit.dart';
import '../ui/morph_menu.dart';

/// One card per trait of the soft glass: left the trait, right the same glass without it. All samples
/// share one scene over a hard-edged pattern, so differences are not hidden by a soft backdrop.
class TraitsApp extends StatefulWidget {
  const TraitsApp({super.key, required this.onBack});
  final VoidCallback onBack;
  @override
  State<TraitsApp> createState() => _TraitsAppState();
}

typedef _Sample = ({GlassFilter on, GlassFilter off, GlassFx Function(double t)? fx});

class _TraitsAppState extends State<TraitsApp> with TickerProviderStateMixin {
  late final _t = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  late final _menu = PopupMotion(this);
  final _scroll = ScrollController();
  double _offset = 0;
  ui.Image? _mask;

  static const g = GlassFilter();

  static final List<(String, String, _Sample)> _traits = [
    ('折射', '厚度和折射率让背景在边缘弯折；中心平坦处不偏移。', (on: g, off: g.copyWith(thicknessPx: 0), fx: null)),
    ('边缘反射', '边缘采样另一处背景，强度随 SDF 过渡，形成内反光。', (on: g, off: g.copyWith(reflectionStrength: 0, reflectionLighten: 0), fx: null)),
    ('边缘带宽度', '通知用 72px / 3.8，天气卡片用 20px / 1.6，两者气质完全不同。', (on: g.copyWith(edgePx: 72, edgePow: 3.8), off: g, fx: null)),
    ('方向光', '高光落在朝向光源的边缘，随光向旋转。', (on: g, off: g.copyWith(lightIntensity: 0, lightOpposite: 0), fx: null)),
    ('对侧光', '背光一侧的弱高光，让玻璃有厚度感。', (on: g.copyWith(lightOpposite: 2), off: g.copyWith(lightOpposite: 0), fx: null)),
    ('底部内光', 'uInnerBottom：底缘一道极细的提亮。', (on: g.copyWith(innerBottom: 0.3), off: g.copyWith(innerBottom: 0), fx: null)),
    ('暗部压制', '高亮背景被压向深紫灰，白字始终可读。', (on: g.copyWith(darker: 0.8), off: g.copyWith(darker: 0), fx: null)),
    ('亮度曲线', '三次贝塞尔重映射背景亮度。', (on: g.copyWith(luminanceAmount: 0.9), off: g.copyWith(luminanceAmount: 0), fx: null)),
    ('饱和度与亮度', '透过玻璃的颜色比原背景更鲜艳。', (on: g, off: g.copyWith(saturation: 1, brightness: 0), fx: null)),
    ('内部混白', '大模糊背景决定玻璃内部的柔光色，是“柔光”的来源。', (on: g.copyWith(innerColorWhite: 0.8, innerColorMix: 0.9), off: g.copyWith(innerColorWhite: 0, innerColorMix: 0), fx: null)),
    ('烧灼曲线', 'uBurn 控制暗部和亮部的过渡陡度。', (on: g.copyWith(burn: 2), off: g.copyWith(burn: 16), fx: null)),
    ('颜色幂', 'uColorPow 带门控的整体 gamma。', (on: g.copyWith(colorPow: 0.7), off: g.copyWith(colorPow: 1), fx: null)),
    ('玻璃底色', '焦点通知用深色底，通知用白色底。', (on: g.copyWith(glassColor: [0.06, 0.06, 0.06, 0.5]), off: g, fx: null)),
    ('去着色', 'uUnshade：退回玻璃底色，用于淡出。', (on: g.copyWith(unshade: 0.7), off: g, fx: null)),
    ('按下', 'uHit 让折射率随手指上升 0.2，玻璃“陷”下去。', (on: g, off: g, fx: (t) => GlassFx(hit: 0.5 + 0.5 * math.sin(t * 2 * math.pi)))),
    ('折射旋转', 'uRotationTrig：图标旋转时折射方向同步转动。', (on: g, off: g, fx: (t) => GlassFx(rotation: t * 2 * math.pi))),
    ('图标光', 'uIconMove 1：遮罩内的局部提亮，桌面图标在玻璃上的辉光。', (on: g, off: g, fx: (t) => GlassFx(iconRect: (left: 30.0, top: 28.0, width: 90.0, height: 60.0), iconStrength: 1, iconRadius: 18))),
    ('动态光', 'uIconMove 2：遮罩区域内光向独立转动并放大三倍。', (on: g, off: g, fx: (t) => GlassFx(iconRect: (left: 16.0, top: 16.0, width: 118.0, height: 84.0), iconStrength: 1, iconMode: 2, iconRadius: 22, dynamicLight: [math.cos(t * 2 * math.pi), math.sin(t * 2 * math.pi), -0.6]))),
  ];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => setState(() => _offset = _scroll.offset));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mask ??= makeRoundMask(128);
  }

  @override
  void dispose() {
    _t.dispose();
    _menu.dispose();
    _scroll.dispose();
    _mask?.dispose();
    super.dispose();
  }

  void _setMenu(bool v) {
    _menu.set(v);
    setState(() {});
  }

  Widget _trait(String title, String note, _Sample s) {
    final orbit = title == '方向光' || title == '对侧光';
    return _block(
      title,
      note,
      SizedBox(
        height: 116,
        child: AnimatedBuilder(
          animation: _t,
          builder: (_, _) {
            final a = _t.value * 2 * math.pi;
            final on = orbit ? s.on.copyWith(lightDir: [math.cos(a), math.sin(a), -0.5]) : s.on;
            final fx = s.fx?.call(_t.value) ?? const GlassFx();
            return Row(
              children: [
                Expanded(
                  child: HyperGlass(
                    filter: on,
                    borderRadius: 24,
                    fx: fx,
                    mask: _mask,
                    child: const Center(child: Text('开', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: HyperGlass(
                    filter: s.off,
                    borderRadius: 24,
                    child: const Center(child: Text('关', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _block(String title, String note, Widget demo) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 26),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white, fontSize: Hy.title4, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(note, style: const TextStyle(color: Colors.white70, fontSize: Hy.subtitle, height: 1.4)),
        const SizedBox(height: 10),
        demo,
      ],
    ),
  );

  Widget _pressDemo() => const SizedBox(
    height: 116,
    child: GlassPress(
      radius: 24,
      child: Center(child: Text('按住这里', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))),
    ),
  );

  Widget _bloomDemo() => const SizedBox(
    height: 116,
    child: Row(
      children: [
        Expanded(child: HyperGlass(borderRadius: 24, bloom: BloomStroke(width: 1.5, color: Color(0x66ffffff)))),
        SizedBox(width: 12),
        Expanded(child: HyperGlass(borderRadius: 24)),
      ],
    ),
  );

  Widget _shapes() => SizedBox(
    height: 96,
    child: Row(
      children: [
        const SizedBox(width: 96, child: HyperGlass(borderRadius: 48)),
        const SizedBox(width: 12),
        const Expanded(child: HyperGlass(borderRadius: 48)),
        const SizedBox(width: 12),
        SizedBox(
          width: 96,
          child: AnimatedBuilder(
            animation: _t,
            builder: (_, _) => HyperGlass(borderRadius: 8 + 40 * (0.5 + 0.5 * math.sin(_t.value * 2 * math.pi))),
          ),
        ),
      ],
    ),
  );

  Widget _opacity() => SizedBox(
    height: 96,
    child: AnimatedBuilder(
      animation: _t,
      builder: (_, _) => HyperGlass(borderRadius: 24, opacity: 0.5 + 0.5 * math.sin(_t.value * 2 * math.pi)),
    ),
  );

  Widget _materials(bool dark) => Column(
    children: [
      for (final e in BlendPresets.all.entries)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SizedBox(
            height: 70,
            child: Row(
              children: [
                for (final (i, m) in [e.value.$1, e.value.$2].indexed) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(
                    child: HyperBlendBlur(
                      material: m,
                      borderRadius: Hy.rMedium,
                      child: Center(
                        child: Text(
                          '${e.key} · ${i == 0 ? '浅' : '深'}',
                          style: TextStyle(
                            color: i == 0 && e.key != '强调色' ? const Color(0xe6000000) : Colors.white,
                            fontSize: Hy.subtitle,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final dark = OsScope.of(context).dark;
    final top = MediaQuery.paddingOf(context).top + 38;
    return LayoutBuilder(
      builder: (context, c) => AnimatedBuilder(
        animation: _menu.listenable,
        builder: (context, _) {
          final anchor = Rect.fromLTWH(c.maxWidth - 88, c.maxHeight - 110, 64, 64);
          return HyperGlassScene(
            animate: _menu.active,
            background: HyperGlassScene(
              background: const _Pattern(),
              child: ListView(
                controller: _scroll,
                cacheExtent: 300,
                padding: EdgeInsets.only(top: top + Hy.barHeight, bottom: 130),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: Opacity(
                      opacity: 1 - ((_offset - 24) / 32).clamp(0.0, 1.0),
                      child: const Text(
                        '特性图鉴',
                        style: TextStyle(color: Colors.white, fontSize: Hy.title1, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  for (final (t, n, s) in _traits) _trait(t, n, s),
                  _block('按压光', '手指下方的光斑和两道光环，公式来自 libhwui。', _pressDemo()),
                  _block('Bloom 描边', '细描边加上下两道边缘光，桌面 Dock 和文件夹都在用。', _bloomDemo()),
                  _block('任意圆角与 SDF', '形状变化时 SDF 实时重建，所以圆角可以连续变形。', _shapes()),
                  _block('透明度', '淡入淡出不是叠一层遮罩，而是 uAlpha 进入 shader。', _opacity()),
                  _block('混色模糊材质', '系统表面的另一条路线：高斯模糊加多层混合模式，共 5 组。', _materials(dark)),
                  _block('渐变模糊', '滚动这个页面，看顶栏：模糊遮罩按小米天气的 5 段透明度向下渐隐。', const SizedBox(height: 4)),
                ],
              ),
            ),
            child: Stack(
              children: [
                FloatingBar(top: top, title: '特性图鉴', offset: _offset, dark: true, foreground: Colors.white, onBack: widget.onBack),
                const Positioned(left: 0, right: 0, top: 0, child: StatusBar(color: Colors.white)),
                Positioned.fromRect(
                  rect: anchor,
                  child: Opacity(
                    opacity: 1 - menuSwap(_menu.geometry.value),
                    child: GlassPress(
                      radius: 32,
                      onTap: () => _setMenu(true),
                      bloom: const BloomStroke(),
                      child: const Icon(Icons.more_horiz, color: Colors.white, size: 26),
                    ),
                  ),
                ),
                MorphMenu(
                  motion: _menu,
                  anchor: anchor,
                  menu: menuRectFor(anchor, c.biggest, 212, 56.0 * 3 + 16, growUp: true),
                  dark: dark,
                  items: [
                    MorphMenuItem('弹簧变形菜单', icon: Icons.bubble_chart_outlined, () => _setMenu(false)),
                    MorphMenuItem('展开与收起用两组弹簧', icon: Icons.compare_arrows_rounded, () => _setMenu(false)),
                    MorphMenuItem('关闭', icon: Icons.close_rounded, () => _setMenu(false)),
                  ],
                  onDismiss: () => _setMenu(false),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Pattern extends StatelessWidget {
  const _Pattern();
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _PatternPainter(), child: const SizedBox.expand());
}

class _PatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff141d4f), Color(0xff3b2a8c), Color(0xff7a2f86), Color(0xffa8463f)],
        ).createShader(rect),
    );
    final bar = Paint()..color = const Color(0x14ffffff);
    for (var y = 0.0; y < size.height; y += 58) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 6), bar);
    }
    final dot = Paint();
    for (var i = 0; i < 26; i++) {
      canvas.drawCircle(
        Offset((i * 83.0) % size.width, (i * 137.0) % size.height),
        5 + (i % 3) * 4.0,
        dot..color = [const Color(0x99ffe27a), const Color(0x9958e0c6), const Color(0x99ff7aa2)][i % 3],
      );
    }
  }

  @override
  bool shouldRepaint(_PatternPainter old) => false;
}
