package com.example.hyper_glass

import android.graphics.SurfaceTexture
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES20
import android.util.Log
import android.view.Surface
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * Android Native GPU Weather Texture Plugin.
 *
 * Provides hardware-accelerated zero-copy procedural weather animation
 * rendered via EGL14 and OpenGL ES directly into an Android [Surface] backed by
 * Flutter's [TextureRegistry.SurfaceTextureEntry].
 *
 * Implements MethodChannel `com.hyperos.glass/gpu_engine`.
 */
class WeatherGpuPlugin(
    messenger: BinaryMessenger,
    private val textureRegistry: TextureRegistry
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "com.hyperos.glass/gpu_engine")
    private val instances = ConcurrentHashMap<Long, WeatherTextureInstance>()

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                val width = (call.argument<Number>("width"))?.toInt() ?: 800
                val height = (call.argument<Number>("height"))?.toInt() ?: 600
                val sceneType = call.argument<String>("sceneType")
                    ?: call.argument<String>("type")
                    ?: "cloudy"
                val intensity = (call.argument<Number>("intensity"))?.toFloat() ?: 1.0f
                val isDark = call.argument<Boolean>("isDark") ?: false
                val timeOfDay = (call.argument<Number>("timeOfDay"))?.toFloat() ?: 0.5f

                try {
                    val entry = textureRegistry.createSurfaceTexture()
                    val textureId = entry.id()
                    val instance = WeatherTextureInstance(
                        entry = entry,
                        initialWidth = width,
                        initialHeight = height,
                        sceneType = sceneType,
                        intensity = intensity,
                        isDark = isDark,
                        timeOfDay = timeOfDay
                    )
                    instances[textureId] = instance
                    instance.start()
                    result.success(textureId)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to initialize WeatherTextureInstance", e)
                    result.error("INIT_FAILED", e.message, null)
                }
            }
            "resize" -> {
                val textureId = (call.argument<Number>("textureId"))?.toLong()
                val width = (call.argument<Number>("width"))?.toInt()
                val height = (call.argument<Number>("height"))?.toInt()

                if (textureId == null || width == null || height == null) {
                    result.error("INVALID_ARGS", "Missing textureId, width, or height", null)
                    return
                }

                val instance = instances[textureId]
                if (instance != null) {
                    instance.resize(width, height)
                    result.success(null)
                } else {
                    result.error("NOT_FOUND", "Texture instance $textureId not found", null)
                }
            }
            "updateWeather" -> {
                val textureId = (call.argument<Number>("textureId"))?.toLong()
                val sceneType = call.argument<String>("sceneType") ?: call.argument<String>("type")
                val intensity = (call.argument<Number>("intensity"))?.toFloat()
                val isDark = call.argument<Boolean>("isDark")
                val timeOfDay = (call.argument<Number>("timeOfDay"))?.toFloat()

                if (textureId == null) {
                    result.error("INVALID_ARGS", "Missing textureId", null)
                    return
                }

                val instance = instances[textureId]
                if (instance != null) {
                    instance.updateWeather(
                        sceneType = sceneType,
                        intensity = intensity,
                        isDark = isDark,
                        timeOfDay = timeOfDay
                    )
                    result.success(null)
                } else {
                    result.error("NOT_FOUND", "Texture instance $textureId not found", null)
                }
            }
            "dispose" -> {
                val textureId = (call.argument<Number>("textureId"))?.toLong()
                if (textureId != null) {
                    val instance = instances.remove(textureId)
                    instance?.dispose()
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        for ((_, instance) in instances) {
            instance.dispose()
        }
        instances.clear()
    }

    companion object {
        private const val TAG = "WeatherGpuPlugin"

        private fun parseWeatherType(sceneType: String?): Int {
            return when (sceneType?.lowercase()?.trim()) {
                "sunny", "clear" -> 0
                "cloudy", "overcast", "fog" -> 1
                "rain", "drizzle", "heavyrain" -> 2
                "snow", "blizzard" -> 3
                "thunder", "storm", "lightning" -> 4
                else -> 1
            }
        }
    }

    /**
     * Dedicated background render pipeline for an individual Flutter texture surface.
     */
    private class WeatherTextureInstance(
        private val entry: TextureRegistry.SurfaceTextureEntry,
        initialWidth: Int,
        initialHeight: Int,
        sceneType: String,
        intensity: Float,
        isDark: Boolean,
        timeOfDay: Float
    ) {
        private val surfaceTexture: SurfaceTexture = entry.surfaceTexture()
        private val surface: Surface
        private val width = AtomicInteger(initialWidth.coerceAtLeast(1))
        private val height = AtomicInteger(initialHeight.coerceAtLeast(1))
        private val needsResize = AtomicBoolean(false)
        private val running = AtomicBoolean(true)

        @Volatile
        private var weatherType = parseWeatherType(sceneType)

        @Volatile
        private var intensityVal = intensity

        @Volatile
        private var isDarkVal = isDark

        @Volatile
        private var timeOfDayVal = timeOfDay

        private val renderThread: Thread

        init {
            val safeW = initialWidth.coerceAtLeast(1)
            val safeH = initialHeight.coerceAtLeast(1)
            surfaceTexture.setDefaultBufferSize(safeW, safeH)
            surface = Surface(surfaceTexture)
            renderThread = Thread({ runRenderLoop() }, "WeatherGpuRenderThread-${entry.id()}")
        }

        fun start() {
            renderThread.start()
        }

        fun resize(w: Int, h: Int) {
            val safeW = w.coerceAtLeast(1)
            val safeH = h.coerceAtLeast(1)
            if (width.get() != safeW || height.get() != safeH) {
                width.set(safeW)
                height.set(safeH)
                needsResize.set(true)
            }
        }

        fun updateWeather(
            sceneType: String?,
            intensity: Float?,
            isDark: Boolean?,
            timeOfDay: Float?
        ) {
            if (sceneType != null) {
                weatherType = parseWeatherType(sceneType)
            }
            if (intensity != null) {
                intensityVal = intensity
            }
            if (isDark != null) {
                isDarkVal = isDark
            }
            if (timeOfDay != null) {
                timeOfDayVal = timeOfDay
            }
        }

        fun dispose() {
            if (running.compareAndSet(true, false)) {
                renderThread.interrupt()
                try {
                    renderThread.join(500)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                }
            }
        }

        private fun runRenderLoop() {
            var eglDisplay: EGLDisplay = EGL14.EGL_NO_DISPLAY
            var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
            var eglSurface: EGLSurface = EGL14.EGL_NO_SURFACE
            var program = 0

            try {
                eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
                if (eglDisplay == EGL14.EGL_NO_DISPLAY) {
                    Log.e(TAG, "eglGetDisplay failed: ${EGL14.eglGetError()}")
                    return
                }

                val version = IntArray(2)
                if (!EGL14.eglInitialize(eglDisplay, version, 0, version, 1)) {
                    Log.e(TAG, "eglInitialize failed: ${EGL14.eglGetError()}")
                    return
                }

                val configAttribs = intArrayOf(
                    EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                    EGL14.EGL_RED_SIZE, 8,
                    EGL14.EGL_GREEN_SIZE, 8,
                    EGL14.EGL_BLUE_SIZE, 8,
                    EGL14.EGL_ALPHA_SIZE, 8,
                    EGL14.EGL_DEPTH_SIZE, 0,
                    EGL14.EGL_STENCIL_SIZE, 0,
                    EGL14.EGL_SURFACE_TYPE, EGL14.EGL_WINDOW_BIT,
                    EGL14.EGL_NONE
                )
                val configs = arrayOfNulls<EGLConfig>(1)
                val numConfigs = IntArray(1)
                if (!EGL14.eglChooseConfig(eglDisplay, configAttribs, 0, configs, 0, 1, numConfigs, 0) || numConfigs[0] == 0) {
                    Log.e(TAG, "eglChooseConfig failed: ${EGL14.eglGetError()}")
                    return
                }
                val eglConfig = configs[0]!!

                val contextAttribs = intArrayOf(
                    EGL14.EGL_CONTEXT_CLIENT_VERSION, 2,
                    EGL14.EGL_NONE
                )
                eglContext = EGL14.eglCreateContext(eglDisplay, eglConfig, EGL14.EGL_NO_CONTEXT, contextAttribs, 0)
                if (eglContext == EGL14.EGL_NO_CONTEXT) {
                    Log.e(TAG, "eglCreateContext failed: ${EGL14.eglGetError()}")
                    return
                }

                val surfaceAttribs = intArrayOf(EGL14.EGL_NONE)
                eglSurface = EGL14.eglCreateWindowSurface(eglDisplay, eglConfig, surface, surfaceAttribs, 0)
                if (eglSurface == EGL14.EGL_NO_SURFACE) {
                    Log.e(TAG, "eglCreateWindowSurface failed: ${EGL14.eglGetError()}")
                    return
                }

                if (!EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)) {
                    Log.e(TAG, "eglMakeCurrent failed: ${EGL14.eglGetError()}")
                    return
                }

                program = createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
                if (program == 0) {
                    Log.e(TAG, "Failed to compile/link GL program")
                    return
                }

                val aPosLoc = GLES20.glGetAttribLocation(program, "a_pos")
                val uTimeLoc = GLES20.glGetUniformLocation(program, "u_time")
                val uWeatherTypeLoc = GLES20.glGetUniformLocation(program, "u_weather_type")
                val uIsDarkLoc = GLES20.glGetUniformLocation(program, "u_is_dark")
                val uIntensityLoc = GLES20.glGetUniformLocation(program, "u_intensity")
                val uResolutionLoc = GLES20.glGetUniformLocation(program, "u_resolution")

                val quadVertices = ByteBuffer.allocateDirect(8 * 4)
                    .order(ByteOrder.nativeOrder())
                    .asFloatBuffer()
                    .apply {
                        put(
                            floatArrayOf(
                                -1.0f, -1.0f,
                                 1.0f, -1.0f,
                                -1.0f,  1.0f,
                                 1.0f,  1.0f
                            )
                        )
                        position(0)
                    }

                var lastTimeNanos = System.nanoTime()
                var animTime = 0.0f

                while (running.get()) {
                    val frameStartNanos = System.nanoTime()
                    val dt = ((frameStartNanos - lastTimeNanos) / 1_000_000_000.0).toFloat().coerceIn(0.0f, 0.1f)
                    lastTimeNanos = frameStartNanos
                    animTime += dt

                    if (needsResize.compareAndSet(true, false)) {
                        val newW = width.get().coerceAtLeast(1)
                        val newH = height.get().coerceAtLeast(1)
                        surfaceTexture.setDefaultBufferSize(newW, newH)
                        EGL14.eglMakeCurrent(eglDisplay, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
                        if (eglSurface != EGL14.EGL_NO_SURFACE) {
                            EGL14.eglDestroySurface(eglDisplay, eglSurface)
                            eglSurface = EGL14.EGL_NO_SURFACE
                        }
                        eglSurface = EGL14.eglCreateWindowSurface(eglDisplay, eglConfig, surface, surfaceAttribs, 0)
                        if (eglSurface == EGL14.EGL_NO_SURFACE) {
                            Log.e(TAG, "eglCreateWindowSurface failed on resize")
                            break
                        }
                        if (!EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)) {
                            Log.e(TAG, "eglMakeCurrent failed on resize")
                            break
                        }
                    }

                    val currentW = width.get().coerceAtLeast(1)
                    val currentH = height.get().coerceAtLeast(1)
                    GLES20.glViewport(0, 0, currentW, currentH)
                    GLES20.glClearColor(0f, 0f, 0f, 1f)
                    GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

                    GLES20.glUseProgram(program)
                    GLES20.glUniform1f(uTimeLoc, animTime)
                    GLES20.glUniform1i(uWeatherTypeLoc, weatherType)
                    GLES20.glUniform1f(uIsDarkLoc, if (isDarkVal) 1.0f else 0.0f)
                    GLES20.glUniform1f(uIntensityLoc, intensityVal)
                    GLES20.glUniform2f(uResolutionLoc, currentW.toFloat(), currentH.toFloat())

                    quadVertices.position(0)
                    GLES20.glEnableVertexAttribArray(aPosLoc)
                    GLES20.glVertexAttribPointer(aPosLoc, 2, GLES20.GL_FLOAT, false, 0, quadVertices)
                    GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
                    GLES20.glDisableVertexAttribArray(aPosLoc)

                    if (!EGL14.eglSwapBuffers(eglDisplay, eglSurface)) {
                        val err = EGL14.eglGetError()
                        if (err == EGL14.EGL_BAD_SURFACE || err == EGL14.EGL_CONTEXT_LOST) {
                            Log.w(TAG, "eglSwapBuffers lost surface or context: $err")
                            break
                        }
                    }

                    val elapsedMs = (System.nanoTime() - frameStartNanos) / 1_000_000
                    val sleepMs = 16L - elapsedMs
                    if (sleepMs > 0) {
                        try {
                            Thread.sleep(sleepMs)
                        } catch (_: InterruptedException) {
                            break
                        }
                    }
                }
            } catch (t: Throwable) {
                Log.e(TAG, "Exception in render loop", t)
            } finally {
                if (program != 0) {
                    GLES20.glDeleteProgram(program)
                }
                if (eglDisplay != EGL14.EGL_NO_DISPLAY) {
                    EGL14.eglMakeCurrent(eglDisplay, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
                    if (eglSurface != EGL14.EGL_NO_SURFACE) {
                        EGL14.eglDestroySurface(eglDisplay, eglSurface)
                    }
                    if (eglContext != EGL14.EGL_NO_CONTEXT) {
                        EGL14.eglDestroyContext(eglDisplay, eglContext)
                    }
                    EGL14.eglTerminate(eglDisplay)
                }
                try {
                    surface.release()
                } catch (_: Throwable) {}
                try {
                    entry.release()
                } catch (_: Throwable) {}
            }
        }

        private fun loadShader(type: Int, shaderCode: String): Int {
            val shader = GLES20.glCreateShader(type)
            if (shader == 0) return 0
            GLES20.glShaderSource(shader, shaderCode)
            GLES20.glCompileShader(shader)
            val compileStatus = IntArray(1)
            GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, compileStatus, 0)
            if (compileStatus[0] == 0) {
                val log = GLES20.glGetShaderInfoLog(shader)
                Log.e(TAG, "Shader compile failed ($type): $log")
                GLES20.glDeleteShader(shader)
                return 0
            }
            return shader
        }

        private fun createProgram(vsCode: String, fsCode: String): Int {
            val vs = loadShader(GLES20.GL_VERTEX_SHADER, vsCode)
            if (vs == 0) return 0
            val fs = loadShader(GLES20.GL_FRAGMENT_SHADER, fsCode)
            if (fs == 0) {
                GLES20.glDeleteShader(vs)
                return 0
            }
            val program = GLES20.glCreateProgram()
            if (program == 0) return 0
            GLES20.glAttachShader(program, vs)
            GLES20.glAttachShader(program, fs)
            GLES20.glBindAttribLocation(program, 0, "a_pos")
            GLES20.glLinkProgram(program)
            val linkStatus = IntArray(1)
            GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, linkStatus, 0)
            GLES20.glDeleteShader(vs)
            GLES20.glDeleteShader(fs)
            if (linkStatus[0] == 0) {
                val log = GLES20.glGetProgramInfoLog(program)
                Log.e(TAG, "Program link failed: $log")
                GLES20.glDeleteProgram(program)
                return 0
            }
            return program
        }

        companion object {
            private const val TAG = "WeatherGpuInstance"

            private const val VERTEX_SHADER = """
attribute vec2 a_pos;
varying vec2 v_uv;

void main() {
    v_uv = a_pos * 0.5 + 0.5;
    v_uv.y = 1.0 - v_uv.y;
    gl_Position = vec4(a_pos, 0.0, 1.0);
}
"""

            private const val FRAGMENT_SHADER = """
precision highp float;
precision highp int;

varying vec2 v_uv;

uniform float u_time;
uniform int u_weather_type;
uniform float u_is_dark;
uniform float u_intensity;
uniform vec2 u_resolution;

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; ++i) {
        v += a * noise(p);
        p = p * 2.0;
        a *= 0.5;
    }
    return v;
}

void main() {
    vec2 uv = v_uv;
    float time = u_time;
    int weather = u_weather_type;
    float isDark = u_is_dark;
    float intensity = u_intensity;
    vec2 res = u_resolution;

    vec3 topColor;
    vec3 bottomColor;

    if (weather == 0) { // Sunny
        if (isDark > 0.5) {
            topColor = vec3(0.03, 0.05, 0.12);
            bottomColor = vec3(0.08, 0.12, 0.22);
        } else {
            topColor = vec3(0.12, 0.42, 0.88);
            bottomColor = vec3(0.50, 0.74, 0.96);
        }
    } else if (weather == 1) { // Cloudy
        if (isDark > 0.5) {
            topColor = vec3(0.05, 0.07, 0.14);
            bottomColor = vec3(0.16, 0.20, 0.28);
        } else {
            topColor = vec3(0.35, 0.45, 0.58);
            bottomColor = vec3(0.65, 0.72, 0.80);
        }
    } else if (weather == 2) { // Rain
        if (isDark > 0.5) {
            topColor = vec3(0.04, 0.06, 0.10);
            bottomColor = vec3(0.12, 0.15, 0.20);
        } else {
            topColor = vec3(0.18, 0.22, 0.30);
            bottomColor = vec3(0.38, 0.42, 0.48);
        }
    } else if (weather == 3) { // Snow
        if (isDark > 0.5) {
            topColor = vec3(0.06, 0.08, 0.16);
            bottomColor = vec3(0.18, 0.22, 0.32);
        } else {
            topColor = vec3(0.40, 0.50, 0.65);
            bottomColor = vec3(0.75, 0.82, 0.90);
        }
    } else { // Thunder
        topColor = vec3(0.10, 0.12, 0.18);
        bottomColor = vec3(0.22, 0.25, 0.32);
    }

    vec3 col = mix(topColor, bottomColor, uv.y);

    // Sun / Moon disk
    if (weather == 0) {
        vec2 sunPos = vec2(0.75, 0.25);
        float aspect = res.x / max(res.y, 1.0);
        float dist = length((uv - sunPos) * vec2(aspect, 1.0));
        if (isDark < 0.5) {
            float sunDisk = smoothstep(0.08, 0.06, dist);
            float sunGlow = exp(-dist * 6.0) * 0.45;
            col += vec3(1.0, 0.85, 0.4) * (sunDisk + sunGlow);
        } else {
            float moonDisk = smoothstep(0.06, 0.05, dist);
            float moonGlow = exp(-dist * 8.0) * 0.3;
            col += vec3(0.85, 0.9, 1.0) * (moonDisk + moonGlow);
        }
    }

    // Clouds
    if (weather >= 1) {
        vec2 cloudUv = uv * vec2(3.0, 1.5) + vec2(time * 0.04, 0.0);
        float c = fbm(cloudUv);
        float cloudAlpha = smoothstep(0.45, 0.8, c) * intensity * 0.7;
        vec3 cloudColor = (isDark > 0.5) ? vec3(0.2, 0.25, 0.32) : vec3(0.92, 0.94, 0.98);
        col = mix(col, cloudColor, cloudAlpha);
    }

    // Rain streaks
    if (weather == 2 || weather == 4) {
        vec2 rainUv = uv * vec2(150.0, 25.0) + vec2(time * 3.0, time * 20.0);
        float streak = pow(noise(rainUv), 7.0) * intensity * 0.8;
        col += vec3(0.7, 0.85, 1.0) * streak;
    }

    // Snow flakes
    if (weather == 3) {
        vec2 snowUv = uv * vec2(50.0, 40.0) + vec2(sin(time + uv.y * 6.0) * 0.5, time * 4.0);
        float flake = smoothstep(0.88, 0.96, noise(snowUv)) * intensity * 0.9;
        col += vec3(0.95, 0.97, 1.0) * flake;
    }

    // Lightning burst (thunder)
    if (weather == 4) {
        float flash = step(0.96, fract(time * 0.9)) * step(fract(time * 2.1), 0.35) * 0.65;
        col += vec3(0.85, 0.9, 1.0) * flash;
    }

    gl_FragColor = vec4(col, 1.0);
}
"""
        }
    }
}
