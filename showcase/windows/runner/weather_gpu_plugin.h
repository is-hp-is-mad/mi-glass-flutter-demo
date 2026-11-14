#ifndef WEATHER_GPU_PLUGIN_H_
#define WEATHER_GPU_PLUGIN_H_

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter/texture_registrar.h>

#include <d3d11.h>
#include <dxgi.h>
#include <wrl/client.h>

#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>

class WeatherGpuPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  WeatherGpuPlugin(flutter::TextureRegistrar* texture_registrar,
                   flutter::BinaryMessenger* messenger);
  virtual ~WeatherGpuPlugin();

  // Disallow copy and assign.
  WeatherGpuPlugin(const WeatherGpuPlugin&) = delete;
  WeatherGpuPlugin& operator=(const WeatherGpuPlugin&) = delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  struct WeatherTextureInstance;

  int64_t CreateTextureInstance(int width, int height, const std::string& scene_type);
  void ResizeTextureInstance(int64_t texture_id, int width, int height);
  void UpdateWeatherInstance(int64_t texture_id, int weather_type, float intensity, bool is_dark, float time_of_day);
  void DisposeTextureInstance(int64_t texture_id);

  flutter::TextureRegistrar* texture_registrar_;
  flutter::BinaryMessenger* messenger_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;

  Microsoft::WRL::ComPtr<ID3D11Device> d3d_device_;
  Microsoft::WRL::ComPtr<ID3D11DeviceContext> d3d_context_;
  bool is_warp_ = false;

  bool InitializeD3D11();

  std::mutex instances_mutex_;
  std::unordered_map<int64_t, std::shared_ptr<WeatherTextureInstance>> instances_;
};

#endif  // WEATHER_GPU_PLUGIN_H_
