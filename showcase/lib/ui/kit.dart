import 'package:flutter/material.dart';

export 'package:hyper_glass/hyper_glass.dart';
export 'package:hyper_glass/hyper_ui.dart';

/// App-wide switches the showcase's Settings can flip.
class Os extends ChangeNotifier {
  bool dark = false;
  bool animatedWallpaper = true;
  bool bloom = true;
  int wallpaper = 0;

  void setDark(bool v) {
    dark = v;
    notifyListeners();
  }

  void update(void Function() f) {
    f();
    notifyListeners();
  }
}

class OsScope extends InheritedNotifier<Os> {
  const OsScope({super.key, required Os os, required super.child}) : super(notifier: os);
  static Os of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<OsScope>()!.notifier!;
}

class StatusBar extends StatelessWidget {
  const StatusBar({super.key, required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 38,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(26, 10, 22, 0),
      child: Row(
        children: [
          Text(
            '10:24',
            style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Icon(Icons.signal_cellular_alt, size: 15, color: color),
          const SizedBox(width: 5),
          Icon(Icons.wifi, size: 15, color: color),
          const SizedBox(width: 5),
          Icon(Icons.battery_5_bar, size: 17, color: color),
        ],
      ),
    ),
  );
}

/// Launcher icon: HyperOS squircle radius is 26.5% of the size; art is procedural, not Xiaomi's assets.
class AppGlyph extends StatelessWidget {
  const AppGlyph({super.key, required this.icon, required this.colors, this.size = 58, this.iconColor = Colors.white});
  final IconData icon;
  final List<Color> colors;
  final double size;
  final Color iconColor;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(size * 0.265),
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
    ),
    child: Icon(icon, color: iconColor, size: size * 0.54),
  );
}
