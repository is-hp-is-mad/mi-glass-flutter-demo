# HyperGlass 通用化与移植

把 HyperOS 4 的柔光玻璃、控件和动效用到其他 Flutter 项目。

**现状：** 全部设计都在 `packages/hyper_glass` 这个包里，showcase 自己也只通过它使用。在只依赖这个包的空白 Windows 项目上验证过：换主色、深色主题、页面、Tab 栏、下拉和对话框都正常。还没解决的是平台和授权问题，见第 7、8 节。

可信度标记：

- **【逆向】** 从 ROM 读出的常量或着色器，可以直接用。
- **【推断】** 由逆向线索推出，对应关系没有完全确认。
- **【自定】** 这里自己定的，可以按项目修改。

---

## 1. 通用化的验收标准

全部满足才算通用，第 10 节是对应的检查清单。

1. 接入方只依赖一个包，不需要拷贝 showcase 的任何文件。
2. 不依赖 `Os`、`OsScope`、`CatalogHost`、`Wallpaper`。
3. 明暗跟随宿主的 `Theme`，主色、字体可由宿主配置。
4. 漏掉初始化或放错位置时，得到明确的报错，而不是空白或静默失效。
5. 包内不含小米字体和 ROM 素材。

---

## 2. 分层

依赖方向只能向下：

```
showcase        lib/（页面、壁纸、模拟状态栏、CI 走查）   只作示例
hyper_ui.dart   控件、弹出层、主题                       可选
hyper_glass.dart  材质                                  只要玻璃时只引这个
```

| 入口 | 内容 |
|---|---|
| `package:hyper_glass/hyper_glass.dart` | `HyperGlass`、`HyperGlassScene`、`HyperBlendBlur`、`ViewShadow`、`GlassFilter`、`BlendMaterial`、`GlassPresets`、`GlassTokens`、`BlendPresets`、`BloomTokens` |
| `package:hyper_glass/hyper_ui.dart` | 主题 `HyperTheme`；令牌 `Hy`；动效 `SpringValue`、`hyperSpring`、`Decelerate`、`ArcMotion`；按压 `Pressable`、`GlassPress`；表面 `FloatSurface`、`FloatingBar`；页面 `HyperPage`；设置项 `PrefCategory`、`PrefCard`、`PrefIcon`、`PrefRow`；控件 `HySwitch`、`HyCheck`、`HySeek`、`HyButton`、`HySegmented`、`HyChips`、`HyTextTabs`、`HyField`、`HyperDialogButton`；弹出层 `HyperOverlay`、`ArcMenu`、`HyperMenuItem`；`HyperBottomBar`；`TextMasked` |

留在 showcase、不进包的：`Os`、`OsScope`、`StatusBar`、`AppGlyph`（模拟系统用）、手绘壁纸、`ci/`，以及手机比例外框和回弹滚动（在 `main.dart`，按需参考）。

---

## 3. 接入

包还没有发布，用 path 或 git 依赖。着色器由包自己注册，宿主不用改 `flutter:` 配置。

```yaml
dependencies:
  hyper_glass:
    path: ../hyper_glass
```

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HyperGlass.init();
  runApp(const MyApp());
}
```

### 只用材质

```dart
HyperGlassScene(
  background: MyBackground(),
  child: HyperGlass(
    filter: GlassPresets.notification,
    borderRadius: 24,
    bloom: BloomTokens.strokeMiddleLight,
    child: content,
  ),
)
```

### 用控件和弹出层

把 `HyperOverlay` 放在页面外面。明暗跟随 `Theme`，字体跟随默认文本样式；只有想换强调色时才需要 `HyperTheme`。

```dart
HyperTheme(
  primary: myColor,
  child: Scaffold(
    body: HyperOverlay(
      floating: HyperBottomBar(
        index: tab,
        onChanged: onTab,
        items: const [HyperBottomBarItem('首页', Icons.home_outlined, Icons.home)],
      ),
      child: HyperPage(title: '设置', children: rows),
    ),
  ),
);

final overlay = HyperOverlay.of(context);
overlay.select(rowContext, options, selected, onPick);  // 设置项的下拉
overlay.menu(buttonContext, items);                     // 按钮菜单
overlay.dialog('标题', '内容', onConfirm: onOk);
overlay.sheet(content, height: 300);
overlay.toast('已保存');
overlay.refresh();  // 页面不是因为滚动而变化时调用，比如切 Tab、转场
```

`rowContext` 用设置项行的 `GlobalKey.currentContext`。对话框默认按钮文字是中文，用 `cancel`、`confirm` 参数换。

要自己管理菜单时，用 `ArcMotion` + `ArcMenu`，例子见 `lib/screens/weather.dart`。

漏掉初始化、玻璃不在场景内、上方没有 `HyperOverlay`，都会报错并说明原因。其中初始化的检查是 assert，只在 debug 下生效。

---

## 4. 使用规则

这些是材质本身的约束，通用化之后依然成立。

### 选材质

| 场景 | 用什么 |
|---|---|
| 有内容衬底的卡片、通知 | `HyperGlass` + `GlassPresets` / `GlassTokens`（折射玻璃） |
| 悬浮按钮、Tab 栏、弹出菜单、对话框 | `HyperBlendBlur` + `BlendMaterial`（混色模糊） |
| 普通设置页 | 不用玻璃：纯色背景加分组列表，这才是真机的样子 |

【逆向】系统的“thin glass”控件实际是混色模糊，没有折射。在纯白背景上玻璃几乎不可见，这是材质本身的特性，应改用混色模糊。

### 场景

- 玻璃只能看到所在 `HyperGlassScene` 的 `background`，看不到同一 `child` 里的其他内容。
- `HyperGlass` 和 `HyperBlendBlur` 必须在场景内，否则报错。
- 不要放进 `background`，否则会采样自己。
- 浮层要模糊整个页面时，再包一层场景，内层场景作为外层的 `background`。`HyperOverlay` 已经做了这件事。
- 背景在动，或玻璃相对背景移动时，用 `animate: true`。静态内容用 `false`，省很多。
- 自己写外层场景时，`animate` 跟随浮层是否打开：`animate: motion.active`。

### 单位

- `BlendMaterial.sigma` 和 miuix 的模糊值实际是 **dp 半径**，不是高斯 sigma。转换为 `sigma = radius × 0.1125`，当 sigma 直接用会模糊约 9 倍，这是早期玻璃发闷的原因。
- 令牌里的长度按 3x 屏的物理像素给出，渲染时已按 `dpr / 3` 缩放，不要再缩放一次。
- `ShadowToken` 的值同样是 3x 物理像素。

### 不要用普通阴影和动画代替

| 项 | 正确做法 | 原因 |
|---|---|---|
| 阴影 | `ViewShadow` | 【逆向】系统阴影末端有 `smoothstep(0.1, 1, a)`，最深约 12%，`BoxShadow` 表达不了 |
| 弹簧 | `hyperSpring(阻尼比, 响应秒数)`，`AnimationController.unbounded` | 要能过冲，打断时继承速度 |
| 按压 | `Pressable` / `GlassPress` | 【逆向】FolmeTouch：最长边收缩 10dp，下限 0.9 |
| 菜单 | `ArcMotion` + `ArcMenu` | 【逆向】`ArcAnimation`：尺寸和位置两组弹簧，收起时互换 |

菜单默认向下展开，从锚点顶部开始（`getYInWindowAlignTop`），放不下才贴底或翻转。这个规则已经在 `HyperOverlay` 里，直接用 `overlay.select`、`overlay.menu` 即可。

### Tab 栏

【逆向】用的是原生 `BottomNavigator`：高 56，最大宽 344，边距 24，`Pured_Thin_Glass`，`maskBlur 20`，`Glass_Stroke_Middle`，阴影 Regular；选中胶囊 `#0f000000`（深色 `#1fffffff`）内缩 3，图标选中时换实心。胶囊前缘用快弹簧 (0.7, 0.4)，后缘用慢弹簧 (0.75, 0.5)。不同应用配方不同，相册的 `Hy.flutterBloom` 明显更亮，不要混用。

---

## 5. 还没做的

原定的解耦已经完成。下面是接入其他项目前还要处理的：

| 项 | 说明 |
|---|---|
| 发布方式 | 目前只能 path 或 git 依赖，仓库结构还没定 |
| 文案 | 对话框默认按钮文字是中文，只能逐次传参，没有接入 `Localizations` |
| 菜单锚点 | `overlay.menu` 总是从锚点右对齐向下展开，靠左的按钮可能超出屏幕左边，要用 `menuRectFor` + `ArcMenu` 自己算 |
| 状态栏 | `HyperPage` 和 `FloatingBar` 默认取 `MediaQuery` 的安全区，真机效果没验证 |
| 对话框高度 | 固定 216，长文本会溢出 |
| 暗色描边 | 对话框深色下用的 `strokeSmallLight` 沿用自 showcase，没有和真机对照 |
| 根目录 demo | 仓库根目录的 `PORTING.md` 和 demo 是更早的版本，没有迁到这个包 |

---

## 6. 目录

```
packages/hyper_glass/
  lib/hyper_glass.dart       材质入口
  lib/hyper_ui.dart          控件入口
  lib/src/                   材质实现
  lib/src/ui/                theme、kit、prefs、arc_menu、overlay、bottom_bar
  shaders/
  test/
lib/                         showcase，第一个使用者
```

包的测试在 `packages/hyper_glass` 下运行 `flutter test`。

---

## 7. 平台与性能现状

Flutter 3.35.7，`sdk: ^3.9.2`。代码用 `ImageFilter.isShaderFilterSupported` 判断是否为 Impeller，这是间接判断，升级 Flutter 时要重新验证。

| 平台 | 后端 | 状态 |
|---|---|---|
| Windows、Linux、macOS | Skia | CI 全部跑通，普通场景帧间隔 p50 约 17 ms |
| Android | Impeller | 只在 SwiftShader 模拟器上跑过，1–7 fps，不代表真机 |
| iOS | Impeller | 只在模拟器 debug 下跑过 |
| Web | 未验证 | 示例用了 `dart:io`，包本身没用，但没有验证过 |

**未解决的问题：**

- **Impeller 没有真机验证：** 帧数据有，画面效果没有看过。
- **Impeller 上玻璃页面停顿：** 两个模拟器上，材质、特性、天气页都有数秒停顿，原因未定位，可能只是没有真 GPU。
- **首次使用的停顿（Skia）：** 第一次显示玻璃页面有明显停顿，Windows 上约 0.2–0.8 秒。预热只能覆盖一部分，总开销还没降下来。
- **内存阶梯上涨：** 进入玻璃页面后不回落，没有验证是缓存还是泄漏。

**内存相关的硬规则：** 每帧刷新的捕获必须用异步 `toImage`，靠它做背压。改回 `toImageSync` 加每帧刷新，内存会在几秒内涨到数 GB。`toImageSync` 只用于一次性的首帧捕获。

---

## 8. 法律与资产

**接入前必须确认，这不是法律意见。**

- **着色器和令牌：** 包的 `shaders/` 里 5 个 `mi_glass_*`、`mi_lm_*` 由系统引擎的着色器转换而来，令牌、弹簧和常量都来自 ROM。这些内容的权利状态没有确认，仓库目前也没有 LICENSE 文件。商业项目使用前应先做法律评估。
- **MiSans：** 不随仓库分发，由 `tool/fetch_misans.py` 从官方地址下载。用于其他项目前要自行确认授权范围，包内默认不带字体。
- **视觉风格：** 仿制系统界面用于非小米产品时，也要考虑商业外观和用户混淆的问题。
- **不要提交：** `rom/` 下的任何文件。

---

## 9. 维护规则

- `packages/hyper_glass/shaders/` 里的 `mi_glass_*`、`mi_lm_*` 和 `shader_layout.g.dart` 是生成物，不要手改，改转换脚本。
- `glass_tokens.g.dart` 由 `flutter/tools/gen_tokens.py` 生成。
- 改参数前先查来源，ROM 里有的值不要凭感觉调。对照真机时用深色、高对比壁纸，真机没有 Dock 底板。
- 新增控件时注明来源：miuix 类名、ROM 地址，或标为【自定】。
- 跟性能有关的改动，用 `SHOWCASE_PERF` 至少跑 3 轮再下结论，单轮波动很大。首次打开页面的开销要专门测，不能只看滚动。

---

## 10. 验收清单

- [x] 新建空白 Flutter 项目，只加这一个依赖就能跑起来（Windows）
- [x] 例子里没有 `Os`、`OsScope`、`CatalogHost`
- [x] 跟随宿主 `Theme` 切换明暗，换主色生效；字体跟随默认文本样式
- [x] 漏掉初始化、不在场景内，都有明确的报错
- [x] 菜单、对话框、底部面板、轻提示、Tab 栏能在 `HyperOverlay` 下直接调用
- [x] 包内不含字体、`rom/` 内容
- [x] 着色器以 package 路径加载成功（Windows）
- [ ] 解耦后的代码在 CI 五个平台跑通
- [ ] Android、iOS 真机上看过画面并测过帧率
- [ ] 第 8 节的授权问题有明确结论
