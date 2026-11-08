# HyperGlass Universal Android SDK (`com.hyperos.glass`)

将小米 HyperOS / MIUI 柔光玻璃（`mi_glass_v13_f16`）、混色模糊（`mi_blend_blur`）、漫射描边（`mi_bloom_stroke`）、按压高光（`mi_press_light`）与弥散阴影（`mi_view_shadow`）从小米官方 ROM 构建产物（`miuix` / `libhwui.so` 私有扩展）完全解耦，移植为 **支持全品牌 Android 设备（Pixel、三星、OPPO、vivo、华为、魅族、一加、小米等）** 的独立通用 Android AAR 库。

---

## 1. 核心解耦架构对比

| 维度 | 原生小米 ROM 强绑定实现 | 重构后通用 `HyperGlass SDK` |
| :--- | :--- | :--- |
| **View 扩展机制** | 反射/直接调用 `android.view.View.setMiGlass`、`setMiBlendBlur`、`setMiBloomStroke` | 独立自定义控件 `HyperGlassView` / `HyperGlassFrameLayout` + 任意控件挂载器 `HyperGlassHelper.attach(view, token)` |
| **底层着色器管线** | 依赖 ROM 私有 `libhwui.so` 非公开符号 | **Android 13+ (API 33)** 标准 `android.graphics.RuntimeShader` (AGSL) + `RenderEffect`；**Android 12 及以下 (API 21–32)** 标准 OpenGL ES 3.0 离屏 FBO (`HyperGlES30Pipeline`) |
| **材质 Token 库** | 运行时查找固件类 `miuix.theme.token.GlassToken` | 完整内化 35+ 项 42 维浮点 `GlassToken`（通用/仿生/着色三大类）、`BloomStrokeToken`、`ColorBlendToken`、`BlendModeToken`、`ShadowToken` |
| **设备能力检测** | 读取 `persist.sys.background_blur_supported`、`ro.mi.os.version.code` | 标准 `Canvas.isHardwareAccelerated()` + `Build.VERSION.SDK_INT` + `ActivityManager` GLES 3.0 与低内存检测 (`HyperGlassCapabilities`) |
| **异常防护与降级** | 非小米设备抛出 `ClassNotFoundException` / `NoSuchMethodError` 或黑屏失效 | 全链路 `try/catch` 保护，低配/禁用硬件加速/着色器编译失败时平滑降级为 `RenderEffect.createBlurEffect` 或半透明超椭圆遮罩 |

---

## 2. 目录结构

```text
hyperglass-sdk/
├── build.gradle.kts
├── settings.gradle.kts
├── hyperglass/                                 # 独立 Android Library 模块 (构建产物: hyperglass-release.aar)
│   ├── build.gradle.kts
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── res/values/attrs.xml                # 自定义 View XML 属性定义
│       └── kotlin/com/hyperos/glass/
│           ├── HyperGlassHelper.kt             # 通用静态挂载工具 HyperGlassHelper.attach(View, GlassToken)
│           ├── widget/
│           │   ├── HyperGlassView.kt           # 独立柔光玻璃 View
│           │   └── HyperGlassFrameLayout.kt    # 独立柔光玻璃容器 FrameLayout
│           ├── pipeline/
│           │   └── HyperGlassPipeline.kt       # 自建背景捕获、LM 多级高斯模糊、折射/反射/描边管线与平滑降级
│           ├── shader/
│           │   └── HyperAgslShaders.kt         # Android 13+ 标准 AGSL RuntimeShader 着色器实现
│           ├── gl/
│           │   └── HyperGlES30Pipeline.kt      # Android 12 及以下 OpenGL ES 3.0 FBO 离屏降级管线
│           ├── token/
│           │   ├── GlassToken.kt               # 内化的 35+ 项原生柔光玻璃 42 维材质常量与 Builder
│           │   ├── BloomStrokeToken.kt         # 内化的 21 维 Bloom 漫射描边常量
│           │   ├── ColorBlendToken.kt          # 内化的 40+ 项多层混色模糊常量
│           │   ├── BlendModeToken.kt           # 完整 46 种 Xiaomi 混合模式枚举 (PLUS_DARKER/LIGHTER/LAB 等)
│           │   ├── ShadowToken.kt              # 弥散阴影预设
│           │   └── MaterialToken.kt            # 复合材质预设 (Overlay_Pill / Dialog / Menu)
│           └── util/
│               ├── HyperGlassCapabilities.kt   # 标准硬件加速与渲染后端嗅探器 (零 SystemProperties 依赖)
│               └── LMGaussianKernel.kt         # 精确移植的 ExecuteLMGaussianBlur 核与三次贝塞尔亮度多项式
└── sample/                                     # 标准 Android Activity 演示工程
    └── src/main/kotlin/com/hyperos/glass/sample/
        └── SampleActivity.kt
```

---

## 3. 快速接入与通用 API 示例

### 方式一：使用 `HyperGlassHelper.attach(...)` 为任意现有 `View` 赋予柔光玻璃效果

无需修改原有布局层级或继承特定父类，即可在标准 Android `Activity` / `Fragment` 中为任意 `View`（如 `LinearLayout`、`CardView`、`Button`、`TextView`）挂载小米柔光玻璃或着色玻璃：

```kotlin
import com.hyperos.glass.HyperGlassHelper
import com.hyperos.glass.token.BloomStrokeToken
import com.hyperos.glass.token.ColorBlendToken
import com.hyperos.glass.token.GlassToken
import com.hyperos.glass.token.ShadowToken

// 1. 为任意 View 挂载通用柔光玻璃 (Common_Large_Regular) + 漫射高光描边 + 弥散阴影
val cardController = HyperGlassHelper.attach(
    target = myCardView,
    token = GlassToken.Common_Large_Regular,
    cornerRadiusDp = 28f,
    bloomStroke = BloomStrokeToken.Glass_Stroke_Middle_Light,
    shadow = ShadowToken.Regular_Light
)
    .setPressLightEnabled(true)     // 开启手指按压折射与径向高光反馈
    .setLiveBackdropUpdates(true)   // 当背景滚动或动画时自动实时采样更新

// 2. 为任意按钮或悬浮栏挂载着色玻璃 (Tint_Purple / Tint_Blue)
HyperGlassHelper.attach(
    target = myFloatingButton,
    token = GlassToken.Tint_Purple,
    cornerRadiusDp = 24f,
    bloomStroke = BloomStrokeToken.Glass_Stroke_Small_Light,
    shadow = ShadowToken.Float_Light
)

// 3. 为任意弹窗或菜单挂载多层混色模糊 (mi_blend_blur)
HyperGlassHelper.attachBlendBlur(
    target = myPopupMenuContainer,
    blendConfig = ColorBlendToken.Overlay_Menu_Dark,
    blurRadiusDp = 66f,
    cornerRadiusDp = 24f,
    bloomStroke = BloomStrokeToken.Glass_Stroke_Middle_Dark
)
```

### 方式二：在代码或 XML 中直接使用 `HyperGlassFrameLayout` / `HyperGlassView`

```xml
<com.hyperos.glass.widget.HyperGlassFrameLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="wrap_content"
    android:padding="20dp"
    app:hg_glassToken="Common_Large_Regular"
    app:hg_bloomStrokeToken="Glass_Stroke_Middle_Light"
    app:hg_shadowToken="Regular_Light"
    app:hg_cornerRadius="28dp"
    app:hg_useSuperellipse="true"
    app:hg_pressLightEnabled="true">

    <TextView
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="HyperOS 柔光玻璃卡片"
        android:textColor="#FFFFFF" />
</com.hyperos.glass.widget.HyperGlassFrameLayout>
```

---

## 4. 在非小米手机（Pixel / 三星 / OPPO / vivo / 华为）上的验证运行说明

### 4.1 构建独立 AAR 与运行示例工程 (`:sample`)

1. 使用 Android Studio 打开 `d:\miuiweather\hyperglass-sdk`，或配置 `ANDROID_HOME` 后在终端执行：
   ```bash
   # 构建通用独立 AAR 包 (输出至 hyperglass/build/outputs/aar/hyperglass-release.aar)
   ./gradlew :hyperglass:assembleRelease

   # 在连接的非小米真机或模拟器 (Pixel / Samsung / OPPO 等) 上安装并运行示例 Activity
   ./gradlew :sample:installDebug
   adb shell am start -n com.hyperos.glass.sample/.SampleActivity
   ```
2. 启动 `SampleActivity` 后，顶部状态栏会实时显示当前设备命中的渲染管线（`Backend`）：
   - **Android 13+ (API 33+) 真机或模拟器（如 Pixel 7/8/9、三星 OneUI 6/7、OPPO ColorOS 13/14/15、vivo OriginOS 4/5）**：自动启用 `AGSL_RUNTIME_SHADER`，通过标准 `android.graphics.RuntimeShader` 完整执行 `mi_glass_v13_f16`（超椭圆 G2 连续曲率边缘法线、透镜折射偏移、双模糊亮度贝塞尔曲线、边缘高光反射、底部内发光与双方向 Bloom 漫射描边）。
   - **Android 12 及以下 (API 21–32) 设备**：自动切换至 `OPENGL_ES_30`，通过标准 `EGL14` + `GLES30` `#version 300 es` 离屏 FBO 渲染完全一致的柔光玻璃与混色模糊着色器。

### 4.2 强制切换渲染后端以验证各级平滑降级（Requirement ④ 验证）

在任意一台设备上（包括 Android 13+ 的 Pixel 模拟器或真机），均可通过 `HyperGlassCapabilities.forcedBackend` 强制模拟低版本或极端低配设备的降级表现：

```kotlin
import com.hyperos.glass.util.HyperGlassCapabilities
import com.hyperos.glass.util.HyperGlassCapabilities.RenderBackend

// 1. 默认自动检测 (Android 13+ -> AGSL, Android <= 12 -> GLES 3.0)
HyperGlassCapabilities.forcedBackend = RenderBackend.AUTO

// 2. 在 Android 13+ 设备上强制验证 Android 12 OpenGL ES 3.0 FBO 离屏管线
HyperGlassCapabilities.forcedBackend = RenderBackend.OPENGL_ES_30

// 3. 强制验证低内存设备降级 (标准模糊 + 材质色调混合)
HyperGlassCapabilities.forcedBackend = RenderBackend.RENDER_EFFECT_BLUR_ONLY

// 4. 强制验证禁用硬件加速 / 极端低配设备的纯遮罩安全降级 (G2 超椭圆半透明材质色 + 柔光描边)
HyperGlassCapabilities.forcedBackend = RenderBackend.FALLBACK_MASK_ONLY
```

### 4.3 验证零小米 ROM 私有符号残留

可在工程根目录执行以下命令，验证 SDK 源码与宿主桥接层已 100% 剔除所有小米私有反射与系统属性：

```powershell
Select-String -Path "d:\miuiweather\hyperglass-sdk\hyperglass\src\**\*.kt" -Pattern "setMiGlass|setMiBlendBlur|SystemProperties|persist\.sys\.background_blur"
```
输出为空，证明无任何 ROM 私有 API 调用残留。
