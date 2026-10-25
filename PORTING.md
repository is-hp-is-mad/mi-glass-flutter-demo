# HyperGlass 移植指南

把小米天气的柔光玻璃、HyperOS 弹出菜单和桌面卸载弹窗的材质移植到另一个 Flutter 项目。

可信度标记，每一条都标了来源：

- **【逆向】**：从 ROM 里的 `libapp.so` 或 `libhyper_os_flutter.so` 读出来的常量，可以直接用。
- **【推断】**：根据逆向线索推出来的，没有完全确认对应哪个控件。
- **【自定】**：我自己设计的，小米代码里没有对应内容，可以按需修改。

---

## 0. 要拷贝的文件

| 文件 | 作用 |
|---|---|
| `lib/hyper_glass.dart` | 统一导出 |
| `lib/src/glass_filter.dart` | 玻璃参数（`ImageFilter.glass` V7 的 p2–p34）和 LM 高斯核计算 |
| `lib/src/hyper_glass_renderer.dart` | 渲染管线：LM 模糊、SDF、玻璃、混色模糊 |
| `lib/src/hyper_glass.dart` | `HyperGlassScene`、`HyperGlass`、`HyperBlendBlur` 三个组件 |
| `lib/src/blend_material.dart` | 菜单和弹窗的混色材质表 |
| `lib/src/shader_layout.g.dart` | 各 shader 的 uniform 槽位（自动生成，不要手改） |
| `shaders/*.frag` | 6 个 shader |

在 `pubspec.yaml` 里注册 shader：

```yaml
flutter:
  shaders:
    - shaders/mi_glass_sdf.frag
    - shaders/mi_glass_v13_f16.frag
    - shaders/mi_lm_blur.frag
    - shaders/mi_lm_downsample.frag
    - shaders/mi_lm_upsample_tint.frag
    - shaders/mi_blend_blur.frag
```

如果包名不是 `hyper_glass`，或者 shader 放在了 package 里，要改资源路径：`shader_layout.g.dart` 里的 `asset` 字段，以及 `hyper_glass_renderer.dart` 里的 `'shaders/mi_blend_blur.frag'`。

前 5 个 shader 是从系统引擎里提取的原版，经 `tool/to_flutter.py` 转换而来（引擎原始 shader 不随仓库分发），**不要手改**。要改就改转换脚本，然后重新生成：

```bash
python -I tool/to_flutter.py <引擎 shader 目录> shaders lib/src/shader_layout.g.dart
```

---

## 1. 液态玻璃（天气卡片）怎么用

### 1.1 基本结构

玻璃只能"看到" `HyperGlassScene` 里 `background` 那一层。`background` 每帧会按物理分辨率截一次图，作为玻璃的背景纹理。

```dart
HyperGlassScene(
  background: MyBackground(),          // 天空、壁纸、动画……玻璃折射和模糊的就是它
  child: Stack(children: [
    Positioned(left: 16, top: 200, width: 380, height: 120,
      child: HyperGlass(
        borderRadius: 24,              // 逻辑像素
        child: Padding(padding: EdgeInsets.all(18), child: Text('空气质量 优 32')),
      )),
  ]),
)
```

- `HyperGlass` 可以放在 `child` 子树里的任何位置，包括 ListView 里，它会自己计算相对背景的位置。
- 不要把 `HyperGlass` 放进 `background`，否则它会去采样自己。
- `animate`：背景在动时设为 `true`（每帧截图）。背景静止时设为 `false`，只在重建时截图，能省不少性能。

### 1.2 参数

`GlassFilter()` 的默认值就是小米天气卡片传给引擎的真实参数【逆向：`_Rhb` → `ImageFilter.glass` → `initGlassV7`】。完整表格见 `docs/GLASS_PARAMS.md`，常改的几项：

| 字段 | 默认 | 含义 |
|---|---|---|
| `edgePx` / `edgePow` | 20 / 1.6 | 边缘高光带宽度和衰减 |
| `thicknessPx` | 98.22 | 玻璃厚度，决定折射强度 |
| `refractIOR` | 1.4 | 折射率 |
| `lightDir` / `lightIntensity` | [-0.5, 0.5, -0.1] / 1.2 | 方向光 |
| `glassColor` | [1, 1, 1, 0.05] | 玻璃底色 |
| `saturation` / `brightness` | 1.6 / 0.14 | 透过玻璃看到的背景饱和度和亮度 |

注意：长度类参数（`edgePx`、`thicknessPx`、`reflectOffsetPx`）在引擎里是**物理像素**，移植时没有按 dpr 缩放。在 dpr=3 的手机上效果和原版一致；在 dpr=1.5 的桌面上，高光会显得宽一些。要统一视觉，可以自己乘上 `dpr / 3`。

### 1.3 深色适配

- 【逆向】小米天气里只找到**一套**玻璃参数，没有深色专用的参数组。深色效果来自背景本身变暗，玻璃只是如实折射。
- 所以深色适配的做法是：换背景（夜间渐变、暗色壁纸），玻璃参数不动。示例 `main.dart` 里的 `_SkyPainter` 就是这样根据 `dark` 切换渐变色的。
- 卡片上的文字在两种模式下都用白色（`Colors.white` 和 `white70`），和小米天气一致，因为卡片总是叠在较暗、较饱和的背景上。
- 如果你的项目在浅色模式下背景很亮（比如白底），玻璃会几乎不可见。这是这种材质本身的特性，原版也一样。这种页面应该换用第 3 节的混色模糊材质。

### 1.4 嵌套：浮层要看得到下面的玻璃卡片

菜单、弹窗这类浮层需要模糊"整个页面"，包括玻璃卡片和遮罩，所以要把页面整体再包一层 scene：

```dart
HyperGlassScene(                       // 外层：给浮层用
  animate: overlayVisible,             // 浮层不显示时关掉，省性能
  background: Stack(fit: StackFit.expand, children: [
    HyperGlassScene(background: sky, child: cards),  // 内层：给卡片用
    IgnorePointer(child: ColoredBox(color: Colors.black.withValues(alpha: 0.3 * t))), // 弹窗遮罩
  ]),
  child: Stack(children: [menu, dialog]),
)
```

### 1.5 已知限制

- **只在 Windows 上实测过。** Windows 走的是 Skia，代码里已经处理了三处 Skia 限制：不支持 `while` 循环、8 位离屏纹理精度不够、输出被强制钳制成预乘颜色。Android、iOS、macOS 走 Impeller，理论上兼容，但没跑过。
- 背景截图比显示晚一帧。背景快速运动时，玻璃里的内容会滞后一帧。
- **内存和背压（重要）**：引擎里每帧复用同一批渲染目标，而 Flutter 的 `toImageSync` 每次都会新建纹理。所以 `HyperGlassScene` 做了两件事：
  1. 只截取玻璃表面所在的区域（每边外扩 80 逻辑像素），不截整个窗口。
  2. 用异步 `toImage` 做背压，上一轮还没被光栅线程画完，就不开始下一轮。GPU 跟不上时，玻璃会自动降低刷新率，但 UI 本身不掉帧。

  移植时**不要**把它改回 `toImageSync` 加每帧刷新：在 GPU 较弱的机器上，内存会在几秒内涨到好几 GB。
- **进一步省内存的措施**（已内置）：
  1. 在 `main()` 里调用 `limitSkiaResourceCache()`，把 Skia 的 GPU 缓存上限设为 32MB。只对 Skia 后端有效，Impeller 上什么也不做。
  2. 半径 1 的 base 模糊在数学上接近原图（相邻权重只有 e⁻⁵ ≈ 0.7%），直接用原图代替。
  3. 不带色调、倍率为 1 的 upsample 只加 ±0.0045 的抖动噪声，跳过这一遍拷贝。

  后两项让每次刷新的纹理从约 12 张降到 8 张。肉眼看不出差别，但已经不是逐像素一致。
- **实测**（CI 完整脚本，帧率不变）：峰值内存 Windows 约 150MB、macOS 约 165MB，有 GPU 的平台都在 **300MB 以内**；Linux CI 用 CPU 软件渲染，约 335MB。最初在 Windows 上会在 0.6–2.4GB 之间剧烈波动，最高到 5GB；根因和合并路径的做法见下一条。
- **Skia 合并路径**：Skia 后端上（目前是 Windows 和 Linux），reflect 模糊、色调模糊和带色调的 upsample 被合并进玻璃 shader，直接读背景截图，再把玻璃直接画到界面上，不生成任何中间纹理。
  - 合并后的卷积核是用 LM 模糊原本的采样方式对单位脉冲模拟出来的。去掉占比 0.5% 的最外圈后，剩下的 3×3 核用 4 次双线性采样精确实现。
  - 色调计算是原版 upsample shader 的 `main` 主体，被转换脚本原样包装成 `_fl_tint()`。
  - Impeller 上（macOS、iOS、Android）仍走原版多步路径。
- **Shader 预热**：`HyperGlassRenderer.load()` 每个进程只加载一次程序，并用 128×128 的小图把每个 pass 跑一遍。否则 Skia 会在第一次绘制时编译 GPU 管线，第一次点开菜单要卡 1 秒左右。
- 场景里没有任何玻璃表面时（比如菜单收起、外层场景空着），完全不截图，没有额外开销。
- 每张不同尺寸的卡片各需要一次 SDF 渲染。缓存上限是 32 项，变形动画时会频繁重建。

---

## 2. 卸载弹窗

### 2.1 材质【逆向】

来源是 MiuiHome `libapp.so`。HyperOS 的卸载弹窗是从顶部的卸载放置区（`uninstall_drop_target`，类 `PKB::hIb`）展开出来的，它用的材质如下：

| | 模糊 sigma | 混色层（按顺序叠加） |
|---|---|---|
| 浅色 `BlendMaterial.dialogLight` | 32 | `#33F9F9F9 overlay` → `#B3FFFFFF hardLight` |
| 深色 `BlendMaterial.dialogDark` | 56 | `#75000000 colorBurn` → `#52000000 srcOver` |

这就是"玻璃感弱、可读性高"的原因：浅色用 70% 白色做 hardLight 压上去，深色用两层黑色压下去，背景只剩柔和的色块。

```dart
HyperBlendBlur(
  material: isDark ? BlendMaterial.dialogDark : BlendMaterial.dialogLight,
  borderRadius: 32,
  child: ...,
)
```

`hIb` 还引用了一个对象 `uic(1.3, 1.4, 0.08, [0.08, 0.08])`，语义没有确认，可能是饱和度和亮度一类的参数，**没有移植**。

### 2.2 两个按钮

| 按钮 | 颜色 | 依据 |
|---|---|---|
| 确认 / 主操作（"卸载"），放**右侧** | 蓝色实底：浅色 `#3482FF`，深色 `#4788FF`；文字白色 | 【推断】桌面里有一对材质：sigma 60，浅色 `#CCFFFFFF plusDarker` + `#E63482FF srcOver`，深色把后者换成 `#E64788FF`。它们是唯一带强调蓝的混色材质，但没有确认就是按钮在用 |
| 取消（次操作），放**左侧** | 跟随底色：浅色 `black 6%`，深色 `white 12%` 的半透明叠色；文字用正文色（90% 黑或 90% 白） | 【自定】按 HyperOS 的视觉规范，取值是我目测设定的 |

两个按钮等宽，高 50，圆角 25（胶囊形），间距 12，距离弹窗底边 24。

如果想让蓝色按钮也带模糊（完全按推断出的材质来做），可以在 `blend_material.dart` 里加一组：

```dart
static const primaryButtonLight = BlendMaterial(sigma: 60, fallback: Color(0xff3482ff), layers: [
  BlendLayer(Color(0xccffffff), BlendLayerMode.plusDarker),
  BlendLayer(Color(0xe63482ff), BlendLayerMode.srcOver),
]);
static const primaryButtonDark = BlendMaterial(sigma: 60, fallback: Color(0xff4788ff), layers: [
  BlendLayer(Color(0xccffffff), BlendLayerMode.plusDarker),
  BlendLayer(Color(0xe64788ff), BlendLayerMode.srcOver),
]);
```

然后用 `HyperBlendBlur(material: ..., borderRadius: 25)` 包住按钮。注意它和弹窗属于同一个 scene，所以模糊的是弹窗下面的页面，而不是弹窗本身，效果和系统不完全一样。用实底蓝更稳妥。

### 2.3 链接小字（"举报滥用"）的位置

【自定，未逆向】这一块没有找到对应的布局代码，下面是按 HyperOS 弹窗惯例给的建议：

```
┌──────────────────────────────┐
│         卸载"某应用"？          │  标题 19sp w600，居中
│                              │
│   卸载后将删除该应用的所有数据。   │  正文 15sp，60% 正文色，居中
│                              │
│ ☐ 同时清除数据        举报滥用  │  ← 链接小字：13sp，放在正文下方、
│                              │     按钮上方，右对齐（或单独居中一行）
│  [   取消   ]   [   卸载   ]   │  按钮区
└──────────────────────────────┘
```

- 颜色：链接色用 `#3482FF`（深色 `#4788FF`），不加下划线，与主按钮的蓝色呼应。
- 间距：上方离正文 12，下方离按钮 20。
- 点击区域至少 44×44，用 `GestureDetector` 包一层透明 padding。

如果你手上有真机截图，可以按截图微调。这一项我无法从二进制里确认。

---

## 3. 弹出菜单

### 3.1 材质【逆向】

来源是小米天气 `libapp.so`：`hyperos.popup_menu` 的构建函数 0x94d63c 调用 0x56aa6c。

| | 模糊 sigma | 混色层 | 不支持模糊时的纯色 |
|---|---|---|---|
| 浅色 `BlendMaterial.popupMenuLight` | 22 | `#05000000 plusDarker` → `#99FFFFFF softLight` → `#66FFFFFF hardLight` | `#FFFFFF` |
| 深色 `BlendMaterial.popupMenuDark` | 22 | `#1A000000 plusDarker` → `#66565656 luminosity` → `#993F3F3F overlay` | `#242424` |

**浅色和深色的区别：**

- **浅色**：先轻微压暗（plusDarker 2%），再用柔光和强光提亮，底色发白。背景的颜色倾向会保留一些，所以菜单在蓝天上会略带蓝调。
- **深色**：先压暗 10%，用 `luminosity` 换成灰色亮度，去掉大部分背景色相，再用 overlay 叠一层深灰提高对比。结果是偏中性的深灰。
- **文字**：浅色用 `black 90%`，深色用 `white 90%`。图标颜色和文字一致。

同一个函数里还有两组常量，**没有移植**：

- 一个阴影 Record，`(180, 1.2, 0.7, 1, 1, 1, 0.2, 0.5, …)`，字段语义没有解出来。
- 一个三色列表 `[#E6747474 overlay, #99525252 colorDodge, #33D1D1D1 srcOver]`，推测是菜单项按下时的高亮。

```dart
HyperBlendBlur(
  material: isDark ? BlendMaterial.popupMenuDark : BlendMaterial.popupMenuLight,
  borderRadius: 24,
  opacity: t.clamp(0.0, 1.0),
  child: menuItems,
)
```

### 3.2 弹出动画

- 【逆向线索】原版存在动画状态 key `hyperos.popup_menu.shrink_animation_stateful.progress` 和枚举 `PopupMenuAnimationGravity`，说明菜单是从锚点方向"缩放 + 进度"展开的。
- 【自定】具体曲线和数值没有解出来，示例里用的是下面这套。

**1. 驱动方式：小米的弹簧参数**【逆向】

小米天气的 `HyperUI#PopupAnimation` 旁边有两组 `SpringCurveParams`（类 `sEa`，字段依次是阻尼比、响应时长秒、固定时长 ms），每组是一对（展开, 收起）：

| 组 | 展开 | 收起 |
|---|---|---|
| A（pp+0x38a70） | 阻尼比 0.8，响应 0.40s | 阻尼比 0.8，响应 0.28s |
| B（pp+0x38a78） | 阻尼比 0.8，响应 0.25s | 阻尼比 0.8，响应 0.40s |

- 弹出动画函数 0x6ad158 对不同属性分别使用 A、B 两组。【推断】A 驱动几何（变形、文字散开），B 驱动淡入淡出。
- 换算成 Flutter 弹簧：`SpringDescription.withDampingRatio(mass: 1, stiffness: (2π / 响应)², ratio: 阻尼比)`。见 `lib/demo/morph_menu.dart` 的 `hyperSpring` 和 `PopupMotion`。
- 要点：
  - 阻尼比 0.8，回弹很轻。
  - **展开和收起用不同的弹簧**，几何上收起明显比展开快。用同一个弹簧会显得"不够灵动"。
- 控制器要用 `AnimationController.unbounded`，才能过冲；打断时继承当前速度，不会跳变。
- 按钮菜单和设置页的选项弹出共用这套参数。

**2. 菜单从按钮本身变形出来，替换掉按钮**（和小米一致：按钮不会留在菜单下面）

- 几何插值：`rect = Rect.lerp(buttonRect, menuRect, t)`，圆角 `32 → 24`。
  - `menuRect` 以按钮为水平中心，底边和按钮底边对齐，左右夹在屏幕内（各留 12）。
  - 用真实尺寸插值，不用 `Transform.scale`：模糊表面采样的就是它真实所在的位置，过冲时也不会变形失真。
- 交叉淡变：`swap = (t / 0.15).clamp(0, 1)`。
  - 按钮的不透明度是 `1 - swap`；菜单磨砂表面通过 `HyperBlendBlur.opacity` 传入 `swap`。
  - 交换只发生在菜单还接近按钮大小的前 15% 行程里。弹簧收起时会在 0 附近余振，那时磨砂表面完全透明，**不会出现"按钮一瞬间变成磨砂"的闪烁**。不要给按钮和菜单分别设两个不同的阈值。
- 菜单项：按最终尺寸布局，放进 `OverflowBox(alignment: bottomCenter)` 加 `ClipRect`，由不断长大的裁剪区域逐步露出来。
- **文字从点击处向外发散弹出**【自定数值，按小米视觉】：所有菜单项同时从按钮中心（点击的位置）出发，沿各自的方向飞到自己的位置。全部由同一个弹簧值 t 驱动，见 `main.dart` 的 `_popItem`。
  - 位移：`fromTap * (1 - t).clamp(0, 1)`。其中 `fromTap = 按钮中心 - 菜单左上角 - 该项内容中心`，内容中心是 `(72, 8 + 56 * (i + 0.5))`。
  - 缩放：`0.3 + 0.7 * t`，以图标加文字的中心为缩放中心。弹簧过冲时会略超过 100%，形成"弹"的感觉。
  - 不透明度：`((t - 0.1) / 0.4).clamp(0, 1)`。
  - 收起时反向播放，所有项一起缩回按钮。
- 菜单打开期间，按钮要用 `IgnorePointer` 屏蔽点击。

**3. 关闭**：同一个弹簧把目标值改成 0，再在菜单下面铺一个透明的 `GestureDetector`，点击外部即关闭。

**4. 菜单打开弹窗**：在菜单项的 `onTap` 里先 `setMenu(false)`，再 `setDialog(true)`。两个弹簧并行，菜单收起的同时弹窗从底部弹起，衔接很自然。

**弹窗动画参数**：

- 弹簧：`stiffness 300, damping 26`。
- 位置：`top = 底部位置 + (1 - t) * (高度 + 24)`，从屏幕外滑上来。
- 遮罩：`black * 0.3 * t`（深色用 0.45）。

### 3.3 菜单布局（示例取值，【自定】）

| 项 | 取值 |
|---|---|
| 宽度 | 220 |
| 菜单项高度 | 56 |
| 上下内边距 | 8 |
| 圆角 | 24 |
| 图标 | 22，左边距 22，与文字间距 14 |
| 文字 | 16sp w500 |
| 菜单底部离按钮 | 12 |

---

## 4. 设置页（`lib/demo/settings_page.dart`）

> ⚠️ **已知偏差，对照时注意：** demo 的设置页背景沿用了天空，选项分组也用了柔光玻璃卡片。**这是不对的**：真机上设置页是普通的纯色背景加分组列表，背景和选项都不是玻璃。对照小米效果时，设置页只参考下面的顶栏悬浮、返回按钮和选项弹出这三点。背景和卡片外观暂未修复。

- **背景**（与真机不符，见上）：demo 里背景仍是天空，每个分组是一张 `HyperGlass` 卡片。
- **大标题**：在列表顶部（32sp）；滚走后，顶栏中间淡入小标题（18sp）。
- **顶栏悬浮规则**：
  - 页面停在最顶部时，顶栏是透明的，返回按钮**只有箭头**，没有底。
  - 只要内容滚到顶栏下面（滚动偏移 > 0），顶栏就进入"悬浮"状态，同时发生两件事：
    1. 顶栏后面淡入渐变模糊遮罩。透明度 `[1, 0.98, 0.8, 0.5, 0]` 位于 `[0, 0.52, 0.74, 0.85, 1]`，从上到下渐隐（小米天气 `gradientBlur` 的常量，【逆向】）。模糊材质用的是小米天气里唯一一组 sigma 20 的浅深色材质（【推断】）。
    2. 返回按钮浮现出圆形玻璃底（从 0.8 放大到 1 并淡入，约 220ms），因为它现在浮在内容上方。
  - 滚回顶部后，这两样都收回去。
- **选项弹出**：点击"温度单位"，从右侧的取值处用 `MorphMenu` 变形展开。动画、弹簧和文字散开方式都和按钮菜单完全一致。选中项显示蓝色（`#3482FF`）加对勾。
- 温度单位通过 `TemperatureUnit.fahrenheit` 全局生效，首页的卡片和大号温度都会换算。

## 5. 参考

- 玻璃参数完整表和调用链：`docs/GLASS_PARAMS.md`
- 可运行的示例：`lib/main.dart`
- CI 自动截图和性能曲线：`.github/workflows/capture.yml`、`lib/ci/`、`tool/plot_perf.py`
