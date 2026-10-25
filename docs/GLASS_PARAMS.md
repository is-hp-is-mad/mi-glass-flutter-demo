# 小米天气 柔光玻璃 — 真实参数（逆向结果）

来源：`MIUIWeather.apk`（与澎湃 OS 4 `OS4.0.4.0.XPBCNXM` ROM 内版本一致）+ 系统引擎
`system_ext/lib64/libhyper_os_flutter.so`（手机实际加载的引擎，Dart 3.10.1，小米魔改 Flutter/Impeller）。

## 调用链（全部经反汇编 / 反编译 / 模拟执行确认）

1. App 组件 `_Rhb`（`libapp.so` 0x5c44b0）用字面常量构造 4 个 `List<double>`，调用
   `ImageFilter.glass` 工厂（0x5c47d4）→ 生成 dart:ui 对象 `_Ur`（cid 0x153e）。
2. `_Ur` 懒创建原生滤镜（0x84cf80），按引擎版本选择 `initGlassV7…V2/initGlass`；系统引擎支持 V7。
   Dart→C 的 FFI 桩（0x9bfe60）把所有标量常量直接内联成 C ABI 实参。
3. 引擎 `tonic::FfiDispatcher<…ImageFilter::initGlassV7>::Call`（0xe896fc）把实参写入
   `flutter::DlGlassImageFilter`（Unicorn 模拟执行确认字段偏移）。
4. `impeller::Canvas::DrawHyperMaterial` 把 `DlGlassImageFilter` 字段拷入 `impeller::MiGlassContents`。
5. `impeller::MiGlassContents::Render` 把字段填入 `MiGlassV13F16(Legacy)FragmentShader` 的 UBO
   （shader 原文见 `shaders_sys/051_shader.glsl`、`052_shader.glsl`，两版引擎 shader 完全一致）。

## 参数表（V7 实参 → shader uniform）

| V7 参数 | 值 | MiGlassContents | Shader uniform |
|---|---|---|---|
| p2 | 4.0 | +0x60 | (模糊/采样相关, 取整 0..1000) |
| p3 | 1.0 | +0x64 | (同上) |
| p4 | 0.0 | +0x68 | 圆角半径；≤0 表示取形状自身半径（≤ min(w,h)/2，上限 502） |
| p5 | 动态 int（`_Ur` 字段） | — | 未定 |
| p6 | 1 | — | 开关 |
| p7 | **20** | +0x6c | `uShapeEdgePx`（≤ 半边长, ≤502） |
| p8 | **1.6** | +0x70 | `uShapeEdgePow` |
| p9 | **98.2209** | +0x74 | `uShapeThicknessPx`（对象池常量 0x40588e2351a00000） |
| p10 | **110** | +0x78 | `uShapeReflectOffsetPx` |
| p11 | **[-0.5, 0.5, -0.1]** | +0x7c | `uDirectionalLightDirection` |
| p12 | **1.2** | +0x88 | `uDirectionalLightIntensity` |
| p13 | **0.8** | +0x8c | `uDirectionalLightOppositeIntensity` |
| p14 | **0.3** | +0x90 | `uDirectionalLightAngleRange` |
| — | **8.0**（引擎常量） | — | `uDirectionalLightLightWidth` |
| p15 | **0.2** | +0x94 | `uDarker` |
| p16 | **[0.6, 0.9]** | +0x98 | `uDarkerRange` |
| p17 | **1.4** | +0xa0 | `uRefractIOR` |
| p18 | **1.0** | +0xa4 | `uReflectionLighten` |
| p19 | **1.4** | +0xa8 | `uReflectionStrength` |
| p20 | **1.0** | +0xac | `uDirectionalLightEdgePow` |
| p21 | **0.5** | +0xb0 | `uInnerColorMix` |
| p22 | **1.5** | +0xb4 | `uBgColorSaturation` |
| p23 | **[1, 1, 1, 0.05]** | +0xb8 | `uGlassColor` |
| p24 | **0.08** | +0xc8 | `uBgColorBrightness` |
| p25 | **0.3** | +0xcc | `uInnerColorWhite` |
| p26 | **[0.5, 1.0, 0.8, 1.2]** | +0xd0 | 亮度三次贝塞尔 P0..P3 → `uLuminanceValues = (-P0+3P1-3P2+P3, 3P0-6P1+3P2, 3P1-3P0, P0)` |
| p27 | **0.01** | +0xe0 | `uInnerBottom` |
| p28 | **0.24** | +0xe4 | `uLuminanceAmount` |
| p29 | **1.6** | +0xe8 | `uSaturation` |
| p30 | **0.14** | +0xec | `uBrightness` |
| — | 0 | — | `uRefractBlurScale` |
| p31 | **1.5** | +0xf0 | `uColorPow` |
| p32 | **1.0** | +0xf4 | `uAlpha`（× 图层不透明度） |
| p33 | **11** | +0xf8 | `uBurn` = max(1, p33) |
| p34 | **0** | +0xfc | `uUnshade` |
| p35–p51 | 0 / 1 / 5 / 60 / 255 … | +0x100… | 图标光、旋转、bloom 等，天气卡片未启用 |

## 尚未确认
- `p5`（来自 `_Ur` 对象的 int 字段）与 p2/p3 的确切用途（推测与背景模糊降采样/半径相关）。
- 背景模糊（`uRefractTex` / `uBgColorTex`）的 sigma：由 `MiGlassFilterHelper::MakeBaseBlurImage` 决定，未反编译。
- `uSdfTex` 由引擎 `MiRenderHelper::GetOrCreateSdfTexture` 生成，格式由 shader 采样方式推断。
