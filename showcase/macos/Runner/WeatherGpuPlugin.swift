import Cocoa
import FlutterMacOS
import Metal
import CoreVideo
import IOSurface

private let kChannelName = "com.hyperos.glass/gpu_engine"

struct WeatherUniforms {
  var time: Float
  var weatherType: Float
  var isDark: Float
  var intensity: Float
  var width: Float
  var height: Float
  var timeOfDay: Float
  var padding: Float
}

private let kMetalShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

struct WeatherUniforms {
    float time;
    float weatherType;
    float isDark;
    float intensity;
    float width;
    float height;
    float timeOfDay;
    float padding;
};

vertex VertexOut weatherVertexShader(uint vertexID [[vertex_id]]) {
    VertexOut out;
    float2 uv = float2((vertexID << 1) & 2, vertexID & 2);
    out.uv = uv;
    out.position = float4(uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    return out;
}

float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(float2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; ++i) {
        v += a * noise(p);
        p = p * 2.0;
        a *= 0.5;
    }
    return v;
}

fragment float4 weatherFragmentShader(VertexOut in [[stage_in]],
                                     constant WeatherUniforms &u [[buffer(0)]]) {
    float2 uv = in.uv;
    float time = u.time;
    int weather = int(u.weatherType);
    float isDark = u.isDark;
    float intensity = u.intensity;
    float2 res = float2(u.width, u.height);

    float3 topColor;
    float3 bottomColor;

    if (weather == 0) { // Sunny
        if (isDark > 0.5) {
            topColor = float3(0.03, 0.05, 0.12);
            bottomColor = float3(0.08, 0.12, 0.22);
        } else {
            topColor = float3(0.12, 0.42, 0.88);
            bottomColor = float3(0.50, 0.74, 0.96);
        }
    } else if (weather == 1) { // Cloudy
        if (isDark > 0.5) {
            topColor = float3(0.05, 0.07, 0.14);
            bottomColor = float3(0.16, 0.20, 0.28);
        } else {
            topColor = float3(0.35, 0.45, 0.58);
            bottomColor = float3(0.65, 0.72, 0.80);
        }
    } else if (weather == 2) { // Rain
        if (isDark > 0.5) {
            topColor = float3(0.04, 0.06, 0.10);
            bottomColor = float3(0.12, 0.15, 0.20);
        } else {
            topColor = float3(0.18, 0.22, 0.30);
            bottomColor = float3(0.38, 0.42, 0.48);
        }
    } else if (weather == 3) { // Snow
        if (isDark > 0.5) {
            topColor = float3(0.06, 0.08, 0.16);
            bottomColor = float3(0.18, 0.22, 0.32);
        } else {
            topColor = float3(0.40, 0.50, 0.65);
            bottomColor = float3(0.75, 0.82, 0.90);
        }
    } else { // Thunder
        topColor = float3(0.10, 0.12, 0.18);
        bottomColor = float3(0.22, 0.25, 0.32);
    }

    float3 col = mix(topColor, bottomColor, uv.y);

    // Sun / Moon disk
    if (weather == 0) {
        float2 sunPos = float2(0.75, 0.25);
        float aspect = res.x / max(res.y, 1.0);
        float dist = length((uv - sunPos) * float2(aspect, 1.0));
        if (isDark < 0.5) {
            float sunDisk = smoothstep(0.08, 0.06, dist);
            float sunGlow = exp(-dist * 6.0) * 0.45;
            col += float3(1.0, 0.85, 0.4) * (sunDisk + sunGlow);
        } else {
            float moonDisk = smoothstep(0.06, 0.05, dist);
            float moonGlow = exp(-dist * 8.0) * 0.3;
            col += float3(0.85, 0.9, 1.0) * (moonDisk + moonGlow);
        }
    }

    // Clouds
    if (weather >= 1) {
        float2 cloudUv = uv * float2(3.0, 1.5) + float2(time * 0.04, 0.0);
        float c = fbm(cloudUv);
        float cloudAlpha = smoothstep(0.45, 0.8, c) * intensity * 0.7;
        float3 cloudColor = (isDark > 0.5) ? float3(0.2, 0.25, 0.32) : float3(0.92, 0.94, 0.98);
        col = mix(col, cloudColor, cloudAlpha);
    }

    // Rain streaks
    if (weather == 2 || weather == 4) {
        float2 rainUv = uv * float2(150.0, 25.0) + float2(time * 3.0, time * 20.0);
        float streak = pow(noise(rainUv), 7.0) * intensity * 0.8;
        col += float3(0.7, 0.85, 1.0) * streak;
    }

    // Snow flakes
    if (weather == 3) {
        float2 snowUv = uv * float2(50.0, 40.0) + float2(sin(time + uv.y * 6.0) * 0.5, time * 4.0);
        float flake = smoothstep(0.88, 0.96, noise(snowUv)) * intensity * 0.9;
        col += float3(0.95, 0.97, 1.0) * flake;
    }

    // Lightning burst (thunder)
    if (weather == 4) {
        float flash = step(0.96, fract(time * 0.9)) * step(fract(time * 2.1), 0.35) * 0.65;
        col += float3(0.85, 0.9, 1.0) * flash;
    }

    return float4(col, 1.0);
}
"""

class WeatherMetalTexture: NSObject, FlutterTexture {
  var textureId: Int64 = -1
  weak var textureRegistry: FlutterTextureRegistry?

  var width: Int
  var height: Int
  var weatherType: Float
  var intensity: Float
  var isDark: Float
  var timeOfDay: Float

  private var pixelBuffer: CVPixelBuffer?
  private var textureCache: CVMetalTextureCache?
  private var metalTexture: MTLTexture?

  private let device: MTLDevice?
  private let commandQueue: MTLCommandQueue?
  private var pipelineState: MTLRenderPipelineState?

  private var timer: DispatchSourceTimer?
  private let lock = NSLock()
  private let startTime = CACurrentMediaTime()

  init?(
    width: Int,
    height: Int,
    weatherType: Float,
    intensity: Float,
    isDark: Float,
    timeOfDay: Float,
    textureRegistry: FlutterTextureRegistry
  ) {
    self.width = max(width, 1)
    self.height = max(height, 1)
    self.weatherType = weatherType
    self.intensity = intensity
    self.isDark = isDark
    self.timeOfDay = timeOfDay
    self.textureRegistry = textureRegistry

    let dev = MTLCreateSystemDefaultDevice()
    self.device = dev
    self.commandQueue = dev?.makeCommandQueue()

    super.init()

    if let dev = dev {
      do {
        let library = try dev.makeLibrary(source: kMetalShaderSource, options: nil)
        let vertexFunction = library.makeFunction(name: "weatherVertexShader")
        let fragmentFunction = library.makeFunction(name: "weatherFragmentShader")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        self.pipelineState = try dev.makeRenderPipelineState(descriptor: pipelineDescriptor)
      } catch {
        NSLog("[WeatherGpuPlugin] Metal shader compilation error: \(error)")
      }
    }

    createBuffers()
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    lock.lock()
    defer { lock.unlock() }
    guard let pb = pixelBuffer else { return nil }
    return Unmanaged.passRetained(pb)
  }

  func resize(width: Int, height: Int) {
    lock.lock()
    defer { lock.unlock() }
    let w = max(width, 1)
    let h = max(height, 1)
    if self.width == w && self.height == h && pixelBuffer != nil {
      return
    }
    self.width = w
    self.height = h
    createBuffers()
  }

  private func createBuffers() {
    pixelBuffer = nil
    metalTexture = nil

    let attrs: [CFString: Any] = [
      kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
      kCVPixelBufferMetalCompatibilityKey: true,
      kCVPixelBufferIOSurfacePropertiesKey: [:] as [String: Any],
      kCVPixelBufferWidthKey: width,
      kCVPixelBufferHeightKey: height
    ]

    var pb: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      attrs as CFDictionary,
      &pb
    )

    guard status == kCVReturnSuccess, let pb = pb else {
      NSLog("[WeatherGpuPlugin] Failed to create CVPixelBuffer: \(status)")
      return
    }
    self.pixelBuffer = pb

    guard let dev = device else { return }

    if textureCache == nil {
      CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, dev, nil, &textureCache)
    }

    if let cache = textureCache {
      var cvMetalTex: CVMetalTexture?
      let cvStatus = CVMetalTextureCacheCreateTextureFromImage(
        kCFAllocatorDefault,
        cache,
        pb,
        nil,
        .bgra8Unorm,
        width,
        height,
        0,
        &cvMetalTex
      )
      if cvStatus == kCVReturnSuccess, let cvMetalTex = cvMetalTex {
        self.metalTexture = CVMetalTextureGetTexture(cvMetalTex)
      }
    }

    if self.metalTexture == nil, let ioSurface = CVPixelBufferGetIOSurface(pb) {
      let desc = MTLTextureDescriptor.texture2DDescriptor(
        pixelFormat: .bgra8Unorm,
        width: width,
        height: height,
        mipmapped: false
      )
      desc.usage = [.renderTarget, .shaderRead]
      self.metalTexture = dev.makeTexture(descriptor: desc, iosurface: ioSurface, plane: 0)
    }
  }

  func startRendering() {
    stopRendering()
    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.hyperos.glass.metal.render"))
    timer.schedule(deadline: .now(), repeating: .milliseconds(16))
    timer.setEventHandler { [weak self] in
      self?.renderFrame()
    }
    self.timer = timer
    timer.resume()
  }

  func stopRendering() {
    if let timer = timer {
      timer.cancel()
      self.timer = nil
    }
  }

  private func renderFrame() {
    lock.lock()
    guard let metalTexture = self.metalTexture,
          let pipelineState = self.pipelineState,
          let commandQueue = self.commandQueue,
          let commandBuffer = commandQueue.makeCommandBuffer() else {
      let currentId = textureId
      let registry = textureRegistry
      lock.unlock()
      if currentId >= 0 {
        registry?.textureFrameAvailable(currentId)
      }
      return
    }

    let renderPassDescriptor = MTLRenderPassDescriptor()
    renderPassDescriptor.colorAttachments[0].texture = metalTexture
    renderPassDescriptor.colorAttachments[0].loadAction = .clear
    renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    renderPassDescriptor.colorAttachments[0].storeAction = .store

    guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
      lock.unlock()
      return
    }

    encoder.setRenderPipelineState(pipelineState)

    let elapsed = Float(CACurrentMediaTime() - startTime)
    var uniforms = WeatherUniforms(
      time: elapsed,
      weatherType: weatherType,
      isDark: isDark,
      intensity: intensity,
      width: Float(width),
      height: Float(height),
      timeOfDay: timeOfDay,
      padding: 0
    )

    encoder.setVertexBytes(&uniforms, length: MemoryLayout<WeatherUniforms>.stride, index: 0)
    encoder.setFragmentBytes(&uniforms, length: MemoryLayout<WeatherUniforms>.stride, index: 0)
    encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    encoder.endEncoding()

    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()

    let currentId = textureId
    let registry = textureRegistry
    lock.unlock()

    if currentId >= 0 {
      registry?.textureFrameAvailable(currentId)
    }
  }

  func dispose() {
    stopRendering()
    lock.lock()
    defer { lock.unlock() }
    if textureId >= 0 {
      textureRegistry?.unregisterTexture(textureId)
      textureId = -1
    }
    pixelBuffer = nil
    metalTexture = nil
    textureCache = nil
  }
}

public class WeatherGpuPlugin: NSObject, FlutterPlugin {
  private let textureRegistry: FlutterTextureRegistry
  private let channel: FlutterMethodChannel
  private var instances = [Int64: WeatherMetalTexture]()
  private let instancesLock = NSLock()

  init(textureRegistry: FlutterTextureRegistry, channel: FlutterMethodChannel) {
    self.textureRegistry = textureRegistry
    self.channel = channel
    super.init()
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let messenger = registrar.messenger
    let textureRegistry = registrar.textures
    let channel = FlutterMethodChannel(name: kChannelName, binaryMessenger: messenger)
    let instance = WeatherGpuPlugin(textureRegistry: textureRegistry, channel: channel)
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public static func register(with viewController: FlutterViewController) {
    let messenger = viewController.engine.binaryMessenger
    let textureRegistry: FlutterTextureRegistry = viewController
    let channel = FlutterMethodChannel(name: kChannelName, binaryMessenger: messenger)
    let instance = WeatherGpuPlugin(textureRegistry: textureRegistry, channel: channel)
    channel.setMethodCallHandler { (call, result) in
      instance.handle(call, result: result)
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initialize":
      let args = call.arguments as? [String: Any]
      let width = args?["width"] as? Int ?? 800
      let height = args?["height"] as? Int ?? 600
      let sceneType = args?["sceneType"] as? String ?? "cloudy"
      let intensity = (args?["intensity"] as? NSNumber)?.floatValue ?? 1.0
      let isDark = args?["isDark"] as? Bool ?? false
      let timeOfDay = (args?["timeOfDay"] as? NSNumber)?.floatValue ?? 0.5

      var weatherType: Float = 1.0
      switch sceneType {
      case "sunny": weatherType = 0.0
      case "cloudy": weatherType = 1.0
      case "rain": weatherType = 2.0
      case "snow": weatherType = 3.0
      case "thunder": weatherType = 4.0
      default: weatherType = 1.0
      }

      guard let textureInstance = WeatherMetalTexture(
        width: width,
        height: height,
        weatherType: weatherType,
        intensity: intensity,
        isDark: isDark ? 1.0 : 0.0,
        timeOfDay: timeOfDay,
        textureRegistry: self.textureRegistry
      ) else {
        result(FlutterError(code: "METAL_INIT_FAILED", message: "Failed to initialize Metal texture", details: nil))
        return
      }

      let id = self.textureRegistry.register(textureInstance)
      textureInstance.textureId = id
      textureInstance.startRendering()

      instancesLock.lock()
      instances[id] = textureInstance
      instancesLock.unlock()

      result(NSNumber(value: id))

    case "resize":
      guard let args = call.arguments as? [String: Any],
            let textureIdNum = args["textureId"] as? NSNumber else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing textureId", details: nil))
        return
      }
      let textureId = textureIdNum.int64Value
      let width = args["width"] as? Int ?? 800
      let height = args["height"] as? Int ?? 600

      instancesLock.lock()
      let instance = instances[textureId]
      instancesLock.unlock()

      if let instance = instance {
        instance.resize(width: width, height: height)
        result(nil)
      } else {
        result(FlutterError(code: "NOT_FOUND", message: "Texture not found", details: nil))
      }

    case "updateWeather":
      guard let args = call.arguments as? [String: Any],
            let textureIdNum = args["textureId"] as? NSNumber else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing textureId", details: nil))
        return
      }
      let textureId = textureIdNum.int64Value

      instancesLock.lock()
      let instance = instances[textureId]
      instancesLock.unlock()

      if let instance = instance {
        if let typeStr = args["type"] as? String {
          switch typeStr {
          case "sunny": instance.weatherType = 0.0
          case "cloudy": instance.weatherType = 1.0
          case "rain": instance.weatherType = 2.0
          case "snow": instance.weatherType = 3.0
          case "thunder": instance.weatherType = 4.0
          default: break
          }
        } else if let typeNum = args["type"] as? NSNumber {
          instance.weatherType = typeNum.floatValue
        }
        if let intensity = args["intensity"] as? NSNumber {
          instance.intensity = intensity.floatValue
        }
        if let isDark = args["isDark"] as? Bool {
          instance.isDark = isDark ? 1.0 : 0.0
        }
        if let timeOfDay = args["timeOfDay"] as? NSNumber {
          instance.timeOfDay = timeOfDay.floatValue
        }
        result(nil)
      } else {
        result(FlutterError(code: "NOT_FOUND", message: "Texture not found", details: nil))
      }

    case "dispose":
      guard let args = call.arguments as? [String: Any],
            let textureIdNum = args["textureId"] as? NSNumber else {
        result(FlutterError(code: "INVALID_ARGS", message: "Missing textureId", details: nil))
        return
      }
      let textureId = textureIdNum.int64Value

      instancesLock.lock()
      let instance = instances.removeValue(forKey: textureId)
      instancesLock.unlock()

      instance?.dispose()
      result(nil)

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
