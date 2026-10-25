import 'package:flutter/material.dart';

import '../hyper_glass.dart';
import 'morph_menu.dart';
import 'sky.dart';
import 'units.dart';

/// HyperOS-style settings page on the soft-glass background.
///
/// * Large title in the list; once it scrolls away a small title fades into the bar.
/// * The bar is plain while the page rests at the top. As soon as content scrolls under it, the bar
///   becomes "floating": a gradient-blur mask fades in behind it (MIUIWeather's gradientBlur alpha
///   stops) and the back button grows a round glass background, since it now floats over content.
/// * Option rows open a [MorphMenu] that grows out of the tapped value, exactly like the button menu.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  /// HyperOS push: the page slides in from the right while the previous one drifts left.
  static Route<void> route({Key? key}) => PageRouteBuilder<void>(
    transitionDuration: const Duration(milliseconds: 450),
    reverseTransitionDuration: const Duration(milliseconds: 380),
    pageBuilder: (_, _, _) => SettingsPage(key: key),
    transitionsBuilder: (_, animation, _, child) => SlideTransition(
      position: Tween(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)),
      child: child,
    ),
  );

  @override
  State<SettingsPage> createState() => SettingsPageState();
}

class SettingsPageState extends State<SettingsPage> with TickerProviderStateMixin {
  final _scroll = ScrollController();
  double _offset = 0;
  late final _options = PopupMotion(this);
  Rect _anchor = Rect.zero;
  final _unitKey = GlobalKey();

  static const _barHeight = 56.0;

  // MIUIWeather gradientBlur mask: alpha stops (pp+0x2bc00) at positions (pp+0x2bc08), top to bottom.
  static const _maskAlpha = [1.0, 0.98, 0.8, 0.5, 0.0];
  static const _maskStops = [0.0, 0.52, 0.74, 0.85, 1.0];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => setState(() => _offset = _scroll.offset));
  }

  @override
  void dispose() {
    _scroll.dispose();
    _options.dispose();
    super.dispose();
  }

  /// Used by the CI capture script.
  void scrollTo(double offset) =>
      _scroll.animateTo(offset, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
  void setOptions(bool open) => _setOptions(open);

  void _setOptions(bool open) {
    if (open) {
      final box = _unitKey.currentContext!.findRenderObject()! as RenderBox;
      _anchor = box.localToGlobal(Offset.zero) & box.size;
    }
    _options.set(open);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final top = MediaQuery.paddingOf(context).top;
    final floating = _offset > 0.5; // content has scrolled under the bar
    final titleT = ((_offset - 24) / 32).clamp(0.0, 1.0); // large title leaving -> small title in
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, c) {
          final page = HyperGlassScene(
            background: ValueListenableBuilder(
              valueListenable: TemperatureUnit.fahrenheit,
              builder: (_, _, _) => Sky(dark: dark, label: TemperatureUnit.format(23)),
            ),
            child: _list(top, titleT),
          );
          return AnimatedBuilder(
            animation: _options.listenable,
            builder: (context, _) => HyperGlassScene(
              animate: floating || _options.active,
              background: page,
              child: Stack(
                children: [
                  _barMask(top, floating),
                  Positioned(
                    top: top,
                    left: 64,
                    right: 64,
                    height: _barHeight,
                    child: IgnorePointer(
                      child: Center(
                        child: Opacity(
                          opacity: titleT,
                          child: const Text(
                            '设置',
                            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _backButton(top, floating),
                  _optionsMenu(c, dark),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _list(double top, double titleT) {
    const white = TextStyle(color: Colors.white);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: ListView(
          controller: _scroll,
          padding: EdgeInsets.fromLTRB(16, top + _barHeight, 16, 40),
          children: [
            Opacity(
              opacity: 1 - titleT,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                child: Text('设置', style: white.copyWith(fontSize: 32, fontWeight: FontWeight.w600)),
              ),
            ),
            _section('单位', [
              ValueListenableBuilder(
                valueListenable: TemperatureUnit.fahrenheit,
                builder: (_, _, _) =>
                    _row('温度单位', TemperatureUnit.label, valueKey: _unitKey, onTap: () => _setOptions(true)),
              ),
              _row('风速单位', '公里/小时'),
              _row('气压单位', '百帕'),
            ]),
            _section('通知', [_row('降雨提醒', '已开启'), _row('灾害预警', '已开启'), _row('每日天气', '07:30')]),
            _section('其他', [_row('数据来源', '示例数据'), _row('用户协议', ''), _row('隐私政策', ''), _row('版本', '1.0.0')]),
            const SizedBox(height: 480),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> rows) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ),
        HyperGlass(
          borderRadius: 24,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(children: rows),
          ),
        ),
      ],
    ),
  );

  Widget _row(String label, String value, {Key? valueKey, VoidCallback? onTap}) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: SizedBox(
      height: 58,
      child: Row(
        children: [
          const SizedBox(width: 20),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
          Row(
            key: valueKey,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value, style: const TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(width: 4),
              Icon(onTap != null ? Icons.unfold_more : Icons.chevron_right, color: Colors.white54, size: 20),
            ],
          ),
          const SizedBox(width: 16),
        ],
      ),
    ),
  );

  /// Floating bar: blur behind the bar, faded out downwards by the gradientBlur alpha stops.
  Widget _barMask(double top, bool floating) => Positioned(
    top: 0,
    left: 0,
    right: 0,
    height: top + _barHeight + 28,
    child: IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: floating ? 1 : 0),
        duration: const Duration(milliseconds: 220),
        builder: (context, v, _) {
          if (v <= 0.001) return const SizedBox.shrink();
          final dark = Theme.of(context).brightness == Brightness.dark;
          return ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (r) => LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [for (final a in _maskAlpha) Colors.white.withValues(alpha: a)],
              stops: _maskStops,
            ).createShader(r),
            child: HyperBlendBlur(
              material: dark ? BlendMaterial.appBarDark : BlendMaterial.appBarLight,
              borderRadius: 0,
              opacity: v,
            ),
          );
        },
      ),
    ),
  );

  /// Back button: just the arrow at rest; a round glass background appears while the bar floats.
  Widget _backButton(double top, bool floating) => Positioned(
    left: 12,
    top: top + 8,
    width: 40,
    height: 40,
    child: GestureDetector(
      onTap: () => Navigator.of(context).maybePop(),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: floating ? 1 : 0),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        builder: (context, v, child) => Stack(
          fit: StackFit.expand,
          children: [
            if (v > 0.001)
              Transform.scale(
                scale: 0.8 + 0.2 * v,
                child: HyperGlass(borderRadius: 20, opacity: v),
              ),
            child!,
          ],
        ),
        child: const Center(child: Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20)),
      ),
    ),
  );

  Widget _optionsMenu(BoxConstraints c, bool dark) {
    final f = TemperatureUnit.fahrenheit;
    void pick(bool fahrenheit) {
      f.value = fahrenheit;
      _setOptions(false);
    }

    final items = [
      MorphMenuItem('摄氏度 °C', () => pick(false), selected: !f.value),
      MorphMenuItem('华氏度 °F', () => pick(true), selected: f.value),
    ];
    const itemH = 52.0, width = 200.0;
    final screen = c.biggest;
    final menu = menuRectFor(
      _anchor,
      screen,
      width,
      itemH * items.length + 16,
      growUp: _anchor.center.dy > screen.height * 0.6,
    );
    return MorphMenu(
      motion: _options,
      anchor: _anchor,
      menu: menu,
      dark: dark,
      items: items,
      itemHeight: itemH,
      anchorRadius: 12,
      onDismiss: () => _setOptions(false),
    );
  }
}
