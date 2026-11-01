import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../hyper_glass.dart';
import 'theme.dart';

/// HyperOS springs are given as SpringCurveParams(damping ratio, response in seconds), like iOS.
SpringDescription hyperSpring(double damping, double response) =>
    SpringDescription.withDampingRatio(mass: 1, stiffness: math.pow(2 * math.pi / response, 2).toDouble(), ratio: damping);

/// `miuix.popupwidget.widget.ArcAnimation`, the popup of a Spinner. The size and the centre run on separate
/// springs that swap on the way out: fraction (0.8, 0.35) / (0.8, 0.22), position (0.8, 0.22) / (0.8, 0.35).
/// Alpha is linear, 50 ms in and 200 ms out; leaving, the content also blurs to 30dp over 200 ms.
class ArcMotion {
  ArcMotion(TickerProvider vsync)
    : fraction = AnimationController.unbounded(vsync: vsync),
      position = AnimationController.unbounded(vsync: vsync),
      alpha = AnimationController(vsync: vsync),
      blur = AnimationController(vsync: vsync);

  final AnimationController fraction, position, alpha, blur;
  bool open = false;

  Listenable get listenable => Listenable.merge([fraction, position, alpha, blur]);
  bool get active => open || fraction.value > 0.001 || alpha.value > 0.001;

  void set(bool value) {
    open = value;
    final sizeSpring = hyperSpring(0.8, value ? 0.35 : 0.22), moveSpring = hyperSpring(0.8, value ? 0.22 : 0.35);
    fraction.animateWith(SpringSimulation(sizeSpring, fraction.value, value ? 1 : 0, fraction.velocity));
    position.animateWith(SpringSimulation(moveSpring, position.value, value ? 1 : 0, position.velocity));
    alpha.animateTo(value ? 1 : 0, duration: Duration(milliseconds: value ? 50 : 200));
    if (value) {
      blur.value = 0;
    } else {
      blur.animateTo(1, duration: const Duration(milliseconds: 200));
    }
  }

  void dispose() {
    fraction.dispose();
    position.dispose();
    alpha.dispose();
    blur.dispose();
  }
}

/// The popup driven by [ArcMotion] (ArcAnimationScaleListener). It starts as a 5:1 bar 69% of the final width,
/// pinned to the side of [menu] that faces [anchor] (PopupView.computeGravity); the width and the aspect ratio
/// follow the fraction, the centre follows the position, and the content is scaled uniformly with the width
/// from its top left, so the bar reveals a shrunken copy of the menu rather than items flying out.
class ArcMenu extends StatelessWidget {
  const ArcMenu({
    super.key,
    required this.motion,
    required this.anchor,
    required this.menu,
    required this.items,
    required this.onDismiss,
    this.itemHeight = 44,
  });

  final ArcMotion motion;
  final Rect anchor, menu;
  final List<HyperMenuItem> items;
  final VoidCallback onDismiss;
  final double itemHeight;

  /// The menu's height for [items] rows of the default [itemHeight].
  static double heightFor(int items) => 44.0 * items + 22;

  static const _startWidth = 0.69, _startAspect = 0.2, _startRadius = 4.0, _endRadius = 24.0, _endBlur = 30.0;

  Rect get _start {
    final w = menu.width * _startWidth, h = w / 5;
    final dx = (menu.center.dx - anchor.center.dx).abs() <= 10
        ? menu.center.dx - w / 2
        : menu.center.dx > anchor.center.dx
        ? menu.left
        : menu.right - w;
    final dy = menu.center.dy <= anchor.center.dy ? menu.bottom - h : menu.top;
    return Rect.fromLTWH(dx, dy, w, h);
  }

  @override
  Widget build(BuildContext context) {
    if (!motion.active) return const SizedBox.shrink();
    final dark = HyperTheme.isDark(context);
    final primary = HyperTheme.primaryOf(context);
    final f = math.max(0.0, motion.fraction.value), p = math.max(0.0, motion.position.value);
    final start = _start;
    final width = start.width + (menu.width - start.width) * f;
    final aspect = _startAspect + (menu.height / menu.width - _startAspect) * f;
    final center = Offset.lerp(start.center, menu.center, p)!;
    final rect = Rect.fromCenter(center: center, width: width, height: aspect * width);
    final fg = dark ? Colors.white.withValues(alpha: 0.9) : Colors.black.withValues(alpha: 0.9);
    final radius = motion.open ? _startRadius + (_endRadius - _startRadius) * f.clamp(0.0, 1.0) : _endRadius;
    final sigma = _endBlur / 2 * motion.blur.value;
    // miuix_appcompat_drop_down_menu_padding_small 11, item min height 44, horizontal padding 20
    Widget content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Column(
        children: [
          for (final item in items)
            InkWell(
              onTap: item.onTap,
              child: SizedBox(
                height: itemHeight,
                child: Row(
                  children: [
                    const SizedBox(width: 20),
                    if (item.icon != null) ...[Icon(item.icon, color: fg, size: 22), const SizedBox(width: 14)],
                    Expanded(
                      child: Text(item.label, style: TextStyle(color: item.selected ? primary : fg, fontSize: 16)),
                    ),
                    if (item.selected) Icon(Icons.check, color: primary, size: 20),
                    const SizedBox(width: 20),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (sigma > 0.01)
      content = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: content,
      );
    final base = dark ? BlendMaterial.popupMenuDark : BlendMaterial.popupMenuLight;
    return Stack(
      children: [
        if (motion.open) Positioned.fill(child: GestureDetector(onTap: onDismiss)),
        // the window stays invisible until the fraction passes 0.1
        if (!motion.open || f > 0.1)
          Positioned.fromRect(
            rect: rect,
            child: // popupview-glass: ShadowToken.Regular
            ViewShadow(
              radius: radius,
              opacity: motion.alpha.value,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: HyperBlendBlur(
                  // popupview-glass: Pured_Thin_Glass, mask blur 60, Glass_Stroke_Small
                  material: BlendMaterial(sigma: 60, layers: base.layers, fallback: base.fallback),
                  borderRadius: radius,
                  opacity: motion.alpha.value,
                  bloom: dark ? BloomTokens.strokeSmallDark : BloomTokens.strokeSmallLight,
                  child: Opacity(
                    opacity: motion.alpha.value,
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      minWidth: menu.width,
                      maxWidth: menu.width,
                      minHeight: menu.height,
                      maxHeight: menu.height,
                      child: Transform.scale(alignment: Alignment.topLeft, scale: math.min(width / menu.width, 1), child: content),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class HyperMenuItem {
  const HyperMenuItem(this.label, this.onTap, {this.icon, this.selected = false});
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool selected;
}

/// Final menu rect for [anchor]: aligned with the anchor's own edge when it sits near a screen edge
/// (HyperOS puts such buttons at an edge or corner, and the menu then spreads out of that corner),
/// growing up when [growUp] (anchor near the bottom) and down otherwise, kept inside [screen].
Rect menuRectFor(Rect anchor, Size screen, double width, double height, {required bool growUp}) {
  final double left;
  if (anchor.center.dx > screen.width * 2 / 3) {
    left = anchor.right - width;
  } else if (anchor.center.dx < screen.width / 3) {
    left = anchor.left;
  } else {
    left = anchor.center.dx - width / 2;
  }
  final top = growUp ? anchor.bottom - height : anchor.top;
  return Rect.fromLTWH(
    left.clamp(12.0, screen.width - width - 12),
    top.clamp(12.0, math.max(12.0, screen.height - height - 12)),
    width,
    height,
  );
}
