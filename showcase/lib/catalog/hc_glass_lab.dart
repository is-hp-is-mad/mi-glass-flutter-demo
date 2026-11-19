import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../ui/kit.dart';

const _channel = MethodChannel('hyper_glass/hc_lab');
const _viewType = 'hyper_glass/hc_glass';

/// 实验：小米原生柔光玻璃（ROM `View.setMiGlass`）能否透出 Flutter 实际画面。
///
/// 背景是 Flutter 画的漂移光斑与文字；玻璃是透明的原生 View，ROM 在它身后的内容上画材质；
/// 卡片上的文字仍由 Flutter 画在玻璃之上。可切 Hybrid Composition / TLHC 对照，下方卡片可拖动以检查跟手。
class HcGlassLab extends StatefulWidget {
  const HcGlassLab({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  State<HcGlassLab> createState() => _HcGlassLabState();
}

class _HcGlassLabState extends State<HcGlassLab> with SingleTickerProviderStateMixin {
  late final AnimationController _drift = AnimationController(vsync: this, duration: const Duration(seconds: 12))
    ..repeat();

  static final _presets = <(String, GlassFilter)>[
    ('通用大卡', GlassTokens.commonLargeRegular),
    ('着色紫', GlassTokens.tintPurple),
    ('着色蓝', GlassTokens.tintBlue),
    ('仿生玻璃', GlassTokens.bionicMediumRegular),
  ];

  bool _hybrid = true;
  bool _blend = false;
  bool _animate = true;
  bool _outline = false;
  bool _scaleBlur = false;
  int _preset = 0;
  Offset _drag = const Offset(40, 0);
  Map<String, Object?> _diag = const {};

  static int _nextKey = 1000;
  final int _mainKey = _nextKey++;
  final int _dragKey = _nextKey++;

  @override
  void initState() {
    super.initState();
    _refreshDiagLater();
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  void _refreshDiagLater() {
    Future<void>.delayed(const Duration(milliseconds: 800), _refreshDiag);
  }

  Future<void> _refreshDiag() async {
    if (!mounted || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final map = await _channel.invokeMapMethod<String, Object?>('diag', {'surfaceKey': _mainKey});
      if (mounted && map != null) setState(() => _diag = map);
    } on PlatformException catch (e) {
      if (mounted) setState(() => _diag = {'error': e.message});
    }
  }

  void _set(VoidCallback f) {
    setState(f);
    _refreshDiagLater();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final filter = _presets[_preset].$2;
    final material = Hy.thinGlass(false);
    return Material(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final dragTop = top + 250.0;
          final drag = Offset(
            _drag.dx.clamp(0, math.max(0, size.width - 240)),
            _drag.dy.clamp(0, math.max(0, size.height * 0.45 - dragTop)),
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              AnimatedBuilder(
                animation: _drift,
                builder: (_, _) => CustomPaint(painter: _Backdrop(_animate ? _drift.value : 0)),
              ),
              // 主卡片：固定位置
              Positioned(
                left: 16,
                right: 16,
                top: top + 64,
                height: 150,
                child: _HcSurface(
                  key: ValueKey('main-$_hybrid'),
                  surfaceKey: _mainKey,
                  hybrid: _hybrid,
                  params: _params(_mainKey, filter, material, radius: 28),
                  child: _CardLabel(
                    title: _blend ? '混色模糊 · ROM 原生' : '柔光玻璃 · ROM 原生',
                    subtitle: '${_hybrid ? 'Hybrid Composition' : 'TLHC 纹理'} · ${_presets[_preset].$1}',
                  ),
                ),
              ),
              // 可拖动的胶囊：检查玻璃是否跟手、是否慢一帧
              Positioned(
                left: 16 + drag.dx,
                top: dragTop + drag.dy,
                width: 220,
                height: 72,
                child: GestureDetector(
                  onPanUpdate: (d) => setState(() => _drag += d.delta),
                  child: _HcSurface(
                    key: ValueKey('drag-$_hybrid'),
                    surfaceKey: _dragKey,
                    hybrid: _hybrid,
                    params: _params(_dragKey, filter, material, radius: 36),
                    child: const Center(
                      child: Text(
                        '拖我 · 看是否跟手',
                        style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 8,
                top: top + 8,
                child: IconButton(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                ),
              ),
              Positioned(
                left: 60,
                top: top + 20,
                child: const Text(
                  '原生玻璃 · HC 实验',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              Positioned(left: 0, right: 0, bottom: 0, height: size.height * 0.45, child: _panel()),
            ],
          );
        },
      ),
    );
  }

  Map<String, Object?> _params(int key, GlassFilter filter, BlendMaterial material, {required double radius}) => {
    'surfaceKey': key,
    'borderRadius': radius,
    'outline': _outline,
    if (_blend) ...{
      'mode': 'blend',
      'blurRadius': material.sigma.round(),
      'blendColors': Int32List.fromList([for (final l in material.layers) l.color.toARGB32()]),
      'blendModes': Int32List.fromList([for (final l in material.layers) HyperNativeRom.toMiBlendMode(l.mode)]),
    } else ...{
      'mode': 'glass',
      'glassParams': HyperNativeRom.packGlassToken(filter),
      'smallBlur': filter.baseBlur.round(),
      'bigBlur': filter.refractBlur.round(),
      'scaleBlurByDensity': _scaleBlur,
    },
  };

  Widget _panel() {
    Widget seg<T>(String label, List<(T, String)> items, T value, void Function(T) on) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(width: 64, child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13))),
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final (v, t) in items)
                  ChoiceChip(
                    label: Text(t, style: const TextStyle(fontSize: 12)),
                    selected: v == value,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => on(v),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    final diagLines = [
      for (final e in _diag.entries) '${e.key}: ${e.value}',
    ].join('\n');

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: Color(0xF0141418),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: [
          seg('合成', const [(true, 'Hybrid Composition'), (false, 'TLHC 对照')], _hybrid, (v) => _set(() => _hybrid = v)),
          seg('材质', const [(false, '柔光玻璃'), (true, '混色模糊')], _blend, (v) => _set(() => _blend = v)),
          seg('预设', [for (final (i, p) in _presets.indexed) (i, p.$1)], _preset, (v) => _set(() => _preset = v)),
          seg('模糊半径', const [(false, '原值'), (true, '× density')], _scaleBlur, (v) => _set(() => _scaleBlur = v)),
          seg('背景动画', const [(true, '开'), (false, '停')], _animate, (v) => setState(() => _animate = v)),
          seg('描边', const [(false, '关'), (true, '显示 View 边界')], _outline, (v) => _set(() => _outline = v)),
          Row(
            children: [
              const Text('诊断', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(onPressed: _refreshDiag, child: const Text('刷新')),
              TextButton(
                onPressed: () => Clipboard.setData(ClipboardData(text: diagLines)),
                child: const Text('复制'),
              ),
            ],
          ),
          SelectableText(
            diagLines.isEmpty ? '（等待原生回报…）' : diagLines,
            style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.4, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}

/// 卡片上由 Flutter 画的内容（应当显示在玻璃之上）。
class _CardLabel extends StatelessWidget {
  const _CardLabel({required this.title, required this.subtitle});
  final String title, subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 26),
        const Spacer(),
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    ),
  );
}

/// 透明原生 View（ROM 材质）+ 其上的 Flutter 内容。
class _HcSurface extends StatefulWidget {
  const _HcSurface({
    super.key,
    required this.surfaceKey,
    required this.hybrid,
    required this.params,
    required this.child,
  });

  final int surfaceKey;
  final bool hybrid;
  final Map<String, Object?> params;
  final Widget child;

  @override
  State<_HcSurface> createState() => _HcSurfaceState();
}

class _HcSurfaceState extends State<_HcSurface> {
  @override
  void didUpdateWidget(_HcSurface old) {
    super.didUpdateWidget(old);
    if (defaultTargetPlatform == TargetPlatform.android && !mapEquals(old.params, widget.params)) {
      _channel.invokeMethod<void>('update', widget.params);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0x33FFFFFF), child: Center(child: Text('仅 Android'))),
          widget.child,
        ],
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        PlatformViewLink(
          viewType: _viewType,
          surfaceFactory: (context, controller) => AndroidViewSurface(
            controller: controller as AndroidViewController,
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
            hitTestBehavior: PlatformViewHitTestBehavior.transparent,
          ),
          onCreatePlatformView: (params) {
            final controller = widget.hybrid
                ? PlatformViewsService.initExpensiveAndroidView(
                    id: params.id,
                    viewType: _viewType,
                    layoutDirection: TextDirection.ltr,
                    creationParams: widget.params,
                    creationParamsCodec: const StandardMessageCodec(),
                    onFocus: () => params.onFocusChanged(true),
                  )
                : PlatformViewsService.initSurfaceAndroidView(
                    id: params.id,
                    viewType: _viewType,
                    layoutDirection: TextDirection.ltr,
                    creationParams: widget.params,
                    creationParamsCodec: const StandardMessageCodec(),
                    onFocus: () => params.onFocusChanged(true),
                  );
            return controller
              ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
              ..create();
          },
        ),
        IgnorePointer(child: widget.child),
      ],
    );
  }
}

/// Flutter 画的背景：漂移的彩色光斑 + 细条纹 + 大字，模糊与折射一眼可见。
class _Backdrop extends CustomPainter {
  const _Backdrop(this.t);
  final double t;

  static const _blobs = [
    (Color(0xFF2B64D8), 0.95, 0.0),
    (Color(0xFFFF6F91), 0.80, 2.1),
    (Color(0xFFFFB37E), 0.75, 4.2),
    (Color(0xFF1FBF8F), 0.70, 1.0),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF101828));
    final a = t * 2 * math.pi;
    for (final (i, (color, r, phase)) in _blobs.indexed) {
      final c = Offset(
        size.width * (0.2 + 0.2 * i + 0.18 * math.cos(a + phase)),
        size.height * (0.25 + 0.12 * i + 0.1 * math.sin(a * (i.isEven ? 1 : -1) + phase)),
      );
      final radius = size.shortestSide * r * 0.6;
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: c, radius: radius)),
      );
    }
    final stripe = Paint()
      ..color = const Color(0x33FFFFFF)
      ..strokeWidth = 2;
    final shift = (t * 48) % 24;
    for (var x = -size.height; x < size.width; x += 24) {
      canvas.drawLine(Offset(x + shift, size.height * 0.55), Offset(x + shift + size.height * 0.55, 0), stripe);
    }
    for (var row = 0; row < 4; row++) {
      final tp = TextPainter(
        text: const TextSpan(
          text: 'FLUTTER 画面 HYPER',
          style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 34, fontWeight: FontWeight.w900),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-60 + (t * 120 + row * 70) % 120, 60.0 + row * 70));
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(_Backdrop old) => old.t != t;
}
