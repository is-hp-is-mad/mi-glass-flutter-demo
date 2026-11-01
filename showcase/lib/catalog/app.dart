import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../hyper_glass.dart';
import '../ui/kit.dart';
import '../ui/morph_menu.dart';
import 'controls_page.dart';
import 'materials_page.dart';
import 'settings_page.dart';

/// What the pages ask of the app: everything that floats above a page lives in the outer scene.
class CatalogHost extends InheritedWidget {
  const CatalogHost({super.key, required this.app, required super.child});
  final CatalogAppState app;
  static CatalogAppState of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<CatalogHost>()!.app;
  @override
  bool updateShouldNotify(CatalogHost old) => false;
}

class CatalogApp extends StatefulWidget {
  const CatalogApp({super.key});
  @override
  State<CatalogApp> createState() => CatalogAppState();
}

class CatalogAppState extends State<CatalogApp> with TickerProviderStateMixin {
  static const _tabs = [
    ('设置', Icons.settings_outlined, Icons.settings_rounded),
    ('控件', Icons.widgets_outlined, Icons.widgets_rounded),
    ('材质', Icons.auto_awesome_outlined, Icons.auto_awesome_rounded),
  ];
  final _pages = const [SettingsPage(), ControlsPage(), MaterialsPage()];
  int _tab = 0;

  late final _detail = SpringValue(this, damping: 0.9, response: 0.4);
  Widget? _detailPage;

  late final _arc = ArcMotion(this);
  Rect _anchor = Rect.zero;
  List<String> _options = const [];
  int _selected = 0;
  ValueChanged<int>? _onPick;

  late final _dialog = SpringValue(this, damping: 0.86, response: 0.36);
  (String, String, VoidCallback?)? _dialogData;
  late final _dim = AnimationController(vsync: this);
  late final _sheet = AnimationController(vsync: this);
  late final _sheetDim = AnimationController(vsync: this);
  bool _sheetOpen = false;
  late final _toast = SpringValue(this, damping: 0.8, response: 0.34);
  String _toastText = '';
  Timer? _toastTimer;

  @override
  void dispose() {
    _detail.dispose();
    _pillLeft.dispose();
    _pillRight.dispose();
    _arc.dispose();
    _dialog.dispose();
    _dim.dispose();
    _sheet.dispose();
    _sheetDim.dispose();
    _toast.dispose();
    _toastTimer?.cancel();
    _liveTimer?.cancel();
    super.dispose();
  }

  bool _live = false;
  Timer? _liveTimer;

  void _pulse() {
    _liveTimer?.cancel();
    _liveTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _live = false);
    });
    if (!_live) setState(() => _live = true);
  }

  // OverlayView: the edge in front runs on the fast spring and the one behind on the slow one, so the pill stretches
  late final _pillLeft = SpringValue(this, value: 0);
  late final _pillRight = SpringValue(this, value: 1);

  void selectTab(int i) {
    final forward = i >= _tab;
    _pillLeft.to(i.toDouble(), damping: forward ? 0.75 : 0.7, response: forward ? 0.5 : 0.4);
    _pillRight.to(i + 1.0, damping: forward ? 0.7 : 0.75, response: forward ? 0.4 : 0.5);
    setState(() => _tab = i);
    _pulse();
  }

  void push(Widget page) {
    setState(() => _detailPage = page);
    _detail.to(1);
  }

  void pop() {
    _detail.to(0, response: 0.32);
    Future<void>.delayed(const Duration(milliseconds: 450), () {
      if (mounted && _detail.value < 0.02) setState(() => _detailPage = null);
    });
  }

  void spinner(BuildContext anchor, List<String> items, int selected, ValueChanged<int> onPick) {
    final b = anchor.findRenderObject()! as RenderBox;
    final root = context.findRenderObject()! as RenderBox;
    setState(() {
      // the Spinner is the value at the row's end: the popup opens right-aligned over it (gravity top|right)
      final row = b.localToGlobal(Offset.zero, ancestor: root) & b.size;
      _anchor = Rect.fromLTRB(row.right - 120, row.top, row.right, row.bottom);
      _options = items;
      _selected = selected;
      _onPick = onPick;
    });
    _arc.set(true);
  }

  // PopupWindowStrategy.getYInWindowAlignTop: Spinner uses gravity top, so the menu opens down from the anchor's
  // top. Only when it does not fit does it press against the bottom, or end at the anchor when the room is above.
  Rect _spinnerRect(Size screen) {
    const inset = 12.0, width = 200.0;
    final height = 44.0 * _options.length + 22;
    final x = _anchor.right - width;
    final top = _anchor.top < inset ? inset : _anchor.top;
    if (top + height < screen.height - inset) return Rect.fromLTWH(x, top, width, height);
    if (screen.height - _anchor.top >= _anchor.top) return Rect.fromLTWH(x, screen.height - inset - height, width, height);
    return Rect.fromLTWH(x, _anchor.top - height, width, height);
  }

  void _closeSpinner() {
    _arc.set(false);
    setState(() {});
  }

  void dialog(String title, String message, {VoidCallback? onOk}) {
    setState(() => _dialogData = (title, message, onOk));
    _dialog.to(1, damping: 0.82, response: 0.3); // PhoneDialogAnim
    _dim.animateTo(1, duration: const Duration(milliseconds: 350), curve: const Decelerate(1.5));
  }

  void _closeDialog() {
    _dialog.c.animateTo(0, duration: const Duration(milliseconds: 200), curve: const Decelerate(1.5));
    _dim.animateTo(0, duration: const Duration(milliseconds: 300), curve: const Decelerate(1.5)).whenComplete(() {
      if (mounted && _dim.value == 0) setState(() => _dialogData = null);
    });
  }

  // miuix_bottom_sheet_slide_in/out: 150ms, 20% of the screen and alpha
  void sheet() {
    setState(() => _sheetOpen = true);
    _sheet.animateTo(1, duration: const Duration(milliseconds: 150), curve: const Cubic(0.4, 0, 1, 1));
    _sheetDim.animateTo(1, duration: const Duration(milliseconds: 350), curve: const Decelerate(1.5));
  }

  void _closeSheet() {
    _sheet.animateTo(0, duration: const Duration(milliseconds: 150), curve: Curves.fastOutSlowIn);
    _sheetDim.animateTo(0, duration: const Duration(milliseconds: 300), curve: const Decelerate(1.5)).whenComplete(() {
      if (mounted && _sheetDim.value == 0) setState(() => _sheetOpen = false);
    });
  }

  void toast(String text) {
    setState(() => _toastText = text);
    _toast.to(1);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(milliseconds: 1800), () => _toast.to(0));
  }

  // miuix.bottomnavigation.BottomNavigator, as in Clock, Notes, Files, Themes and Calendar: internal-pured-thin-glass,
  // black labels whether selected or not, and a grey pill inset 3dp that marks the current tab. The icon also turns
  // solid. Selecting is not a colour change, which is the Gallery's own design.
  Widget _bottomBar(bool dark) => FloatSurface(
    radius: 28,
    child: LayoutBuilder(
      builder: (context, c) {
        final item = (c.maxWidth - 6) / _tabs.length;
        return Stack(
          children: [
            AnimatedBuilder(
              animation: Listenable.merge([_pillLeft.c, _pillRight.c]),
              builder: (_, _) {
                final left = 3 + _pillLeft.value * item, right = 3 + _pillRight.value * item;
                return Positioned(
                  left: left,
                  top: 3,
                  bottom: 3,
                  width: right - left,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: dark ? const Color(0x1fffffff) : const Color(0x0f000000),
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                );
              },
            ),
            Row(
              children: [
                const SizedBox(width: 3),
                for (final (i, (l, outline, solid)) in _tabs.indexed)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => selectTab(i),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(i == _tab ? solid : outline, size: 26, color: Hy.text(dark)),
                          Text(
                            l,
                            style: TextStyle(color: Hy.text(dark), fontSize: Hy.footnote, height: 1.2),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(width: 3),
              ],
            ),
          ],
        );
      },
    ),
  );

  Widget _dialogLayer(BoxConstraints c, bool dark) {
    final d = _dialogData;
    if (d == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: Listenable.merge([_dialog.c, _dim]),
      builder: (_, _) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeDialog,
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.3 * _dim.value)),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 24 - (1 - _dialog.value) * 260,
              height: 216,
              child: SizedBox.expand(
                // dialog-default has no ShadowToken
                child: HyperBlendBlur(
                  // dialog-default: Pured_Thin / Pured_Regular with mask blur 100, Glass_Stroke_Big
                  material: BlendMaterial(sigma: 100, layers: BlendMaterial.popupMenuLight.layers, fallback: Hy.card(dark)),
                  borderRadius: Hy.rBig,
                  bloom: dark ? BloomTokens.strokeSmallLight : BloomTokens.strokeBigLight,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
                    child: Column(
                      children: [
                        Text(
                          d.$1,
                          style: TextStyle(color: Hy.text(dark), fontSize: Hy.title4, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: Text(
                            d.$2,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Hy.sub(dark), fontSize: Hy.body1, height: 1.45),
                          ),
                        ),
                        Row(
                          children: [
                            Expanded(child: _dialogButton('取消', false, dark, _closeDialog)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _dialogButton('确定', true, dark, () {
                                d.$3?.call();
                                _closeDialog();
                              }),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _dialogButton(String l, bool primary, bool dark, VoidCallback onTap) => Pressable(
    onTap: onTap,
    child: Container(
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        color: primary ? Hy.primary(dark) : (dark ? const Color(0x1fffffff) : const Color(0x14000000)),
      ),
      child: Text(
        l,
        style: TextStyle(color: primary ? Colors.white : Hy.text(dark), fontSize: 17, fontWeight: FontWeight.w500),
      ),
    ),
  );

  Widget _sheetLayer(BoxConstraints c, bool dark) {
    if (!_sheetOpen) return const SizedBox.shrink();
    const h = 300.0;
    return AnimatedBuilder(
      animation: Listenable.merge([_sheet, _sheetDim]),
      builder: (_, _) {
        final t = _sheet.value;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeSheet,
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.3 * _sheetDim.value)),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: -(1 - t) * c.maxHeight * 0.2,
              height: h,
              child: Opacity(
                opacity: t,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Hy.card(dark),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(Hy.rBig)),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(color: Hy.hint(dark), borderRadius: BorderRadius.circular(2)),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '分享到',
                        style: TextStyle(color: Hy.text(dark), fontSize: Hy.title4, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          for (final (l, i, col) in const [
                            ('消息', Icons.chat_bubble_rounded, Color(0xff1a8fe8)),
                            ('邮件', Icons.mail_rounded, Color(0xff3b6ff0)),
                            ('收藏', Icons.star_rounded, Color(0xffff9f1a)),
                            ('更多', Icons.more_horiz_rounded, Color(0xff7b8494)),
                          ])
                            Pressable(
                              onTap: _closeSheet,
                              child: Column(
                                children: [
                                  AppGlyph(icon: i, colors: [col, col], size: 54),
                                  const SizedBox(height: 6),
                                  Text(
                                    l,
                                    style: TextStyle(color: Hy.sub(dark), fontSize: Hy.subtitle),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                        child: SizedBox(width: double.infinity, child: _dialogButton('取消', false, dark, _closeSheet)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = OsScope.of(context).dark;
    return CatalogHost(
      app: this,
      child: Scaffold(
        backgroundColor: Hy.window(dark),
        body: NotificationListener<ScrollNotification>(
          onNotification: (_) {
            _pulse();
            return false;
          },
          child: LayoutBuilder(
            builder: (context, c) => AnimatedBuilder(
              animation: Listenable.merge([_detail.c, _arc.listenable]),
              builder: (context, _) {
                final d = _detail.value;
                return HyperGlassScene(
                  animate: _live,
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      // the page underneath drifts left and dims (inferred from the system transition)
                      Transform.translate(
                        offset: Offset(-0.25 * c.maxWidth * d.clamp(0.0, 1.0), 0),
                        child: IndexedStack(index: _tab, sizing: StackFit.expand, children: _pages),
                      ),
                      if (d > 0.002)
                        IgnorePointer(
                          child: ColoredBox(color: Colors.black.withValues(alpha: 0.2 * d.clamp(0.0, 1.0))),
                        ),
                      if (_detailPage != null)
                        Positioned(left: (1 - d) * c.maxWidth, top: 0, width: c.maxWidth, height: c.maxHeight, child: _detailPage!),
                    ],
                  ),
                  child: Stack(
                    children: [
                      if (d < 0.98)
                        // BottomNavigatorLayoutHelper: 24dp from the edges, at most 344dp wide, 24dp above the bottom
                        Positioned(
                          left: (c.maxWidth - math.min(c.maxWidth - 48, 344)) / 2,
                          width: math.min(c.maxWidth - 48, 344),
                          bottom: 24 - d * 100,
                          height: 56,
                          child: _bottomBar(dark),
                        ),
                      AnimatedBuilder(
                        animation: _toast.c,
                        builder: (_, _) {
                          final t = _toast.value.clamp(0.0, 1.0);
                          if (t < 0.01) return const SizedBox.shrink();
                          return Positioned(
                            left: 0,
                            right: 0,
                            bottom: 80 + t * 22,
                            height: 44,
                            child: Center(
                              child: Opacity(
                                opacity: t,
                                child: SizedBox(
                                  width: 40.0 + _toastText.length * 15,
                                  child: FloatSurface(
                                    radius: 22,
                                    child: Center(
                                      child: Text(
                                        _toastText,
                                        style: TextStyle(color: Hy.text(dark), fontSize: Hy.body2),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      ArcMenu(
                        motion: _arc,
                        anchor: _anchor,
                        menu: _spinnerRect(c.biggest),
                        dark: dark,
                        items: [
                          for (final (i, n) in _options.indexed)
                            MorphMenuItem(n, () {
                              _onPick?.call(i);
                              _closeSpinner();
                            }, selected: i == _selected),
                        ],
                        onDismiss: _closeSpinner,
                      ),
                      _sheetLayer(c, dark),
                      _dialogLayer(c, dark),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
