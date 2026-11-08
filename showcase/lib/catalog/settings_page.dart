import 'package:flutter/material.dart';

import '../ui/art.dart';
import '../ui/kit.dart';
import 'app.dart';
import 'render_mode_card.dart';
import 'widgets.dart';

/// Every kind of preference miuix has, as a settings screen would use them.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _wlan = true, _bt = false, _nfc = true, _notify = true, _sync = false;
  double _font = 0.4, _bright = 0.65;
  int _theme = 0, _refresh = 1;
  final _wallKey = GlobalKey(), _refreshKey = GlobalKey();

  static const _refreshRates = ['标准 60Hz', '高刷 120Hz', '自动'];

  void _openDetail(String title, List<Widget> children) =>
      CatalogHost.of(context).push(PageScaffold(title: title, onBack: CatalogHost.of(context).pop, bottomPadding: 40, children: children));

  @override
  Widget build(BuildContext context) {
    final os = OsScope.of(context);
    final overlay = HyperOverlay.of(context);
    return PageScaffold(
      title: '设置',
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: const HyField(hint: '搜索设置项', search: true),
        ),
        const RenderModeSwitchSection(includePreview: true),
        PrefCard(
          children: [PrefRow('小米账号', summary: '云服务、小米云盘、查找设备', onTap: () => overlay.toast('账号页面仅作展示'))],
        ),
        PrefCard(
          children: [
            PrefRow(
              'WLAN',
              icon: Icons.wifi_rounded,
              color: const Color(0xff2f7bff),
              summary: _wlan ? '已连接 HONOR-40' : null,
              trailing: HySwitch(value: _wlan, onChanged: (v) => setState(() => _wlan = v)),
            ),
            PrefRow(
              '蓝牙',
              icon: Icons.bluetooth_rounded,
              color: const Color(0xff2f7bff),
              trailing: HySwitch(value: _bt, onChanged: (v) => setState(() => _bt = v)),
            ),
            PrefRow('移动网络', icon: Icons.swap_vert_rounded, color: const Color(0xff2fbf71), value: '中国移动', onTap: _network),
            PrefRow(
              'NFC',
              icon: Icons.nfc_rounded,
              color: const Color(0xffff9f1a),
              trailing: HySwitch(value: _nfc, onChanged: (v) => setState(() => _nfc = v)),
            ),
          ],
        ),
        const PrefCategory('显示'),
        PrefCard(
          children: [
            PrefRow(
              '深色模式',
              icon: Icons.dark_mode_rounded,
              color: const Color(0xff5a5fd6),
              trailing: HySwitch(value: os.dark, onChanged: os.setDark),
            ),
            Builder(
              builder: (context) => PrefRow(
                key: _wallKey,
                '壁纸',
                icon: Icons.wallpaper_rounded,
                color: const Color(0xff34b7ff),
                value: Wallpaper.names[os.wallpaper],
                trailing: Icon(Icons.unfold_more_rounded, size: 19, color: Hy.hint(os.dark)),
                onTap: () =>
                    overlay.select(_wallKey.currentContext!, Wallpaper.names, os.wallpaper, (i) => os.update(() => os.wallpaper = i)),
              ),
            ),
            PrefRow(
              '屏幕刷新率',
              key: _refreshKey,
              icon: Icons.speed_rounded,
              color: const Color(0xffff6d6d),
              value: _refreshRates[_refresh],
              trailing: Icon(Icons.unfold_more_rounded, size: 19, color: Hy.hint(os.dark)),
              onTap: () => overlay.select(_refreshKey.currentContext!, _refreshRates, _refresh, (i) => setState(() => _refresh = i)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '亮度',
                    style: TextStyle(color: Hy.text(os.dark), fontSize: Hy.headline1),
                  ),
                  const SizedBox(height: 10),
                  HySeek(value: _bright, onChanged: (v) => setState(() => _bright = v)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '字体大小',
                    style: TextStyle(color: Hy.text(os.dark), fontSize: Hy.headline1),
                  ),
                  const SizedBox(height: 10),
                  HySeek(value: _font, onChanged: (v) => setState(() => _font = v)),
                ],
              ),
            ),
          ],
        ),
        const PrefCategory('主题'),
        PrefCard(
          children: [
            for (final (i, l) in const ['跟随系统', '浅色', '深色'].indexed)
              PrefRow(
                l,
                onTap: () => setState(() => _theme = i),
                trailing: i == _theme ? Icon(Icons.check_rounded, color: Hy.primary(os.dark), size: 22) : const SizedBox(width: 22),
              ),
          ],
        ),
        const PrefCategory('通知'),
        PrefCard(
          children: [
            PrefRow(
              '锁屏显示通知',
              summary: '在锁屏界面显示通知内容',
              trailing: HyCheck(value: _notify, onChanged: (v) => setState(() => _notify = v)),
            ),
            PrefRow(
              '自动同步',
              summary: '连接 WLAN 时同步数据',
              trailing: HyCheck(value: _sync, onChanged: (v) => setState(() => _sync = v)),
            ),
          ],
        ),
        PrefCard(
          children: [
            PrefRow('关于手机', icon: Icons.info_rounded, color: const Color(0xff7b8494), value: 'OS4.0', onTap: _about),
            PrefRow(
              '恢复默认设置',
              icon: Icons.restart_alt_rounded,
              color: const Color(0xffff6d6d),
              onTap: () => overlay.dialog(
                '恢复默认设置',
                '所有展示用的选项都会回到初始状态。',
                onConfirm: () {
                  setState(() {
                    _wlan = true;
                    _bt = false;
                    _bright = 0.65;
                    _font = 0.4;
                  });
                  overlay.toast('已恢复默认');
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _network() => _openDetail('移动网络', [
    PrefCard(
      children: [
        PrefRow('SIM 卡 1', summary: '中国移动', value: '已启用'),
        const PrefRow('数据流量', value: '2.1 GB', chevron: false),
        const PrefRow('漫游', chevron: false, value: '关闭'),
      ],
    ),
    const PrefCategory('网络偏好'),
    PrefCard(
      children: const [
        PrefRow('5G 优先', chevron: false, value: '开启'),
        PrefRow('双卡增强', chevron: false, value: '关闭'),
      ],
    ),
  ]);

  void _about() => _openDetail('关于手机', const [
    PrefCard(
      children: [
        PrefRow('设备名称', value: 'Xiaomi', chevron: false),
        PrefRow('系统版本', value: 'OS4.0.4.0', chevron: false),
        PrefRow('运行内存', value: '16 GB', chevron: false),
        PrefRow('机身存储', value: '512 GB', chevron: false),
      ],
    ),
  ]);
}
