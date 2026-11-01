import 'package:flutter/material.dart';

import '../ui/kit.dart';

/// A [HyperPage] under the simulated status bar.
class PageScaffold extends StatelessWidget {
  const PageScaffold({super.key, required this.title, required this.children, this.onBack, this.bottomPadding = 120});
  final String title;
  final List<Widget> children;
  final VoidCallback? onBack;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) => HyperPage(
    title: title,
    onBack: onBack,
    bottomPadding: bottomPadding,
    top: MediaQuery.paddingOf(context).top + 38,
    overlay: Positioned(left: 0, right: 0, top: 0, child: StatusBar(color: Hy.text(HyperTheme.isDark(context)))),
    children: children,
  );
}
