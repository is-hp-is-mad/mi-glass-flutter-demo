package com.hyperos.glass.sample

import android.app.Activity
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Shader
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.view.ViewGroup.LayoutParams.MATCH_PARENT
import android.view.ViewGroup.LayoutParams.WRAP_CONTENT
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.hyperos.glass.HyperGlassHelper
import com.hyperos.glass.token.BloomStrokeToken
import com.hyperos.glass.token.ColorBlendToken
import com.hyperos.glass.token.GlassToken
import com.hyperos.glass.token.MaterialToken
import com.hyperos.glass.token.ShadowToken
import com.hyperos.glass.util.HyperGlassCapabilities
import com.hyperos.glass.widget.HyperGlassFrameLayout
import kotlin.math.roundToInt

/**
 * Universal Android Sample Activity demonstrating how to use the decoupled HyperGlass SDK
 * on **any Android phone** (Pixel, Samsung, OPPO, vivo, Huawei, Meizu, Xiaomi, etc.):
 *
 * 1. Using [HyperGlassFrameLayout] / `HyperGlassView` custom containers directly;
 * 2. Using [HyperGlassHelper.attach] to endow **any standard Android [View]** (`LinearLayout`,
 *    `TextView`, `Button`, etc.) with Xiaomi HyperOS soft-light glass (`Common_Large_Regular`,
 *    `Common_Small_Thin`), bionic glass (`Bionic_Medium_Regular`), or tinted glass
 *    (`Tint_Purple`, `Tint_Blue`, `Tint_Orange`) + diffuse Bloom rim stroke (`BloomStrokeToken`).
 */
class SampleActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val density = resources.displayMetrics.density
        fun dp(v: Float): Int = (v * density).roundToInt()

        val root = FrameLayout(this)

        // 1. Vibrant multi-gradient + geometric orbs wallpaper backdrop
        val wallpaperView = object : View(this) {
            private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG)
            private val orbPaint = Paint(Paint.ANTI_ALIAS_FLAG)

            override fun onDraw(canvas: Canvas) {
                super.onDraw(canvas)
                val w = width.toFloat()
                val h = height.toFloat()
                bgPaint.shader = LinearGradient(
                    0f, 0f, w, h,
                    intArrayOf(0xFF0F172A.toInt(), 0xFF1E293B.toInt(), 0xFF311042.toInt()),
                    floatArrayOf(0f, 0.55f, 1f),
                    Shader.TileMode.CLAMP
                )
                canvas.drawRect(0f, 0f, w, h, bgPaint)

                // Colorful background orbs to showcase refraction, lens edge distortion & tinting
                orbPaint.color = 0xFF38BDF8.toInt()
                canvas.drawCircle(w * 0.22f, h * 0.20f, w * 0.28f, orbPaint)

                orbPaint.color = 0xFFF43F5E.toInt()
                canvas.drawCircle(w * 0.80f, h * 0.36f, w * 0.26f, orbPaint)

                orbPaint.color = 0xFFA855F7.toInt()
                canvas.drawCircle(w * 0.30f, h * 0.62f, w * 0.30f, orbPaint)

                orbPaint.color = 0xFFF59E0B.toInt()
                canvas.drawCircle(w * 0.76f, h * 0.78f, w * 0.25f, orbPaint)
            }
        }
        root.addView(wallpaperView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))

        // 2. Scrollable foreground showcase cards
        val scrollView = ScrollView(this).apply {
            isVerticalScrollBarEnabled = false
        }
        val contentColumn = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20f), dp(56f), dp(20f), dp(48f))
        }

        // Header showing active rendering backend on this device
        val activeBackend = HyperGlassCapabilities.resolveBackend(this, null)
        val headerView = TextView(this).apply {
            text = "HyperGlass Universal SDK\nBackend: $activeBackend"
            setTextColor(Color.WHITE)
            textSize = 20f
            setPadding(dp(4f), 0, dp(4f), dp(20f))
        }
        contentColumn.addView(headerView)

        // =========================================================================
        // Example A: Custom View `HyperGlassFrameLayout` with Common_Large_Regular
        // =========================================================================
        val commonGlassCard = HyperGlassFrameLayout(this).apply {
            setGlassToken(GlassToken.Common_Large_Regular)
            setBloomStroke(BloomStrokeToken.Glass_Stroke_Middle_Light)
            setShadow(ShadowToken.Regular_Light)
            setCornerRadiusDp(28f)
            setPressLightEnabled(true)
            setPadding(dp(22f), dp(20f), dp(22f), dp(20f))
        }
        commonGlassCard.addView(
            buildCardLabel(
                title = "1. HyperGlassFrameLayout (Common_Large_Regular)",
                subtitle = "AGSL RuntimeShader mi_glass_v13_f16 + G2 Superellipse + BloomStroke + Press Light (Tap & hold)"
            )
        )
        contentColumn.addView(
            commonGlassCard,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { bottomMargin = dp(18f) }
        )

        // =========================================================================
        // Example B: `HyperGlassHelper.attach(...)` on a standard Android LinearLayout
        //            using Tint_Purple & Tint_Blue
        // =========================================================================
        val purpleStandardLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(22f), dp(20f), dp(22f), dp(20f))
            addView(
                buildCardLabel(
                    title = "2. HyperGlassHelper.attach(view, GlassToken.Tint_Purple)",
                    subtitle = "Attached to a standard android.widget.LinearLayout without subclassing"
                )
            )
        }
        HyperGlassHelper.attach(
            target = purpleStandardLayout,
            token = GlassToken.Tint_Purple,
            cornerRadiusDp = 28f,
            bloomStroke = BloomStrokeToken.Glass_Stroke_Small_Light,
            shadow = ShadowToken.Float_Light
        ).setPressLightEnabled(true).setLiveBackdropUpdates(true)

        contentColumn.addView(
            purpleStandardLayout,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { bottomMargin = dp(18f) }
        )

        val blueStandardLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(22f), dp(20f), dp(22f), dp(20f))
            addView(
                buildCardLabel(
                    title = "3. HyperGlassHelper.attach(view, GlassToken.Tint_Blue)",
                    subtitle = "Tinted soft-light glass with dual-blur luminance curve & edge reflection"
                )
            )
        }
        HyperGlassHelper.attach(
            target = blueStandardLayout,
            token = GlassToken.Tint_Blue,
            cornerRadiusDp = 28f,
            bloomStroke = BloomStrokeToken.Glass_Stroke_Small_Light,
            shadow = ShadowToken.Float_Light
        ).setLiveBackdropUpdates(true)

        contentColumn.addView(
            blueStandardLayout,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { bottomMargin = dp(18f) }
        )

        // =========================================================================
        // Example C: Bionic Glass (`Bionic_Medium_Regular`) & `Common_Small_Thin`
        // =========================================================================
        val bionicLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(22f), dp(20f), dp(22f), dp(20f))
            addView(
                buildCardLabel(
                    title = "4. Bionic Glass (GlassToken.Bionic_Medium_Regular)",
                    subtitle = "High-refraction bionic lens edge (IOR = 3.0, burn = 1.0)"
                )
            )
        }
        HyperGlassHelper.attach(
            target = bionicLayout,
            token = GlassToken.Bionic_Medium_Regular,
            cornerRadiusDp = 28f,
            bloomStroke = BloomStrokeToken.Flutter_Card_Light,
            shadow = ShadowToken.Regular_Light
        ).setLiveBackdropUpdates(true)

        contentColumn.addView(
            bionicLayout,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { bottomMargin = dp(18f) }
        )

        // =========================================================================
        // Example D: Multi-layer Color Blend Blur (`mi_blend_blur`)
        // =========================================================================
        val blendBlurLayout = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(22f), dp(20f), dp(22f), dp(20f))
            addView(
                buildCardLabel(
                    title = "5. ColorBlendBlur (Overlay_Menu_Dark)",
                    subtitle = "Multi-layer PLUS_DARKER + LUMINOSITY + OVERLAY blend over LM Gaussian blur"
                )
            )
        }
        HyperGlassHelper.attachBlendBlur(
            target = blendBlurLayout,
            blendConfig = ColorBlendToken.Overlay_Menu_Dark,
            blurRadiusDp = 66f,
            cornerRadiusDp = 26f,
            bloomStroke = BloomStrokeToken.Glass_Stroke_Middle_Dark,
            shadow = ShadowToken.High_Dark
        ).setLiveBackdropUpdates(true)

        contentColumn.addView(
            blendBlurLayout,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT).apply { bottomMargin = dp(18f) }
        )

        // =========================================================================
        // Example E: Composite MaterialToken (`MaterialToken.Overlay_Pill_Light`)
        // =========================================================================
        val pillView = TextView(this).apply {
            text = "6. MaterialToken.Overlay_Pill_Light (Capsule Pill)"
            setTextColor(Color.WHITE)
            textSize = 15f
            gravity = Gravity.CENTER
            setPadding(dp(24f), dp(16f), dp(24f), dp(16f))
        }
        HyperGlassHelper.attachMaterial(pillView, MaterialToken.Overlay_Pill_Light)
            .setCornerRadiusDp(32f)
            .setLiveBackdropUpdates(true)

        contentColumn.addView(
            pillView,
            LinearLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT)
        )

        scrollView.addView(contentColumn, FrameLayout.LayoutParams(MATCH_PARENT, WRAP_CONTENT))
        root.addView(scrollView, FrameLayout.LayoutParams(MATCH_PARENT, MATCH_PARENT))

        setContentView(root)
    }

    private fun buildCardLabel(title: String, subtitle: String): View {
        val density = resources.displayMetrics.density
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        box.addView(
            TextView(this).apply {
                text = title
                setTextColor(Color.WHITE)
                textSize = 16f
                paint.isFakeBoldText = true
            }
        )
        box.addView(
            TextView(this).apply {
                text = subtitle
                setTextColor(0xD9FFFFFF.toInt())
                textSize = 13f
                setPadding(0, (6 * density).roundToInt(), 0, 0)
            }
        )
        return box
    }
}
