#include "weather_gpu_plugin.h"

#include <d3dcompiler.h>
#include <iostream>
#include <chrono>
#include <cmath>

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")
#pragma comment(lib, "d3dcompiler.lib")

namespace {

const char* kChannelName = "com.hyperos.glass/gpu_engine";

struct alignas(16) ConstantBufferData {
  float time;
  float weather_type;
  float is_dark;
  float intensity;

  float width;
  float height;
  float time_of_day;
  float padding;
};

const char* kHlslShaderSource = R"(
cbuffer WeatherConstants : register(b0) {
    float4 u_time_weather_dark_intensity;
    float4 u_resolution_time_pad;
};

struct VSOutput {
    float4 pos : SV_Position;
    float2 uv  : TEXCOORD0;
};

VSOutput VSMain(uint id : SV_VertexID) {
    VSOutput output;
    output.uv = float2((id << 1) & 2, id & 2);
    output.pos = float4(output.uv * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    return output;
}

float hash21(float2 p) {
    p = frac(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return frac(p.x * p.y);
}

float noise(float2 p) {
    float2 i = floor(p);
    float2 f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
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

float4 PSMain(VSOutput input) : SV_Target {
    float2 uv = input.uv;
    float time = u_time_weather_dark_intensity.x;
    int weather = (int)u_time_weather_dark_intensity.y;
    float isDark = u_time_weather_dark_intensity.z;
    float intensity = u_time_weather_dark_intensity.w;
    float2 res = u_resolution_time_pad.xy;

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

    float3 col = lerp(topColor, bottomColor, uv.y);

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
        col = lerp(col, cloudColor, cloudAlpha);
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
        float flash = step(0.96, frac(time * 0.9)) * step(frac(time * 2.1), 0.35) * 0.65;
        col += float3(0.85, 0.9, 1.0) * flash;
    }

    return float4(col, 1.0);
}
)";

}  // namespace

struct WeatherGpuPlugin::WeatherTextureInstance {
  int64_t texture_id = -1;
  size_t width = 800;
  size_t height = 600;

  std::atomic<bool> running{true};
  std::thread render_thread;

  Microsoft::WRL::ComPtr<ID3D11Device> d3d_device;
  Microsoft::WRL::ComPtr<ID3D11DeviceContext> d3d_context;

  Microsoft::WRL::ComPtr<ID3D11Texture2D> render_target_texture;
  Microsoft::WRL::ComPtr<ID3D11RenderTargetView> render_target_view;

  Microsoft::WRL::ComPtr<ID3D11VertexShader> vertex_shader;
  Microsoft::WRL::ComPtr<ID3D11PixelShader> pixel_shader;
  Microsoft::WRL::ComPtr<ID3D11Buffer> constant_buffer;

  std::unique_ptr<flutter::TextureVariant> texture_variant;
  flutter::TextureRegistrar* texture_registrar = nullptr;

  std::atomic<int> weather_type{1};
  std::atomic<float> intensity{1.0f};
  std::atomic<bool> is_dark{false};
  std::atomic<float> time_of_day{0.5f};

  float anim_time = 0.0f;
  std::mutex surface_mutex;
  FlutterDesktopGpuSurfaceDescriptor descriptor{};

  ~WeatherTextureInstance() {
    running = false;
    if (render_thread.joinable()) {
      render_thread.join();
    }
  }

  bool CreateSurface(size_t w, size_t h) {
    std::lock_guard<std::mutex> lock(surface_mutex);
    width = (w == 0) ? 800 : w;
    height = (h == 0) ? 600 : h;

    render_target_view.Reset();
    render_target_texture.Reset();

    D3D11_TEXTURE2D_DESC desc = {};
    desc.Width = static_cast<UINT>(width);
    desc.Height = static_cast<UINT>(height);
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
    desc.MiscFlags = D3D11_RESOURCE_MISC_SHARED;

    HRESULT hr = d3d_device->CreateTexture2D(&desc, nullptr, &render_target_texture);
    if (FAILED(hr)) return false;

    hr = d3d_device->CreateRenderTargetView(render_target_texture.Get(), nullptr, &render_target_view);
    return SUCCEEDED(hr);
  }

  bool InitShaders() {
    Microsoft::WRL::ComPtr<ID3DBlob> vs_blob;
    Microsoft::WRL::ComPtr<ID3DBlob> ps_blob;
    Microsoft::WRL::ComPtr<ID3DBlob> error_blob;

    HRESULT hr = D3DCompile(kHlslShaderSource, strlen(kHlslShaderSource), nullptr, nullptr, nullptr,
                            "VSMain", "vs_4_0", 0, 0, &vs_blob, &error_blob);
    if (FAILED(hr)) return false;

    hr = d3d_device->CreateVertexShader(vs_blob->GetBufferPointer(), vs_blob->GetBufferSize(), nullptr, &vertex_shader);
    if (FAILED(hr)) return false;

    hr = D3DCompile(kHlslShaderSource, strlen(kHlslShaderSource), nullptr, nullptr, nullptr,
                            "PSMain", "ps_4_0", 0, 0, &ps_blob, &error_blob);
    if (FAILED(hr)) return false;

    hr = d3d_device->CreatePixelShader(ps_blob->GetBufferPointer(), ps_blob->GetBufferSize(), nullptr, &pixel_shader);
    if (FAILED(hr)) return false;

    D3D11_BUFFER_DESC cb_desc = {};
    cb_desc.ByteWidth = sizeof(ConstantBufferData);
    cb_desc.Usage = D3D11_USAGE_DYNAMIC;
    cb_desc.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
    cb_desc.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;

    hr = d3d_device->CreateBuffer(&cb_desc, nullptr, &constant_buffer);
    return SUCCEEDED(hr);
  }

  void RenderFrame(float dt) {
    anim_time += dt;

    std::lock_guard<std::mutex> lock(surface_mutex);
    if (!render_target_view || !d3d_context) return;

    D3D11_VIEWPORT viewport = {};
    viewport.TopLeftX = 0;
    viewport.TopLeftY = 0;
    viewport.Width = static_cast<float>(width);
    viewport.Height = static_cast<float>(height);
    viewport.MinDepth = 0.0f;
    viewport.MaxDepth = 1.0f;
    d3d_context->RSSetViewports(1, &viewport);

    ID3D11RenderTargetView* rtv = render_target_view.Get();
    d3d_context->OMSetRenderTargets(1, &rtv, nullptr);

    if (constant_buffer) {
      D3D11_MAPPED_SUBRESOURCE mapped = {};
      HRESULT hr = d3d_context->Map(constant_buffer.Get(), 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped);
      if (SUCCEEDED(hr)) {
        ConstantBufferData* cb = static_cast<ConstantBufferData*>(mapped.pData);
        cb->time = anim_time;
        cb->weather_type = static_cast<float>(weather_type.load());
        cb->is_dark = is_dark.load() ? 1.0f : 0.0f;
        cb->intensity = intensity.load();
        cb->width = static_cast<float>(width);
        cb->height = static_cast<float>(height);
        cb->time_of_day = time_of_day.load();
        cb->padding = 0.0f;
        d3d_context->Unmap(constant_buffer.Get(), 0);
      }
    }

    if (vertex_shader && pixel_shader) {
      d3d_context->IASetInputLayout(nullptr);
      d3d_context->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
      d3d_context->VSSetShader(vertex_shader.Get(), nullptr, 0);
      d3d_context->PSSetShader(pixel_shader.Get(), nullptr, 0);
      ID3D11Buffer* cb = constant_buffer.Get();
      d3d_context->PSSetConstantBuffers(0, 1, &cb);
      d3d_context->Draw(3, 0);
    } else {
      float clear_color[4] = {0.2f, 0.4f, 0.7f, 1.0f};
      d3d_context->ClearRenderTargetView(render_target_view.Get(), clear_color);
    }

    d3d_context->Flush();
  }

  const FlutterDesktopGpuSurfaceDescriptor* ObtainDescriptor(size_t w, size_t h) {
    std::lock_guard<std::mutex> lock(surface_mutex);
    if (!render_target_texture) return nullptr;

    descriptor.struct_size = sizeof(FlutterDesktopGpuSurfaceDescriptor);
    descriptor.handle = render_target_texture.Get();
    descriptor.width = width;
    descriptor.height = height;
    descriptor.visible_width = width;
    descriptor.visible_height = height;
    descriptor.format = kFlutterDesktopPixelFormatRGBA8888;
    descriptor.release_callback = nullptr;
    descriptor.release_context = nullptr;
    return &descriptor;
  }
};

void WeatherGpuPlugin::RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar) {
  if (!registrar) return;
  auto plugin = std::make_unique<WeatherGpuPlugin>(
      registrar->texture_registrar(), registrar->messenger());
  registrar->AddPlugin(std::move(plugin));
}

WeatherGpuPlugin::WeatherGpuPlugin(flutter::TextureRegistrar* texture_registrar,
                                   flutter::BinaryMessenger* messenger)
    : texture_registrar_(texture_registrar), messenger_(messenger) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger_, kChannelName, &flutter::StandardMethodCodec::GetInstance());

  channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });

  InitializeD3D11();
}

WeatherGpuPlugin::~WeatherGpuPlugin() {
  std::lock_guard<std::mutex> lock(instances_mutex_);
  instances_.clear();
}

bool WeatherGpuPlugin::InitializeD3D11() {
  if (d3d_device_ && d3d_context_) return true;

  D3D_FEATURE_LEVEL featureLevels[] = {
      D3D_FEATURE_LEVEL_11_1,
      D3D_FEATURE_LEVEL_11_0,
      D3D_FEATURE_LEVEL_10_1,
      D3D_FEATURE_LEVEL_10_0,
  };
  D3D_FEATURE_LEVEL featureLevel;
  UINT creationFlags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;

  HRESULT hr = D3D11CreateDevice(
      nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, creationFlags,
      featureLevels, ARRAYSIZE(featureLevels), D3D11_SDK_VERSION,
      &d3d_device_, &featureLevel, &d3d_context_);

  if (FAILED(hr)) {
    is_warp_ = true;
    hr = D3D11CreateDevice(
        nullptr, D3D_DRIVER_TYPE_WARP, nullptr, creationFlags,
        featureLevels, ARRAYSIZE(featureLevels), D3D11_SDK_VERSION,
        &d3d_device_, &featureLevel, &d3d_context_);
  }

  return SUCCEEDED(hr);
}

int64_t WeatherGpuPlugin::CreateTextureInstance(int width, int height, const std::string& scene_type) {
  if (!InitializeD3D11() || !texture_registrar_) {
    return -1;
  }

  auto instance = std::make_shared<WeatherTextureInstance>();
  instance->d3d_device = d3d_device_;
  instance->d3d_context = d3d_context_;
  instance->texture_registrar = texture_registrar_;

  int w_type = 1; // cloudy default
  if (scene_type == "sunny") w_type = 0;
  else if (scene_type == "cloudy") w_type = 1;
  else if (scene_type == "rain") w_type = 2;
  else if (scene_type == "snow") w_type = 3;
  else if (scene_type == "thunder") w_type = 4;
  instance->weather_type.store(w_type);

  if (!instance->CreateSurface(width, height)) {
    return -1;
  }
  instance->InitShaders();

  instance->texture_variant = std::make_unique<flutter::TextureVariant>(
      flutter::GpuSurfaceTexture(
          kFlutterDesktopGpuSurfaceTypeD3d11Texture2D,
          [instance_weak = std::weak_ptr<WeatherTextureInstance>(instance)](
              size_t w, size_t h) -> const FlutterDesktopGpuSurfaceDescriptor* {
            if (auto inst = instance_weak.lock()) {
              return inst->ObtainDescriptor(w, h);
            }
            return nullptr;
          }));

  int64_t texture_id = texture_registrar_->RegisterTexture(instance->texture_variant.get());
  if (texture_id < 0) {
    return -1;
  }
  instance->texture_id = texture_id;

  // Initial frame
  instance->RenderFrame(0.016f);
  texture_registrar_->MarkTextureFrameAvailable(texture_id);

  // Background 60 FPS render loop
  instance->render_thread = std::thread([instance]() {
    auto last_time = std::chrono::steady_clock::now();
    while (instance->running) {
      auto now = std::chrono::steady_clock::now();
      float dt = std::chrono::duration<float>(now - last_time).count();
      last_time = now;
      if (dt > 0.1f) dt = 0.016f;

      instance->RenderFrame(dt);

      if (instance->texture_id >= 0 && instance->texture_registrar) {
        instance->texture_registrar->MarkTextureFrameAvailable(instance->texture_id);
      }

      std::this_thread::sleep_for(std::chrono::milliseconds(16));
    }
  });

  std::lock_guard<std::mutex> lock(instances_mutex_);
  instances_[texture_id] = instance;
  return texture_id;
}

void WeatherGpuPlugin::ResizeTextureInstance(int64_t texture_id, int width, int height) {
  std::shared_ptr<WeatherTextureInstance> instance;
  {
    std::lock_guard<std::mutex> lock(instances_mutex_);
    auto it = instances_.find(texture_id);
    if (it != instances_.end()) {
      instance = it->second;
    }
  }
  if (instance) {
    instance->CreateSurface(width, height);
  }
}

void WeatherGpuPlugin::UpdateWeatherInstance(int64_t texture_id, int weather_type, float intensity, bool is_dark, float time_of_day) {
  std::shared_ptr<WeatherTextureInstance> instance;
  {
    std::lock_guard<std::mutex> lock(instances_mutex_);
    auto it = instances_.find(texture_id);
    if (it != instances_.end()) {
      instance = it->second;
    }
  }
  if (instance) {
    instance->weather_type.store(weather_type);
    instance->intensity.store(intensity);
    instance->is_dark.store(is_dark);
    instance->time_of_day.store(time_of_day);
  }
}

void WeatherGpuPlugin::DisposeTextureInstance(int64_t texture_id) {
  std::shared_ptr<WeatherTextureInstance> instance;
  {
    std::lock_guard<std::mutex> lock(instances_mutex_);
    auto it = instances_.find(texture_id);
    if (it != instances_.end()) {
      instance = it->second;
      instances_.erase(it);
    }
  }
  if (instance) {
    instance->running = false;
    if (texture_registrar_) {
      texture_registrar_->UnregisterTexture(texture_id);
    }
  }
}

void WeatherGpuPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const std::string& method = method_call.method_name();

  if (method == "initialize") {
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    int width = 800;
    int height = 600;
    std::string scene_type = "cloudy";

    if (args) {
      auto w_it = args->find(flutter::EncodableValue("width"));
      if (w_it != args->end()) {
        if (std::holds_alternative<int32_t>(w_it->second)) width = std::get<int32_t>(w_it->second);
        else if (std::holds_alternative<int64_t>(w_it->second)) width = static_cast<int>(std::get<int64_t>(w_it->second));
      }
      auto h_it = args->find(flutter::EncodableValue("height"));
      if (h_it != args->end()) {
        if (std::holds_alternative<int32_t>(h_it->second)) height = std::get<int32_t>(h_it->second);
        else if (std::holds_alternative<int64_t>(h_it->second)) height = static_cast<int>(std::get<int64_t>(h_it->second));
      }
      auto s_it = args->find(flutter::EncodableValue("sceneType"));
      if (s_it != args->end() && std::holds_alternative<std::string>(s_it->second)) {
        scene_type = std::get<std::string>(s_it->second);
      }
    }

    int64_t texture_id = CreateTextureInstance(width, height, scene_type);
    if (texture_id >= 0) {
      result->Success(flutter::EncodableValue(texture_id));
    } else {
      result->Error("TEXTURE_CREATION_FAILED", "Failed to create Direct3D 11 texture surface");
    }
  } else if (method == "resize") {
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args) {
      int64_t texture_id = -1;
      int width = 800;
      int height = 600;

      auto id_it = args->find(flutter::EncodableValue("textureId"));
      if (id_it != args->end()) {
        if (std::holds_alternative<int32_t>(id_it->second)) texture_id = std::get<int32_t>(id_it->second);
        else if (std::holds_alternative<int64_t>(id_it->second)) texture_id = std::get<int64_t>(id_it->second);
      }
      auto w_it = args->find(flutter::EncodableValue("width"));
      if (w_it != args->end()) {
        if (std::holds_alternative<int32_t>(w_it->second)) width = std::get<int32_t>(w_it->second);
        else if (std::holds_alternative<int64_t>(w_it->second)) width = static_cast<int>(std::get<int64_t>(w_it->second));
      }
      auto h_it = args->find(flutter::EncodableValue("height"));
      if (h_it != args->end()) {
        if (std::holds_alternative<int32_t>(h_it->second)) height = std::get<int32_t>(h_it->second);
        else if (std::holds_alternative<int64_t>(h_it->second)) height = static_cast<int>(std::get<int64_t>(h_it->second));
      }

      if (texture_id >= 0) {
        ResizeTextureInstance(texture_id, width, height);
        result->Success();
        return;
      }
    }
    result->Error("INVALID_ARGUMENTS", "Missing textureId or dimensions");
  } else if (method == "updateWeather") {
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args) {
      int64_t texture_id = -1;
      int weather_type = 1;
      float intensity = 1.0f;
      bool is_dark = false;
      float time_of_day = 0.5f;

      auto id_it = args->find(flutter::EncodableValue("textureId"));
      if (id_it != args->end()) {
        if (std::holds_alternative<int32_t>(id_it->second)) texture_id = std::get<int32_t>(id_it->second);
        else if (std::holds_alternative<int64_t>(id_it->second)) texture_id = std::get<int64_t>(id_it->second);
      }

      auto type_it = args->find(flutter::EncodableValue("type"));
      if (type_it != args->end()) {
        if (std::holds_alternative<std::string>(type_it->second)) {
          std::string t = std::get<std::string>(type_it->second);
          if (t == "sunny") weather_type = 0;
          else if (t == "cloudy") weather_type = 1;
          else if (t == "rain") weather_type = 2;
          else if (t == "snow") weather_type = 3;
          else if (t == "thunder") weather_type = 4;
        } else if (std::holds_alternative<int32_t>(type_it->second)) {
          weather_type = std::get<int32_t>(type_it->second);
        }
      }

      auto int_it = args->find(flutter::EncodableValue("intensity"));
      if (int_it != args->end()) {
        if (std::holds_alternative<double>(int_it->second)) intensity = static_cast<float>(std::get<double>(int_it->second));
      }

      auto dark_it = args->find(flutter::EncodableValue("isDark"));
      if (dark_it != args->end()) {
        if (std::holds_alternative<bool>(dark_it->second)) is_dark = std::get<bool>(dark_it->second);
      }

      auto tod_it = args->find(flutter::EncodableValue("timeOfDay"));
      if (tod_it != args->end()) {
        if (std::holds_alternative<double>(tod_it->second)) time_of_day = static_cast<float>(std::get<double>(tod_it->second));
      }

      if (texture_id >= 0) {
        UpdateWeatherInstance(texture_id, weather_type, intensity, is_dark, time_of_day);
        result->Success();
        return;
      }
    }
    result->Error("INVALID_ARGUMENTS", "Missing textureId or params");
  } else if (method == "dispose") {
    const auto* args = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args) {
      int64_t texture_id = -1;
      auto id_it = args->find(flutter::EncodableValue("textureId"));
      if (id_it != args->end()) {
        if (std::holds_alternative<int32_t>(id_it->second)) texture_id = std::get<int32_t>(id_it->second);
        else if (std::holds_alternative<int64_t>(id_it->second)) texture_id = std::get<int64_t>(id_it->second);
      }
      if (texture_id >= 0) {
        DisposeTextureInstance(texture_id);
        result->Success();
        return;
      }
    }
    result->Error("INVALID_ARGUMENTS", "Missing textureId");
  } else {
    result->NotImplemented();
  }
}
