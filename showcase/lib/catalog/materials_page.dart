import 'package:flutter/material.dart';

import '../hyper_glass.dart';
import '../screens/gallery.dart';
import '../screens/lab.dart';
import '../screens/traits.dart';
import '../screens/weather.dart';
import '../ui/art.dart';
import '../ui/kit.dart';
import 'app.dart';
import 'widgets.dart';

/// Glass and blend materials over pictures, where they belong: page chrome stays on the plain pages.
class MaterialsPage extends StatefulWidget {
  const MaterialsPage({super.key});
  @override
  State<MaterialsPage> createState() => _MaterialsPageState();
}

class _MaterialsPageState extends State<MaterialsPage> {
  int _group = 0;

  static const _groups = ['通用', '仿生', '着色'];

  Map<String, GlassFilter> get _tokens => {
    for (final e in GlassTokens.all.entries)
      if (e.key.startsWith(const ['Common', 'Bionic', 'Tint'][_group])) e.key: e.value,
  };

  @override
  Widget build(BuildContext context) {
    final dark = OsScope.of(context).dark;
    final host = CatalogHost.of(context);
    return PageScaffold(
      title: '材质',
      children: [
        const PrefCategory('系统样张'),
        const _Sample(),
        const PrefCategory('玻璃令牌 · GlassToken'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: HySegmented(items: _groups, index: _group, onChanged: (i) => setState(() => _group = i)),
        ),
        LayoutBuilder(
          builder: (context, c) {
            final tokens = _tokens;
            final cell = (c.maxWidth - 32 - 28 - 12) / 2 / 1.9;
            final rows = (tokens.length + 1) ~/ 2;
            return _Picture(
              key: ValueKey(_group), // a fresh scene per group, so only one group's textures are alive
              keepAlive: false, // up to 15 multi-pass filters: not worth holding once scrolled away
              wallpaper: const [2, 3, 1][_group],
              height: 28 + rows * cell + (rows - 1) * 12,
              child: GridView.count(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(14),
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.9,
                children: [
                  for (final e in tokens.entries)
                    HyperGlass(
                      filter: e.value,
                      borderRadius: Hy.rCommon,
                      bloom: BloomTokens.strokeMiddleLight,
                      child: Center(
                        child: Text(
                          e.key.replaceAll('_', ' '),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: e.value.glassColor[0] > 0.5 && e.value.glassColor[3] >= 0.5 ? const Color(0xe6000000) : Colors.white,
                            fontSize: Hy.subtitle,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        const PrefCategory('混色模糊 · ColorBlend'),
        _Picture(
          wallpaper: 0,
          height: 28.0 + 72 * BlendPresets.all.length,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                for (final e in BlendPresets.all.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SizedBox(
                      height: 62,
                      child: HyperBlendBlur(
                        material: dark ? e.value.$2 : e.value.$1,
                        borderRadius: Hy.rCommon,
                        child: Center(
                          child: Text(
                            e.key,
                            style: TextStyle(
                              color: e.key == '强调色' || dark ? Colors.white : const Color(0xe6000000),
                              fontSize: Hy.body2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const PrefCategory('更多'),
        PrefCard(
          children: [
            PrefRow(
              '玻璃实验室',
              summary: '全部参数实时调节',
              icon: Icons.science_rounded,
              color: const Color(0xff5a48e6),
              onTap: () => host.push(LabApp(onBack: host.pop)),
            ),
            PrefRow(
              '特性图鉴',
              summary: '每项特性的开关对照',
              icon: Icons.auto_awesome_rounded,
              color: const Color(0xffff5a7d),
              onTap: () => host.push(TraitsApp(onBack: host.pop)),
            ),
            PrefRow(
              '相册示例',
              icon: Icons.filter_vintage_rounded,
              color: const Color(0xffff7a59),
              onTap: () => host.push(GalleryApp(onBack: host.pop)),
            ),
            PrefRow(
              '天气示例',
              icon: Icons.wb_sunny_rounded,
              color: const Color(0xff2f7bff),
              onTap: () => host.push(WeatherApp(onBack: host.pop)),
            ),
          ],
        ),
      ],
    );
  }
}

/// A picture with its own scene, for surfaces that need something to refract.
class _Picture extends StatefulWidget {
  const _Picture({super.key, required this.wallpaper, required this.height, required this.child, this.keepAlive = true});
  final bool keepAlive;
  final int wallpaper;
  final double height;
  final Widget child;
  @override
  State<_Picture> createState() => _PictureState();
}

// kept alive: a scene rebuilt on the way back into view would show its glass a frame late
class _PictureState extends State<_Picture> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.keepAlive;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Hy.rDemiBig),
        child: SizedBox(
          height: widget.height,
          child: HyperGlassScene(
            animate: false,
            background: Wallpaper(index: widget.wallpaper, dark: false, animate: false),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// The two surfaces of Xiaomi's OS4 design sheet: a media card and the dialer's keys.
class _Sample extends StatefulWidget {
  const _Sample();
  @override
  State<_Sample> createState() => _SampleState();
}

class _SampleState extends State<_Sample> {
  bool _playing = true;

  Widget _key(String d, String l) => SizedBox(
    width: 64,
    height: 64,
    child: GlassPress(
      filter: GlassPresets.notification,
      radius: 32,
      scale: 0.92,
      bloom: BloomTokens.strokeMiddleLight,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            d,
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w500, height: 1.1),
          ),
          if (l.isNotEmpty) Text(l, style: const TextStyle(color: Colors.white70, fontSize: 9)),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => _Picture(
    wallpaper: 1,
    height: 336,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          SizedBox(
            height: 132,
            child: GlassPress(
              filter: GlassPresets.notification,
              radius: Hy.rDemiBig,
              scale: 0.98,
              bloom: BloomTokens.strokeMiddleLight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(Hy.rSmall),
                          child: const SizedBox(width: 44, height: 44, child: PhotoArt(5)),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Dream',
                                style: TextStyle(color: Colors.white, fontSize: Hy.body1, fontWeight: FontWeight.w600),
                              ),
                              Text(
                                'Hope',
                                style: TextStyle(color: Colors.white70, fontSize: Hy.subtitle),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.cast_rounded, color: Colors.white70, size: 20),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 28),
                        Pressable(
                          onTap: () => setState(() => _playing = !_playing),
                          child: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 32),
                        ),
                        const Icon(Icons.skip_next_rounded, color: Colors.white, size: 28),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          for (final row in const [
            [('1', ''), ('2', 'ABC'), ('3', 'DEF')],
            [('4', 'GHI'), ('5', 'JKL'), ('6', 'MNO')],
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [for (final (d, l) in row) _key(d, l)]),
            ),
        ],
      ),
    ),
  );
}
