import 'package:flutter/material.dart';

import '../ui/art.dart';
import '../ui/kit.dart';

/// 手动切换三种柔光玻璃渲染方式（小米原生、小米移植、安卓低版本Flutter移植版）的交互控制与实时对比面板。
class RenderModeSwitchSection extends StatefulWidget {
  const RenderModeSwitchSection({super.key, this.includePreview = false});

  /// 是否在控制卡片下方内嵌独立的实时柔光玻璃预览画布（在「设置」首页开启，在「材质」页直接驱动全页样张）。
  final bool includePreview;

  @override
  State<RenderModeSwitchSection> createState() => _RenderModeSwitchSectionState();
}

class _RenderModeSwitchSectionState extends State<RenderModeSwitchSection> {
  int _presetIndex = 0;

  static final _previewPresets = <(String, GlassFilter)>[
    ('通用大卡', GlassTokens.commonLargeRegular),
    ('着色紫', GlassTokens.tintPurple),
    ('着色蓝', GlassTokens.tintBlue),
    ('仿生玻璃', GlassTokens.bionicMediumRegular),
  ];

  static const _portBackends = <(String, String)>[
    ('AUTO', '自动'),
    ('AGSL_RUNTIME_SHADER', 'AGSL(13+)'),
    ('OPENGL_ES_30', 'GLES3.0(低版)'),
    ('FALLBACK_MASK_ONLY', '安全遮罩'),
  ];

  @override
  void initState() {
    super.initState();
    hyperRenderController.ensureCapabilitiesLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final os = OsScope.of(context);
    final dark = os.dark;
    return ListenableBuilder(
      listenable: hyperRenderController,
      builder: (context, _) {
        final mode = hyperRenderController.mode;
        final modeIndex = HyperRenderMode.values.indexOf(mode);

        final (statusColor, statusTitle, statusDetail) = switch (mode) {
          HyperRenderMode.xiaomiNative => hyperRenderController.xiaomiNativeSupported
              ? (
                  const Color(0xff2fbf71),
                  '已命中小米 HyperOS 原生接口 (View.setMiGlass)',
                  '直接调用小米 ROM 系统 Framework 与 libhwui.so 私有着色器硬解。',
                )
              : (
                  const Color(0xffff9f1a),
                  '当前设备非小米 ROM · 已触发防崩溃平滑降级',
                  '未检测到 android.view.View.setMiGlass 私有符号，已自动拦截 NoSuchMethodError 并降级为安全半透明遮罩。请切换至「小米移植」或「Flutter移植」查看完整柔光玻璃。',
                ),
          HyperRenderMode.xiaomiPort => (
              const Color(0xff277af7),
              '已启用小米移植通用 Android SDK (${hyperRenderController.portBackend})',
              '完全脱离小米 ROM 依赖，在 Android 13+ 使用标准 AGSL RuntimeShader + RenderEffect，在 Android 12 及以下使用标准 OpenGL ES 3.0 离屏 FBO，支持全品牌安卓机型。',
            ),
          HyperRenderMode.flutterPort => (
              const Color(0xff8c6bff),
              '已启用安卓低版本 / 全平台 Flutter 移植版管线',
              '基于纯 Flutter FragmentShader 实现 LM 多级高斯模糊、G2 超椭圆距离场、透镜折射与漫射描边，兼容安卓低版本 (API 21+) 及全平台。',
            ),
        };

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PrefCategory('渲染方式手动切换 · Render Mode'),
            PrefCard(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.layers_rounded, size: 19, color: Hy.primary(dark)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '选择柔光玻璃渲染管线',
                              style: TextStyle(
                                color: Hy.text(dark),
                                fontSize: Hy.body1,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              mode.label,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: Hy.footnote,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      HySegmented(
                        items: const ['小米原生', '小米移植', 'Flutter移植'],
                        index: modeIndex,
                        onChanged: (i) => hyperRenderController.setMode(HyperRenderMode.values[i]),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: dark ? const Color(0x14ffffff) : const Color(0x0a000000),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: statusColor.withValues(alpha: 0.35), width: 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    statusTitle,
                                    style: TextStyle(
                                      color: Hy.text(dark),
                                      fontSize: Hy.subtitle,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              statusDetail,
                              style: TextStyle(
                                color: Hy.sub(dark),
                                fontSize: Hy.footnote,
                                height: 1.4,
                              ),
                            ),
                            if (hyperRenderController.deviceModel.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                '当前运行环境: ${hyperRenderController.deviceModel}',
                                style: TextStyle(
                                  color: Hy.hint(dark),
                                  fontSize: Hy.footnote,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (mode == HyperRenderMode.xiaomiPort) ...[
                        const SizedBox(height: 12),
                        Text(
                          '小米移植 SDK 内部渲染档位 (测试不同安卓版本降级):',
                          style: TextStyle(
                            color: Hy.sub(dark),
                            fontSize: Hy.footnote,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            for (final (id, label) in _portBackends)
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 2),
                                  child: GestureDetector(
                                    onTap: () => hyperRenderController.setPortBackend(id),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 7),
                                      decoration: BoxDecoration(
                                        color: hyperRenderController.forcedPortBackend == id
                                            ? Hy.primary(dark)
                                            : (dark ? const Color(0x1fffffff) : const Color(0x0f000000)),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        label,
                                        style: TextStyle(
                                          color: hyperRenderController.forcedPortBackend == id
                                              ? Colors.white
                                              : Hy.text(dark),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (widget.includePreview) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Hy.rDemiBig),
                  child: SizedBox(
                    height: 214,
                    child: HyperGlassScene(
                      animate: os.animatedWallpaper,
                      background: Wallpaper(index: os.wallpaper, dark: false, animate: os.animatedWallpaper),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          children: [
                            Expanded(
                              child: GlassPress(
                                filter: _previewPresets[_presetIndex].$2,
                                radius: Hy.rDemiBig,
                                scale: 0.97,
                                bloom: BloomTokens.strokeMiddleLight,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 46,
                                        height: 46,
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(alpha: 0.22),
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                        child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 26),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '实时预览 · ${mode.label}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: Hy.body1,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '材质: ${_previewPresets[_presetIndex].$1} · 按住卡片体验折射高光',
                                              style: const TextStyle(
                                                color: Colors.white70,
                                                fontSize: Hy.footnote,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                for (final (idx, item) in _previewPresets.indexed)
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 3),
                                      child: GestureDetector(
                                        onTap: () => setState(() => _presetIndex = idx),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 6),
                                          decoration: BoxDecoration(
                                            color: idx == _presetIndex
                                                ? Colors.white.withValues(alpha: 0.88)
                                                : Colors.black.withValues(alpha: 0.36),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            item.$1,
                                            style: TextStyle(
                                              color: idx == _presetIndex ? Colors.black87 : Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}
