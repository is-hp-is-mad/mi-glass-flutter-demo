# mi-glass-flutter-demo

[![capture](https://github.com/is-hp-is-mad/mi-glass-flutter-demo/actions/workflows/capture.yml/badge.svg)](https://github.com/is-hp-is-mad/mi-glass-flutter-demo/actions/workflows/capture.yml)

这个项目把澎湃 OS 4（HyperOS）里的三种材质移植到了 Flutter，能在各个平台上运行：

- **小米天气的柔光玻璃**：带折射、边缘高光和方向光的液态玻璃卡片。
- **HyperOS 弹出菜单**：从按钮本身变形展开，文字从点击处向外散开。
- **系统桌面卸载弹窗的磨砂材质**：玻璃感较弱，可读性更高。

参数和 shader 都来自对澎湃 OS 4 系统包的逆向分析：
- 小米天气的 `libapp.so`
- 系统 Flutter 引擎 `libhyper_os_flutter.so`
- 系统桌面 MiuiHome 的 `libapp.so`

这不是凭感觉做的仿制品，具体每一项的来源和可信度见 [`PORTING.md`](PORTING.md)。

## 效果与测试

每次推送，GitHub Actions 都会在 **Windows / Linux / macOS** 上分别编译并运行这个 demo。demo 会按脚本自动操作：浅色、深色两种模式下各展示卡片、打开菜单、打开弹窗，然后反复开关菜单做压力测试。

产物在 [Actions](https://github.com/is-hp-is-mad/mi-glass-flutter-demo/actions/workflows/capture.yml) 页面的 `mi-glass-results` 里，包括：

- `<系统>_light_*.png` / `<系统>_dark_*.png`：各个状态的截图。
- `perf_<系统>.png`：性能曲线。上图是每一帧的 UI 线程和光栅线程耗时，带 16.7ms 参考线；下图是进程内存（RSS）随时间的变化，并标出了脚本的每个步骤。

注意：CI 机器没有独立 GPU，Linux 用的是 Mesa 软件渲染，帧耗时会明显高于真机，主要用来对比趋势和检查内存是否稳定。

**内存实测**（完整脚本：卡片、菜单、弹窗、设置页，再反复开关菜单压力测试；进程 RSS 峰值）：

| 系统 | 渲染后端 | 峰值内存 |
|---|---|---|
| Windows | Skia（合并路径） | 约 150MB |
| macOS | Impeller（原版多步路径） | 约 165MB |
| Linux（CI，CPU 软件渲染） | Skia（合并路径） | 约 335MB，软件渲染器本身占用较多 |

有 GPU 的平台整体在 **300MB 以内**，压力测试期间曲线平稳，没有锯齿式上涨。

## 快速开始

需要 Flutter 3.35.7（stable）和 Python 3。

界面字体统一用小米的 [MiSans](https://hyperos.mi.com/font/)。字体文件不随仓库分发，构建前先用脚本从官网下载需要的 4 个字重（ExtraLight、Regular、Medium、Semibold），放到 `assets/fonts/`：

```bash
python tool/fetch_misans.py
flutter pub get
flutter run -d windows   # 也可以换成 macos / linux / android / ios
```

在本机复现 CI 的截图流程：

```bash
flutter build windows --release
MIGLASS_CAPTURE=1 MIGLASS_OUT=ci_out build/windows/x64/runner/Release/hyper_glass.exe
python tool/plot_perf.py ci_out windows
```

## 用法

```dart
// 液态玻璃卡片：只能看到 HyperGlassScene 的 background
HyperGlassScene(
  background: MyWallpaper(),
  child: HyperGlass(borderRadius: 24, child: Text('空气质量 优 32')),
);

// 弹出菜单 / 弹窗（磨砂）：放在外层 scene 里，背景就是整个页面
HyperBlendBlur(
  material: isDark ? BlendMaterial.popupMenuDark : BlendMaterial.popupMenuLight,
  borderRadius: 24,
  child: menuItems,
);
```

完整的移植说明见 [`PORTING.md`](PORTING.md)，包括：
- 深色适配
- 卸载弹窗的按钮配色和链接小字的位置
- 菜单从角落弹出的动画
- 内存和背压的注意事项

## 实现要点

- **shader 是原版**：小米引擎里的 5 个 GLES shader（SDF、玻璃、LM 模糊、降采样、带色调的升采样）由 [`tool/to_flutter.py`](tool/to_flutter.py) 机械转换成 Flutter `FragmentProgram`。转换只改接口层，计算部分一字未动。
- **管线是照着引擎写的**：`AcquireGlassBlurTextures`、`ExecuteLMGaussianBlur`、`GetOrCreateSdfTexture`、`MiGlassContents::Render` 都按反汇编结果翻译成了 Dart（见 `lib/src/hyper_glass_renderer.dart`）。
- **兼容 Skia 后端**：Skia 的 SkSL 不支持 `while`；离屏纹理只有 8 位，存不下有符号距离；输出还会被强制钳制成预乘颜色。针对这三点做了编码、解码处理，见 `PORTING.md` 第 1.5 节。
- **控制内存**：
  - 只截取玻璃所在的区域，不截整个窗口。
  - 异步截图带背压：GPU 跟不上时只降低玻璃的刷新率，UI 本身不掉帧。
  - 磨砂场景按 1/4 分辨率截图。
  - 限制 Skia 的 GPU 缓存。
  - 加载时预热 shader，避免第一次打开菜单时卡顿。

## 已知问题

- **设置页的背景和选项分组不应该是玻璃。** demo 里的设置页为了省事，沿用了天空背景，选项分组也用了柔光玻璃卡片。真机上设置页是普通的纯色背景加分组列表，选项本身不是玻璃。
  - 对照小米效果时，设置页只以这几点为准：顶栏悬浮时的渐变模糊、返回按钮圆形玻璃底的出现时机、选项弹出动画。背景和选项卡片的外观请不要参考。
  - 这一处暂未修复。

## 平台状态

| 平台 | 状态 |
|---|---|
| Windows | 本机实测可用，CI 自动截图 |
| Linux / macOS | CI 自动截图 |
| Android / iOS / Web | 能编译，未实测 |

## 免责声明

本项目与小米公司没有任何关联。MiSans 字体的版权归小米所有，请按其授权协议使用。仓库中的 shader 和参数来自对公开发布的系统软件的逆向分析，仅用于学习和研究图形技术。"小米""澎湃 OS""HyperOS"等名称和商标归其权利人所有。如果权利人认为有不妥之处，请提 issue，会及时处理。

## 致谢

感谢 [LINUX DO](https://linux.do) 社区的支持与贡献。
