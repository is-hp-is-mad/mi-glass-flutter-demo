import 'package:flutter/material.dart';

import '../hyper_glass.dart';
import '../ui/art.dart';
import '../ui/kit.dart';
import '../ui/morph_menu.dart';

/// Gallery (HyperGalleryUI): tabs 照片 / 相册 / 精选 in a floating glass bar, 4-column photo grid with date
/// groups, photo page with floating glass bars (GlassOs4Background) and the morphing "more" menu.
class GalleryApp extends StatefulWidget {
  const GalleryApp({super.key, required this.onBack});
  final VoidCallback onBack;
  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> with TickerProviderStateMixin {
  int _tab = 0;
  double _offset = 0;
  bool _selecting = false;
  final _selected = <int>{};
  late final _tabX = SpringValue(this, damping: 0.8, response: 0.36);
  late final _view = SpringValue(this, damping: 0.86, response: 0.4);
  int? _photo;
  Rect _from = Rect.zero;
  final _scroll = ScrollController();

  static const _groups = [('今天', 7, 0), ('昨天 · 杭州', 10, 7), ('10月12日 · 千岛湖', 13, 17), ('9月30日 · 北京', 19, 30)];
  static const _albums = [
    ('相机', 2318, 1),
    ('截屏录屏', 512, 3),
    ('收藏', 86, 5),
    ('视频', 204, 8),
    ('微信', 1420, 13),
    ('下载', 33, 21),
  ];

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() => setState(() => _offset = _scroll.offset));
  }

  @override
  void dispose() {
    _tabX.dispose();
    _view.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _setTab(int i) {
    setState(() {
      _tab = i;
      _offset = 0;
    });
    _tabX.to(i.toDouble());
  }

  void _openPhoto(int seed, Rect from) {
    setState(() {
      _photo = seed;
      _from = from;
    });
    _view.to(1);
  }

  void _closePhoto() => _view.to(0, response: 0.32);

  @override
  Widget build(BuildContext context) {
    final dark = OsScope.of(context).dark;
    final top = MediaQuery.paddingOf(context).top + 38;
    return Material(
      color: Hy.window(dark),
      child: LayoutBuilder(
        builder: (context, c) => Stack(
          children: [
            HyperGlassScene(
              background: ColoredBox(
                color: Hy.window(dark),
                child: IndexedStack(
                  index: _tab,
                  sizing: StackFit.expand,
                  children: [_photos(top, dark), _albumsPage(top, dark), _featured(top, dark)],
                ),
              ),
              child: Stack(
                children: [
                  const Positioned(top: 0, left: 0, right: 0, child: IgnorePointer(child: SizedBox.shrink())),
                  FloatingBar(
                    top: top,
                    title: const ['照片', '相册', '精选'][_tab],
                    offset: _offset,
                    dark: dark,
                    onBack: widget.onBack,
                    maskColor: dark ? const Color(0xff242424) : const Color(0xfff3f3f3),
                    bloom: Hy.flutterBloom,
                    actions: [
                      if (_tab == 0)
                        Pressable(
                          onTap: () => setState(() {
                            _selecting = !_selecting;
                            _selected.clear();
                          }),
                          child: SizedBox(
                            height: 40,
                            width: 76,
                            child: FloatSurface(
                              bloom: Hy.flutterBloom,
                              radius: 20,
                              child: Center(
                                child: Text(
                                  _selecting ? '取消' : '选择',
                                  style: TextStyle(color: Hy.text(dark), fontSize: Hy.body2, fontWeight: FontWeight.w500),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  Positioned(left: 0, right: 0, top: 0, child: StatusBar(color: Hy.text(dark))),
                  Positioned(left: 24, right: 24, bottom: 30, height: 60, child: _bottomBar(dark)),
                ],
              ),
            ),
            AnimatedBuilder(
              animation: _view.c,
              builder: (_, _) {
                final t = _view.value;
                if (t <= 0.003 || _photo == null) return const SizedBox.shrink();
                final full = Offset.zero & c.biggest;
                return Positioned.fromRect(
                  rect: Rect.lerp(_from, full, t)!,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular((1 - t).clamp(0.0, 1.0) * 12),
                    child: OverflowBox(
                      minWidth: c.maxWidth,
                      maxWidth: c.maxWidth,
                      minHeight: c.maxHeight,
                      maxHeight: c.maxHeight,
                      child: Transform.scale(
                        scale: Rect.lerp(_from, full, t)!.width / c.maxWidth,
                        child: PhotoPage(seed: _photo!, chrome: t.clamp(0.0, 1.0), onClose: _closePhoto),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar(bool dark) {
    if (_selecting) {
      return FloatSurface(
        bloom: Hy.flutterBloom,
        radius: 30,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final (l, i) in [
              ('发送', Icons.ios_share_rounded),
              ('创作', Icons.auto_fix_high_rounded),
              ('添加到', Icons.add_box_outlined),
              ('删除', Icons.delete_outline_rounded),
            ])
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(i, size: 21, color: Hy.text(dark)),
                  Text(l, style: TextStyle(color: Hy.text(dark), fontSize: Hy.footnote)),
                ],
              ),
          ],
        ),
      );
    }
    return Row(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) => FloatSurface(
              bloom: Hy.flutterBloom,
              radius: 30,
              child: AnimatedBuilder(
                animation: _tabX.c,
                builder: (_, _) {
                  final w = (c.maxWidth - 8) / 3;
                  return Stack(
                    children: [
                      Positioned(
                        left: 4 + w * _tabX.value,
                        top: 4,
                        bottom: 4,
                        width: w,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(26),
                            color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.1),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          const SizedBox(width: 4),
                          for (final (i, l) in const ['照片', '相册', '精选'].indexed)
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _setTab(i),
                                child: Center(
                                  child: Text(
                                    l,
                                    style: TextStyle(
                                      color: _tab == i ? Hy.primary(dark) : Hy.text(dark),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          const SizedBox(width: 4),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 60,
          height: 60,
          child: FloatSurface(
            bloom: Hy.flutterBloom,
            radius: 30,
            onTap: () {},
            child: Icon(Icons.search_rounded, color: Hy.text(dark), size: 24),
          ),
        ),
      ],
    );
  }

  Widget _title(String t, bool dark, double top) => Padding(
    padding: EdgeInsets.fromLTRB(20, top + Hy.barHeight - 8, 20, 12),
    child: Opacity(
      opacity: 1 - ((_offset - 24) / 32).clamp(0.0, 1.0),
      child: Text(
        t,
        style: TextStyle(color: Hy.text(dark), fontSize: Hy.title1, fontWeight: FontWeight.w600),
      ),
    ),
  );

  Widget _photos(double top, bool dark) => CustomScrollView(
    controller: _scroll,
    slivers: [
      SliverToBoxAdapter(child: _title('照片', dark, top)),
      for (final (name, n, start) in _groups) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Text(
              name,
              style: TextStyle(color: Hy.text(dark), fontSize: Hy.headline1, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 2, crossAxisSpacing: 2),
            delegate: SliverChildBuilderDelegate((context, i) => _tile(start + i, dark), childCount: n),
          ),
        ),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 120)),
    ],
  );

  Widget _tile(int seed, bool dark) => Builder(
    builder: (ctx) => GestureDetector(
      onTap: () {
        if (_selecting) {
          setState(() => _selected.contains(seed) ? _selected.remove(seed) : _selected.add(seed));
          return;
        }
        final b = ctx.findRenderObject()! as RenderBox;
        final root = context.findRenderObject()! as RenderBox;
        _openPhoto(seed, b.localToGlobal(Offset.zero, ancestor: root) & b.size);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          PhotoArt(seed),
          if (seed % 11 == 3)
            const Positioned(
              right: 5,
              bottom: 4,
              child: Text('0:18', style: TextStyle(color: Colors.white, fontSize: Hy.footnote, fontWeight: FontWeight.w600)),
            ),
          if (seed % 13 == 5) const Positioned(left: 5, bottom: 4, child: Icon(Icons.favorite, color: Colors.white, size: 13)),
          if (_selecting)
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _selected.contains(seed) ? Hy.primary(dark) : const Color(0x33000000),
                  border: Border.all(color: Colors.white, width: 1.4),
                ),
                child: _selected.contains(seed) ? const Icon(Icons.check, size: 15, color: Colors.white) : null,
              ),
            ),
        ],
      ),
    ),
  );

  Widget _albumsPage(double top, bool dark) => ListView(
    padding: const EdgeInsets.only(bottom: 120),
    children: [
      _title('相册', dark, top),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 14,
          childAspectRatio: 0.84,
          children: [
            for (final (name, n, seed) in _albums)
              Pressable(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Hy.rCommon),
                        child: PhotoArt(seed),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      name,
                      style: TextStyle(color: Hy.text(dark), fontSize: Hy.body1, fontWeight: FontWeight.w500),
                    ),
                    Text('$n', style: TextStyle(color: Hy.sub(dark), fontSize: Hy.subtitle)),
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _featured(double top, bool dark) => ListView(
    padding: const EdgeInsets.only(bottom: 120),
    children: [
      _title('精选', dark, top),
      for (final (title, sub, seed) in const [
        ('一年前的今天', '千岛湖 · 42 张', 2),
        ('人物与宠物', '12 个分组', 7),
        ('足迹', '6 座城市', 16),
        ('闪回', 'AI 视频 · 0:45', 9),
      ])
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: SizedBox(
            height: 190,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Hy.rDemiBig),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PhotoArt(seed),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(color: Colors.white, fontSize: Hy.title3, fontWeight: FontWeight.w600),
                          ),
                          Text(sub, style: const TextStyle(color: Colors.white70, fontSize: Hy.subtitle)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
}

/// Photo page: the bars float over the picture as glass and fade together with a tap.
class PhotoPage extends StatefulWidget {
  const PhotoPage({super.key, required this.seed, required this.chrome, required this.onClose});
  final int seed;
  final double chrome;
  final VoidCallback onClose;
  @override
  State<PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends State<PhotoPage> with TickerProviderStateMixin {
  late final _menu = PopupMotion(this);
  late final _bars = SpringValue(this, value: 1, damping: 0.9, response: 0.3);
  bool _shown = true, _fav = false;
  final _moreKey = GlobalKey();
  Rect _anchor = Rect.zero;

  @override
  void dispose() {
    _menu.dispose();
    _bars.dispose();
    super.dispose();
  }

  void _setMenu(bool open) {
    if (open) {
      final b = _moreKey.currentContext!.findRenderObject()! as RenderBox;
      final root = context.findRenderObject()! as RenderBox;
      _anchor = b.localToGlobal(Offset.zero, ancestor: root) & b.size;
    }
    _menu.set(open);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final dark = OsScope.of(context).dark;
    final top = MediaQuery.paddingOf(context).top + 38;
    return LayoutBuilder(
      builder: (context, c) => HyperGlassScene(
        background: GestureDetector(
          onTap: () {
            setState(() => _shown = !_shown);
            _bars.to(_shown ? 1 : 0);
          },
          child: Container(
            color: _shown && !dark ? Colors.white : Colors.black,
            child: AspectRatio(aspectRatio: c.maxWidth / c.maxHeight, child: PhotoArt(widget.seed)),
          ),
        ),
        child: AnimatedBuilder(
          animation: Listenable.merge([_bars.c, _menu.listenable]),
          builder: (context, _) {
            final v = (_bars.value * widget.chrome).clamp(0.0, 1.0);
            final items = [
              MorphMenuItem('添加到相册', icon: Icons.add_box_outlined, () => _setMenu(false)),
              MorphMenuItem('设为壁纸', icon: Icons.wallpaper_rounded, () => _setMenu(false)),
              MorphMenuItem('幻灯片放映', icon: Icons.slideshow_rounded, () => _setMenu(false)),
              MorphMenuItem('详细信息', icon: Icons.info_outline_rounded, () => _setMenu(false)),
            ];
            const itemH = 52.0;
            return Stack(
              children: [
                if (v > 0.01) ...[
                  Positioned(
                    left: 14,
                    right: 14,
                    top: top + (v - 1) * 40,
                    height: 48,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 48,
                          child: FloatSurface(
                            bloom: Hy.flutterBloom,
                            radius: 24,
                            opacity: v,
                            onTap: widget.onClose,
                            child: Icon(Icons.arrow_back_ios_new, size: 18, color: Hy.text(dark)),
                          ),
                        ),
                        const Spacer(),
                        SizedBox(
                          width: 150,
                          child: FloatSurface(
                            bloom: Hy.flutterBloom,
                            radius: 24,
                            opacity: v,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('10月12日 14:08', style: TextStyle(color: Hy.text(dark), fontSize: Hy.body2, fontWeight: FontWeight.w600)),
                                Text('千岛湖', style: TextStyle(color: Hy.sub(dark), fontSize: Hy.footnote)),
                              ],
                            ),
                          ),
                        ),
                        const Spacer(),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: 30 + (v - 1) * 60,
                    height: 62,
                    child: FloatSurface(
                      bloom: Hy.flutterBloom,
                      radius: 31,
                      opacity: v,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _action(Icons.ios_share_rounded, '发送'),
                          _action(Icons.tune_rounded, '编辑'),
                          _action(_fav ? Icons.favorite : Icons.favorite_border, '收藏', onTap: () => setState(() => _fav = !_fav)),
                          _action(Icons.delete_outline_rounded, '删除'),
                          _action(Icons.more_horiz, '更多', key: _moreKey, onTap: () => _setMenu(true)),
                        ],
                      ),
                    ),
                  ),
                ],
                MorphMenu(
                  motion: _menu,
                  anchor: _anchor,
                  menu: menuRectFor(_anchor, c.biggest, 212, itemH * items.length + 16, growUp: true),
                  dark: dark,
                  items: items,
                  itemHeight: itemH,
                  anchorRadius: 24,
                  onDismiss: () => _setMenu(false),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _action(IconData i, String l, {VoidCallback? onTap, Key? key}) => Pressable(
    key: key,
    onTap: onTap,
    child: SizedBox(
      width: 52,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(i, size: 21, color: Hy.text(OsScope.of(context).dark)),
          Text(l, style: TextStyle(color: Hy.text(OsScope.of(context).dark), fontSize: Hy.footnote)),
        ],
      ),
    ),
  );
}
