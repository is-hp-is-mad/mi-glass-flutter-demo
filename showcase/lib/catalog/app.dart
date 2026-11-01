import 'package:flutter/material.dart';

import '../ui/kit.dart';
import 'controls_page.dart';
import 'materials_page.dart';
import 'settings_page.dart';

/// What the pages ask of the app: moving between pages. Popups come from [HyperOverlay].
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
    HyperBottomBarItem('设置', Icons.settings_outlined, Icons.settings_rounded),
    HyperBottomBarItem('控件', Icons.widgets_outlined, Icons.widgets_rounded),
    HyperBottomBarItem('材质', Icons.auto_awesome_outlined, Icons.auto_awesome_rounded),
  ];
  final _pages = const [SettingsPage(), ControlsPage(), MaterialsPage()];
  int _tab = 0;

  final _overlay = GlobalKey<HyperOverlayState>();
  HyperOverlayState get overlay => _overlay.currentState!;

  late final _detail = SpringValue(this, damping: 0.9, response: 0.4);
  Widget? _detailPage;

  @override
  void initState() {
    super.initState();
    _detail.c.addListener(() => overlay.refresh());
  }

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  void selectTab(int i) {
    setState(() => _tab = i);
    overlay.refresh();
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

  @override
  Widget build(BuildContext context) {
    final dark = HyperTheme.isDark(context);
    return CatalogHost(
      app: this,
      child: Scaffold(
        backgroundColor: Hy.window(dark),
        body: HyperOverlay(
          key: _overlay,
          floating: AnimatedBuilder(
            animation: _detail.c,
            builder: (_, child) {
              final d = _detail.value;
              if (d >= 0.98) return const SizedBox.shrink();
              return Transform.translate(offset: Offset(0, d * 100), child: child);
            },
            child: HyperBottomBar(items: _tabs, index: _tab, onChanged: selectTab),
          ),
          child: LayoutBuilder(
            builder: (context, c) => AnimatedBuilder(
              animation: _detail.c,
              builder: (context, _) {
                final d = _detail.value;
                return Stack(
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
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
