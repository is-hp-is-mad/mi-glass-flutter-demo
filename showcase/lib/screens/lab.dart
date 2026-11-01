import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../hyper_glass.dart';
import '../ui/art.dart';
import '../ui/kit.dart';

/// Every shader parameter on a slider, over any ROM preset. Drag the glass; the light follows a second
/// drag on the free wallpaper.
class LabApp extends StatefulWidget {
  const LabApp({super.key, required this.onBack});
  final VoidCallback onBack;
  @override
  State<LabApp> createState() => _LabAppState();
}

class _LabAppState extends State<LabApp> {
  String _preset = '天气卡片 · 逆向';
  late GlassFilter _f = GlassPresets.all[_preset]!;
  Offset _pos = const Offset(46, 150);
  int _shape = 0;
  double _hit = 0, _rotation = 0, _icon = 0, _opacity = 1;
  bool _bloom = true, _dynamic = false;
  int _wall = 2;
  Offset _lightAt = const Offset(0.2, 0.2);
  ui.Image? _mask;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mask ??= makeRoundMask(128);
  }

  @override
  void dispose() {
    _mask?.dispose();
    super.dispose();
  }

  Size get _size => switch (_shape) {
    0 => const Size(290, 170),
    1 => const Size(290, 84),
    _ => const Size(150, 150),
  };
  double get _radius => switch (_shape) {
    0 => 28,
    _ => 300,
  };

  void _setPreset(String p) => setState(() {
    _preset = p;
    _f = GlassPresets.all[p]!;
  });

  List<double> get _dir {
    final x = (_lightAt.dx - 0.5) * 2, y = (0.5 - _lightAt.dy) * 2;
    return [x, y, -0.6];
  }

  Widget _section(String t, bool dark) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
    child: Text(
      t,
      style: TextStyle(color: Hy.text(dark), fontSize: Hy.body1, fontWeight: FontWeight.w600),
    ),
  );

  Widget _slider(String label, double v, double lo, double hi, ValueChanged<double> set, bool dark) => SizedBox(
    height: 36,
    child: Row(
      children: [
        SizedBox(
          width: 106,
          child: Text(label, style: TextStyle(color: Hy.sub(dark), fontSize: Hy.subtitle)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              activeTrackColor: Hy.primary(dark),
              inactiveTrackColor: Hy.divider(dark),
              thumbColor: Colors.white,
              overlayShape: SliderComponentShape.noOverlay,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9, elevation: 2),
            ),
            child: Slider(value: v.clamp(lo, hi), min: lo, max: hi, onChanged: set),
          ),
        ),
        SizedBox(
          width: 50,
          child: Text(
            v.abs() >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(2),
            textAlign: TextAlign.right,
            style: TextStyle(color: Hy.text(dark), fontSize: Hy.subtitle, fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
      ],
    ),
  );

  Widget _chip(String l, bool on, VoidCallback onTap, bool dark) => Padding(
    padding: const EdgeInsets.only(right: 8, bottom: 8),
    child: Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: on ? Hy.primary(dark) : Hy.pressed(dark),
          borderRadius: BorderRadius.circular(Hy.rSmall),
        ),
        child: Text(
          l,
          style: TextStyle(color: on ? Colors.white : Hy.text(dark), fontSize: Hy.subtitle, fontWeight: FontWeight.w500),
        ),
      ),
    ),
  );

  Widget _toggle(String l, bool v, ValueChanged<bool> set, bool dark) => SizedBox(
    height: 44,
    child: Row(
      children: [
        Expanded(
          child: Text(l, style: TextStyle(color: Hy.text(dark), fontSize: Hy.body2)),
        ),
        HySwitch(value: v, onChanged: set),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final dark = OsScope.of(context).dark;
    final top = MediaQuery.paddingOf(context).top + 38;
    final f = _f;
    final s = _size;
    final rot = _rotation * math.pi / 180;
    final fx = GlassFx(
      hit: _hit,
      rotation: rot,
      iconRect: _icon > 0 ? (left: s.width / 2 - 60, top: s.height / 2 - 40, width: 120.0, height: 80.0) : null,
      iconStrength: _icon,
      iconMode: _dynamic ? 2 : 1,
      iconRadius: 20,
      dynamicLight: _dynamic ? _dir : null,
    );
    void set(GlassFilter g) => setState(() => _f = g);
    return Material(
      color: Hy.window(dark),
      child: LayoutBuilder(
        builder: (context, c) {
          final stage = c.maxHeight * 0.46;
          return Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: stage,
                child: HyperGlassScene(
                  background: GestureDetector(
                    onPanUpdate: (d) => setState(() {
                      _lightAt = Offset(d.localPosition.dx / c.maxWidth, d.localPosition.dy / stage);
                      _f = _f.copyWith(lightDir: _dir);
                    }),
                    child: Wallpaper(index: _wall, dark: false),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: _pos.dx,
                        top: _pos.dy,
                        width: s.width,
                        height: s.height,
                        child: GestureDetector(
                          onPanUpdate: (d) => setState(() => _pos += d.delta),
                          child: GlassPress(
                            filter: f.copyWith(alpha: _opacity),
                            radius: _radius,
                            bloom: _bloom ? const BloomStroke() : null,
                            scale: 1,
                            fx: fx,
                            mask: _mask,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _preset,
                                    style: const TextStyle(color: Colors.white, fontSize: Hy.body2, fontWeight: FontWeight.w600),
                                  ),
                                  const Text('拖动玻璃 · 拖动壁纸改光向', style: TextStyle(color: Colors.white70, fontSize: Hy.footnote)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(left: 0, right: 0, top: 0, child: const StatusBar(color: Colors.white)),
                      Positioned(
                        left: 12,
                        top: top + 8,
                        width: 40,
                        height: 40,
                        child: GlassPress(
                          radius: 20,
                          onTap: widget.onBack,
                          child: const Icon(Icons.arrow_back_ios_new, size: 18, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: stage,
                bottom: 0,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 50),
                  children: [
                    _section('ROM 预设', dark),
                    const SizedBox(height: 6),
                    Wrap(
                      children: [for (final k in GlassPresets.all.keys) _chip(k, k == _preset, () => _setPreset(k), dark)],
                    ),
                    _section('形状与背景', dark),
                    const SizedBox(height: 6),
                    Wrap(
                      children: [
                        for (final (i, l) in const ['圆角卡片', '胶囊', '圆'].indexed)
                          _chip(l, _shape == i, () => setState(() => _shape = i), dark),
                        for (final (i, l) in Wallpaper.names.indexed)
                          _chip(l, _wall == i, () => setState(() => _wall = i), dark),
                      ],
                    ),
                    _section('形状 · SDF', dark),
                    _slider('边缘宽度 edgePx', f.edgePx, 0, 120, (v) => set(f.copyWith(edgePx: v)), dark),
                    _slider('边缘曲线 edgePow', f.edgePow, 0.5, 5, (v) => set(f.copyWith(edgePow: v)), dark),
                    _slider('厚度 thickness', f.thicknessPx, 0, 240, (v) => set(f.copyWith(thicknessPx: v)), dark),
                    _section('折射与反射', dark),
                    _slider('折射率 IOR', f.refractIOR, 1, 6, (v) => set(f.copyWith(refractIOR: v)), dark),
                    _slider('反射偏移', f.reflectOffsetPx, 0, 1400, (v) => set(f.copyWith(reflectOffsetPx: v)), dark),
                    _slider('反射强度', f.reflectionStrength, 0, 3, (v) => set(f.copyWith(reflectionStrength: v)), dark),
                    _slider('反射提亮', f.reflectionLighten, 0, 4, (v) => set(f.copyWith(reflectionLighten: v)), dark),
                    _section('方向光', dark),
                    _slider('主光强度', f.lightIntensity, 0, 3, (v) => set(f.copyWith(lightIntensity: v)), dark),
                    _slider('对侧光', f.lightOpposite, 0, 3, (v) => set(f.copyWith(lightOpposite: v)), dark),
                    _slider('光角范围', f.lightAngleRange, 0.05, 1, (v) => set(f.copyWith(lightAngleRange: v)), dark),
                    _slider('底部内光', f.innerBottom, 0, 0.5, (v) => set(f.copyWith(innerBottom: v)), dark),
                    _section('色调', dark),
                    _slider('饱和度', f.saturation, 0, 3, (v) => set(f.copyWith(saturation: v)), dark),
                    _slider('亮度', f.brightness, -0.3, 0.5, (v) => set(f.copyWith(brightness: v)), dark),
                    _slider('亮度曲线量', f.luminanceAmount, 0, 1, (v) => set(f.copyWith(luminanceAmount: v)), dark),
                    _slider('暗部压制', f.darker, 0, 1, (v) => set(f.copyWith(darker: v)), dark),
                    _slider('背景饱和', f.bgColorSaturation, 0, 3, (v) => set(f.copyWith(bgColorSaturation: v)), dark),
                    _slider('背景亮度', f.bgColorBrightness, 0, 0.6, (v) => set(f.copyWith(bgColorBrightness: v)), dark),
                    _slider('内部混白', f.innerColorWhite, 0, 1, (v) => set(f.copyWith(innerColorWhite: v)), dark),
                    _slider('内部混色', f.innerColorMix, 0, 1, (v) => set(f.copyWith(innerColorMix: v)), dark),
                    _slider('烧灼 burn', f.burn, 1, 16, (v) => set(f.copyWith(burn: v)), dark),
                    _slider('颜色幂 colorPow', f.colorPow, 0.5, 2.5, (v) => set(f.copyWith(colorPow: v)), dark),
                    _slider('玻璃底色 α', f.glassColor[3], 0, 0.6, (v) {
                      set(f.copyWith(glassColor: [f.glassColor[0], f.glassColor[1], f.glassColor[2], v]));
                    }, dark),
                    _slider('去着色 unshade', f.unshade, 0, 1, (v) => set(f.copyWith(unshade: v)), dark),
                    _section('交互与动态', dark),
                    _slider('按下 uHit', _hit, 0, 1, (v) => setState(() => _hit = v), dark),
                    _slider('旋转 °', _rotation, 0, 360, (v) => setState(() => _rotation = v), dark),
                    _slider('图标光强', _icon, 0, 1, (v) => setState(() => _icon = v), dark),
                    _slider('整体透明度', _opacity, 0, 1, (v) => setState(() => _opacity = v), dark),
                    _toggle('动态光（uIconMove = 2）', _dynamic, (v) => setState(() => _dynamic = v), dark),
                    _toggle('Bloom 描边', _bloom, (v) => setState(() => _bloom = v), dark),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
