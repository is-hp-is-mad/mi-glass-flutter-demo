package com.example.hyper_glass

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.Outline
import android.graphics.Paint
import android.graphics.Point
import android.graphics.RectF
import android.view.View
import android.view.ViewGroup
import android.view.ViewOutlineProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.lang.reflect.InvocationTargetException
import java.lang.reflect.Method
import kotlin.math.roundToInt

/**
 * 实验：小米原生柔光玻璃能否透出 **Flutter 实际画面**。
 *
 * 与 [MultiBackendPlatformView] 的区别：
 * - 不画 Android 程序化壁纸，View 本身完全透明，只调用 ROM 的 `setMiGlass` / 混色模糊；
 * - Flutter 侧用 Hybrid Composition（`initExpensiveAndroidView`）嵌入，View 处在真实窗口的 View 树里，
 *   身后是 Flutter 的 `FlutterImageView`；也可切到 TLHC 作对照。
 *
 * 诊断（`diag`）回报：反射方法是否存在、每次调用的结果、父链（判断 HC / TLHC）、FlutterView 当前渲染 View。
 */
object HcGlassLab {
    private val views = HashMap<Int, HcGlassView>()

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "hyper_glass/hc_lab")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "update" -> {
                        @Suppress("UNCHECKED_CAST")
                        val args = (call.arguments as? Map<String, Any?>).orEmpty()
                        val key = (args["surfaceKey"] as? Number)?.toInt()
                        key?.let { views[it]?.apply(args) }
                        result.success(null)
                    }
                    "diag" -> {
                        val key = call.argument<Number>("surfaceKey")?.toInt()
                        result.success(diag(key?.let { views[it] }))
                    }
                    else -> result.notImplemented()
                }
            }
        engine.platformViewsController.registry
            .registerViewFactory("hyper_glass/hc_glass", Factory())
    }

    internal fun attach(key: Int, view: HcGlassView) {
        views[key] = view
    }

    internal fun detach(key: Int, view: HcGlassView) {
        if (views[key] === view) views.remove(key)
    }

    private fun diag(view: HcGlassView?): Map<String, Any?> {
        val r = XiaomiRomReflector
        val methods = linkedMapOf(
            "setMiViewMaterialType" to (r.setMiViewMaterialType != null),
            "setMiGlassBlurRadius" to (r.setMiGlassBlurRadius != null),
            "setMiGlass" to (r.setMiGlass != null),
            "setMiBackgroundBlurMode" to (r.setMiBackgroundBlurMode != null),
            "setMiViewBlurMode" to (r.setMiViewBlurMode != null),
            "setMiBackgroundBlurType" to (r.setMiBackgroundBlurType != null),
            "setMiBackgroundBlurRadius" to (r.setMiBackgroundBlurRadius != null),
            "setMiBackgroundBlendColors" to (r.setMiBackgroundBlendColors != null),
        )
        val out = linkedMapOf<String, Any?>(
            "hyperOsVersion" to r.hyperOsVersion,
            "blurSupportedProp" to r.isBlurSupported,
            "isSupportGlass" to r.isSupportGlass,
            "methods" to methods.entries.joinToString("\n") { "${it.key}: ${if (it.value) "有" else "无"}" },
        )
        if (view == null) {
            out["view"] = "未创建"
            return out
        }
        val chain = mutableListOf<String>()
        var flutterView: ViewGroup? = null
        var p = view.parent
        while (p != null && chain.size < 8) {
            val name = p.javaClass.simpleName
            chain.add(name)
            if (flutterView == null && p is ViewGroup && p.javaClass.name == "io.flutter.embedding.android.FlutterView") {
                flutterView = p
            }
            p = p.parent
        }
        out["composition"] = when {
            chain.any { it.contains("MutatorView") } -> "Hybrid Composition"
            chain.any { it.contains("PlatformViewWrapper") } -> "TLHC（纹理）"
            chain.any { it.contains("SingleViewPresentation") || it.contains("PresentationRoot") } -> "Virtual Display"
            else -> "未知"
        }
        out["parentChain"] = chain.joinToString(" → ")
        out["flutterViewChildren"] = flutterView?.let { fv ->
            (0 until fv.childCount).joinToString(", ") { fv.getChildAt(it).javaClass.simpleName }
        } ?: "未找到 FlutterView"
        out["hardwareAccelerated"] = view.isHardwareAccelerated
        out["size"] = "${view.width}x${view.height}"
        out["calls"] = view.lastCalls.joinToString("\n")
        return out
    }

    private class Factory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
        override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
            @Suppress("UNCHECKED_CAST")
            val params = (args as? Map<String, Any?>).orEmpty()
            return HcGlassView(context, params)
        }
    }
}

/** 完全透明的 View：ROM 材质由系统画在它的身后内容上，自己什么都不画（调试描边除外）。 */
internal class HcGlassView(
    context: Context,
    initial: Map<String, Any?>,
) : View(context), PlatformView {

    private val density = context.resources.displayMetrics.density.coerceAtLeast(1f)
    private var surfaceKey: Int? = null
    private var cornerRadiusPx = 0f
    private var showOutline = false
    private val outlinePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        color = Color.RED
        pathEffect = DashPathEffect(floatArrayOf(12f, 8f), 0f)
    }
    private val rect = RectF()
    var lastCalls: List<String> = emptyList()
        private set

    init {
        setBackgroundColor(Color.TRANSPARENT)
        setWillNotDraw(false)
        outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: Outline) {
                outline.setRoundRect(0, 0, view.width, view.height, cornerRadiusPx)
            }
        }
        apply(initial)
    }

    fun apply(params: Map<String, Any?>) {
        (params["surfaceKey"] as? Number)?.toInt()?.let { key ->
            if (surfaceKey != key) {
                surfaceKey?.let { HcGlassLab.detach(it, this) }
                surfaceKey = key
                HcGlassLab.attach(key, this)
            }
        }
        cornerRadiusPx = ((params["borderRadius"] as? Number)?.toFloat() ?: 0f) * density
        clipToOutline = cornerRadiusPx > 0f
        invalidateOutline()
        showOutline = params["outline"] == true
        outlinePaint.strokeWidth = 1.5f * density

        val calls = mutableListOf<String>()
        fun call(name: String, m: Method?, vararg args: Any?) {
            if (m == null) {
                calls.add("$name: 方法不存在")
                return
            }
            calls.add(
                try {
                    m.invoke(this, *args)
                    "$name: ok"
                } catch (e: InvocationTargetException) {
                    "$name: 抛出 ${e.targetException?.javaClass?.simpleName}: ${e.targetException?.message}"
                } catch (e: Throwable) {
                    "$name: ${e.javaClass.simpleName}: ${e.message}"
                }
            )
        }

        val r = XiaomiRomReflector
        when (params["mode"] as? String ?: "glass") {
            "glass" -> {
                val glass = params["glassParams"] as? FloatArray
                if (glass == null) {
                    calls.add("glassParams 缺失")
                } else {
                    val small = (params["smallBlur"] as? Number)?.toInt() ?: 36
                    val big = (params["bigBlur"] as? Number)?.toInt() ?: 500
                    val scale = params["scaleBlurByDensity"] == true
                    val s = if (scale) (small * density).roundToInt() else small
                    val b = if (scale) (big * density).roundToInt() else big
                    call("setMiViewMaterialType(1)", r.setMiViewMaterialType, 1)
                    call("setMiBackgroundBlurMode(1)", r.setMiBackgroundBlurMode, 1)
                    call("setMiViewBlurMode(1)", r.setMiViewBlurMode, 1)
                    call("setMiBackgroundBlurType(0)", r.setMiBackgroundBlurType, 0)
                    call("setMiGlassBlurRadius($s, $b)", r.setMiGlassBlurRadius, s, b)
                    call("setMiGlass(float[${glass.size}])", r.setMiGlass, glass)
                }
            }
            "blend" -> {
                val radiusPx = (((params["blurRadius"] as? Number)?.toFloat() ?: 40f) * density).roundToInt()
                val colors = params["blendColors"] as? IntArray
                val modes = params["blendModes"] as? IntArray
                call("setMiViewMaterialType(0)", r.setMiViewMaterialType, 0)
                call("setMiBackgroundBlurMode(1)", r.setMiBackgroundBlurMode, 1)
                call("setMiViewBlurMode(1)", r.setMiViewBlurMode, 1)
                call("setMiBackgroundBlurType(0)", r.setMiBackgroundBlurType, 0)
                call("setMiBackgroundBlurRadius($radiusPx)", r.setMiBackgroundBlurRadius, radiusPx)
                if (colors != null && modes != null) {
                    val list = ArrayList<Point>()
                    for (i in 0 until minOf(colors.size, modes.size)) list.add(Point(colors[i], modes[i]))
                    call("setMiBackgroundBlendColors(${list.size})", r.setMiBackgroundBlendColors, list)
                }
            }
            else -> {
                call("setMiBackgroundBlurMode(0)", r.setMiBackgroundBlurMode, 0)
                call("setMiViewBlurMode(0)", r.setMiViewBlurMode, 0)
            }
        }
        lastCalls = calls
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (!showOutline) return
        val inset = outlinePaint.strokeWidth / 2
        rect.set(inset, inset, width - inset, height - inset)
        canvas.drawRoundRect(rect, cornerRadiusPx, cornerRadiusPx, outlinePaint)
    }

    override fun getView(): View = this

    override fun dispose() {
        surfaceKey?.let { HcGlassLab.detach(it, this) }
    }
}
