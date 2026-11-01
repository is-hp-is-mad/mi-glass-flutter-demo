import 'package:flutter/material.dart';

import '../ui/kit.dart';
import 'widgets.dart';

/// Each miuix control on its own, sized from the ROM's dimens.
class ControlsPage extends StatefulWidget {
  const ControlsPage({super.key});
  @override
  State<ControlsPage> createState() => _ControlsPageState();
}

class _ControlsPageState extends State<ControlsPage> {
  bool _switch = true, _switchOff = false, _check = true, _radio = true;
  double _seek = 0.45, _progress = 0.62;
  int _segment = 0, _chip = 1, _textTab = 0, _spin = 0, _page = 1;
  final _spinKey = GlobalKey();

  static const _spinItems = ['按时间排序', '按名称排序', '按大小排序'];

  Widget _label(String t, bool dark) => Text(
    t,
    style: TextStyle(color: Hy.sub(dark), fontSize: Hy.subtitle),
  );

  @override
  Widget build(BuildContext context) {
    final dark = OsScope.of(context).dark;
    final overlay = HyperOverlay.of(context);
    const gap = SizedBox(height: 12);
    return PageScaffold(
      title: '控件',
      children: [
        const PrefCategory('导航'),
        PrefCard(
          padding: const EdgeInsets.all(16),
          children: [
            _label('文字标签', dark),
            const SizedBox(height: 8),
            HyTextTabs(items: const ['最近', '收藏', '共享'], index: _textTab, onChanged: (i) => setState(() => _textTab = i)),
            const SizedBox(height: 18),
            _label('分段选择', dark),
            const SizedBox(height: 8),
            HySegmented(items: const ['日', '周', '月', '年'], index: _segment, onChanged: (i) => setState(() => _segment = i)),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: HyChips(items: const ['全部', '工作', '生活', '旅行', '灵感', '待办'], index: _chip, onChanged: (i) => setState(() => _chip = i)),
        ),
        PrefCard(
          padding: const EdgeInsets.all(16),
          children: [
            _label('页面指示器', dark),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 4; i++)
                  GestureDetector(
                    onTap: () => setState(() => _page = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _page ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: i == _page ? Hy.primary(dark) : Hy.hint(dark),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
        const PrefCategory('按钮'),
        PrefCard(
          padding: const EdgeInsets.all(16),
          children: [
            HyButton('主要按钮', primary: true, onTap: () => overlay.toast('主要按钮')),
            gap,
            HyButton('次要按钮', onTap: () => overlay.toast('次要按钮')),
            gap,
            Row(
              children: [
                HyButton('内联按钮', primary: true, size: HyButtonSize.inline, onTap: () => overlay.toast('内联按钮')),
                const SizedBox(width: 10),
                HyButton('取消', size: HyButtonSize.inline, onTap: () {}),
                const Spacer(),
                HyButton('小按钮', size: HyButtonSize.tiny, onTap: () {}),
              ],
            ),
          ],
        ),
        const PrefCategory('选择'),
        PrefCard(
          children: [
            PrefRow(
              '开关 · 开',
              trailing: HySwitch(value: _switch, onChanged: (v) => setState(() => _switch = v)),
            ),
            PrefRow(
              '开关 · 关',
              trailing: HySwitch(value: _switchOff, onChanged: (v) => setState(() => _switchOff = v)),
            ),
            PrefRow(
              '复选框',
              trailing: HyCheck(value: _check, onChanged: (v) => setState(() => _check = v)),
            ),
            PrefRow(
              '单选按钮',
              trailing: HyCheck(radio: true, value: _radio, onChanged: (v) => setState(() => _radio = v)),
            ),
          ],
        ),
        const PrefCategory('滑杆与进度'),
        PrefCard(
          padding: const EdgeInsets.all(16),
          children: [
            _label('进度滑杆', dark),
            const SizedBox(height: 10),
            HySeek(value: _seek, onChanged: (v) => setState(() => _seek = v)),
            const SizedBox(height: 18),
            _label('进度条 ${(_progress * 100).round()}%', dark),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => setState(() => _progress = _progress > 0.9 ? 0.1 : _progress + 0.2),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 6,
                  backgroundColor: dark ? const Color(0x33ffffff) : const Color(0x14000000),
                  color: Hy.primary(dark),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.6, color: Hy.primary(dark), backgroundColor: Hy.divider(dark)),
                ),
                const SizedBox(width: 12),
                Text(
                  '加载中…',
                  style: TextStyle(color: Hy.sub(dark), fontSize: Hy.body2),
                ),
              ],
            ),
          ],
        ),
        const PrefCategory('输入'),
        PrefCard(
          padding: const EdgeInsets.all(16),
          children: const [
            HyField(hint: '搜索', search: true),
            SizedBox(height: 12),
            HyField(hint: '请输入内容'),
          ],
        ),
        const PrefCategory('弹出层'),
        PrefCard(
          children: [
            PrefRow(
              '下拉选择',
              key: _spinKey,
              value: _spinItems[_spin],
              trailing: Icon(Icons.unfold_more_rounded, size: 19, color: Hy.hint(dark)),
              onTap: () => overlay.select(_spinKey.currentContext!, _spinItems, _spin, (i) => setState(() => _spin = i)),
            ),
            PrefRow('对话框', onTap: () => overlay.dialog('删除这条笔记？', '删除后可以在最近删除中找回。')),
            PrefRow('底部面板', onTap: () => overlay.sheet(const ShareSheet())),
            PrefRow('轻提示', onTap: () => overlay.toast('已保存到相册')),
          ],
        ),
      ],
    );
  }
}

class ShareSheet extends StatelessWidget {
  const ShareSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = HyperTheme.isDark(context);
    final overlay = HyperOverlay.of(context);
    return Column(
      children: [
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
                onTap: overlay.closeSheet,
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
          child: SizedBox(width: double.infinity, child: HyperDialogButton('取消', onTap: overlay.closeSheet)),
        ),
      ],
    );
  }
}
