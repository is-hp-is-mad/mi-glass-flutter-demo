#include "weather_gpu_plugin.h"
#include "weather_texture_gl.h"

#include <cstring>
#include <memory>
#include <unordered_map>

namespace {

const char* kChannelName = "com.hyperos.glass/gpu_engine";

struct TextureContext {
  FlWeatherTextureGL* texture = nullptr;
  FlTextureRegistrar* registrar = nullptr;
  guint timer_id = 0;
  int64_t texture_id = -1;

  ~TextureContext() {
    if (timer_id > 0) {
      g_source_remove(timer_id);
      timer_id = 0;
    }
    if (texture && registrar) {
      fl_texture_registrar_unregister_texture(registrar, FL_TEXTURE(texture));
      g_object_unref(texture);
      texture = nullptr;
    }
  }
};

static gboolean on_frame_tick(gpointer user_data) {
  auto* ctx = static_cast<TextureContext*>(user_data);
  if (ctx && ctx->registrar && ctx->texture) {
    fl_texture_registrar_mark_texture_frame_available(ctx->registrar, FL_TEXTURE(ctx->texture));
    return G_SOURCE_CONTINUE;
  }
  return G_SOURCE_REMOVE;
}

class LinuxWeatherGpuPlugin {
 public:
  LinuxWeatherGpuPlugin(FlTextureRegistrar* registrar, FlBinaryMessenger* messenger)
      : registrar_(registrar), messenger_(messenger) {
    g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
    channel_ = fl_method_channel_new(messenger_, kChannelName, FL_METHOD_CODEC(codec));

    fl_method_channel_set_method_call_handler(
        channel_,
        [](FlMethodChannel* channel, FlMethodCall* method_call, gpointer user_data) {
          auto* self = static_cast<LinuxWeatherGpuPlugin*>(user_data);
          self->HandleMethodCall(method_call);
        },
        this, nullptr);
  }

  ~LinuxWeatherGpuPlugin() {
    textures_.clear();
    if (channel_) {
      g_object_unref(channel_);
      channel_ = nullptr;
    }
  }

 private:
  void HandleMethodCall(FlMethodCall* method_call) {
    const gchar* method = fl_method_call_get_name(method_call);
    FlValue* args = fl_method_call_get_args(method_call);

    if (strcmp(method, "initialize") == 0) {
      int width = 800;
      int height = 600;
      const char* scene_type = "cloudy";

      if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
        FlValue* w_val = fl_value_lookup_string(args, "width");
        if (w_val && fl_value_get_type(w_val) == FL_VALUE_TYPE_INT) {
          width = fl_value_get_int(w_val);
        }
        FlValue* h_val = fl_value_lookup_string(args, "height");
        if (h_val && fl_value_get_type(h_val) == FL_VALUE_TYPE_INT) {
          height = fl_value_get_int(h_val);
        }
        FlValue* s_val = fl_value_lookup_string(args, "sceneType");
        if (s_val && fl_value_get_type(s_val) == FL_VALUE_TYPE_STRING) {
          scene_type = fl_value_get_string(s_val);
        }
      }

      int w_type = 1; // cloudy
      if (strcmp(scene_type, "sunny") == 0) w_type = 0;
      else if (strcmp(scene_type, "cloudy") == 0) w_type = 1;
      else if (strcmp(scene_type, "rain") == 0) w_type = 2;
      else if (strcmp(scene_type, "snow") == 0) w_type = 3;
      else if (strcmp(scene_type, "thunder") == 0) w_type = 4;

      FlWeatherTextureGL* weather_texture = fl_weather_texture_gl_new(width, height);
      fl_weather_texture_gl_set_weather(weather_texture, w_type, 1.0f, FALSE, 0.5f);

      gboolean reg_success = fl_texture_registrar_register_texture(registrar_, FL_TEXTURE(weather_texture));
      if (!reg_success) {
        g_object_unref(weather_texture);
        g_autoptr(FlValue) err = fl_value_new_string("Failed to register FlTextureGL");
        fl_method_call_respond_error(method_call, "TEXTURE_REGISTER_FAILED", "Could not register texture with registrar", err, nullptr);
        return;
      }

      int64_t texture_id = fl_texture_get_id(FL_TEXTURE(weather_texture));

      auto ctx = std::make_unique<TextureContext>();
      ctx->texture = weather_texture;
      ctx->registrar = registrar_;
      ctx->texture_id = texture_id;

      // Start 60 FPS tick timer
      ctx->timer_id = g_timeout_add(16, on_frame_tick, ctx.get());

      textures_[texture_id] = std::move(ctx);

      g_autoptr(FlValue) res = fl_value_new_int(texture_id);
      fl_method_call_respond_success(method_call, res, nullptr);
    } else if (strcmp(method, "resize") == 0) {
      if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
        int64_t texture_id = -1;
        int width = 800;
        int height = 600;

        FlValue* id_val = fl_value_lookup_string(args, "textureId");
        if (id_val && fl_value_get_type(id_val) == FL_VALUE_TYPE_INT) {
          texture_id = fl_value_get_int(id_val);
        }
        FlValue* w_val = fl_value_lookup_string(args, "width");
        if (w_val && fl_value_get_type(w_val) == FL_VALUE_TYPE_INT) {
          width = fl_value_get_int(w_val);
        }
        FlValue* h_val = fl_value_lookup_string(args, "height");
        if (h_val && fl_value_get_type(h_val) == FL_VALUE_TYPE_INT) {
          height = fl_value_get_int(h_val);
        }

        auto it = textures_.find(texture_id);
        if (it != textures_.end() && it->second->texture) {
          fl_weather_texture_gl_resize(it->second->texture, width, height);
          fl_method_call_respond_success(method_call, nullptr, nullptr);
          return;
        }
      }
      fl_method_call_respond_error(method_call, "INVALID_ARGUMENTS", "Texture not found or invalid args", nullptr, nullptr);
    } else if (strcmp(method, "updateWeather") == 0) {
      if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
        int64_t texture_id = -1;
        int weather_type = 1;
        float intensity = 1.0f;
        gboolean is_dark = FALSE;
        float time_of_day = 0.5f;

        FlValue* id_val = fl_value_lookup_string(args, "textureId");
        if (id_val && fl_value_get_type(id_val) == FL_VALUE_TYPE_INT) {
          texture_id = fl_value_get_int(id_val);
        }

        FlValue* type_val = fl_value_lookup_string(args, "type");
        if (type_val) {
          if (fl_value_get_type(type_val) == FL_VALUE_TYPE_STRING) {
            const char* t = fl_value_get_string(type_val);
            if (strcmp(t, "sunny") == 0) weather_type = 0;
            else if (strcmp(t, "cloudy") == 0) weather_type = 1;
            else if (strcmp(t, "rain") == 0) weather_type = 2;
            else if (strcmp(t, "snow") == 0) weather_type = 3;
            else if (strcmp(t, "thunder") == 0) weather_type = 4;
          } else if (fl_value_get_type(type_val) == FL_VALUE_TYPE_INT) {
            weather_type = fl_value_get_int(type_val);
          }
        }

        FlValue* int_val = fl_value_lookup_string(args, "intensity");
        if (int_val && fl_value_get_type(int_val) == FL_VALUE_TYPE_FLOAT) {
          intensity = static_cast<float>(fl_value_get_float(int_val));
        }

        FlValue* dark_val = fl_value_lookup_string(args, "isDark");
        if (dark_val && fl_value_get_type(dark_val) == FL_VALUE_TYPE_BOOL) {
          is_dark = fl_value_get_bool(dark_val);
        }

        FlValue* tod_val = fl_value_lookup_string(args, "timeOfDay");
        if (tod_val && fl_value_get_type(tod_val) == FL_VALUE_TYPE_FLOAT) {
          time_of_day = static_cast<float>(fl_value_get_float(tod_val));
        }

        auto it = textures_.find(texture_id);
        if (it != textures_.end() && it->second->texture) {
          fl_weather_texture_gl_set_weather(it->second->texture, weather_type, intensity, is_dark, time_of_day);
          fl_method_call_respond_success(method_call, nullptr, nullptr);
          return;
        }
      }
      fl_method_call_respond_error(method_call, "INVALID_ARGUMENTS", "Texture not found or invalid args", nullptr, nullptr);
    } else if (strcmp(method, "dispose") == 0) {
      if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
        int64_t texture_id = -1;
        FlValue* id_val = fl_value_lookup_string(args, "textureId");
        if (id_val && fl_value_get_type(id_val) == FL_VALUE_TYPE_INT) {
          texture_id = fl_value_get_int(id_val);
        }

        auto it = textures_.find(texture_id);
        if (it != textures_.end()) {
          textures_.erase(it);
          fl_method_call_respond_success(method_call, nullptr, nullptr);
          return;
        }
      }
      fl_method_call_respond_error(method_call, "INVALID_ARGUMENTS", "Texture not found", nullptr, nullptr);
    } else {
      fl_method_call_respond_not_implemented(method_call, nullptr);
    }
  }

  FlTextureRegistrar* registrar_ = nullptr;
  FlBinaryMessenger* messenger_ = nullptr;
  FlMethodChannel* channel_ = nullptr;
  std::unordered_map<int64_t, std::unique_ptr<TextureContext>> textures_;
};

static std::unique_ptr<LinuxWeatherGpuPlugin> g_linux_plugin;

}  // namespace

void weather_gpu_plugin_register_with_view(FlView* view) {
  if (!view) return;
  FlEngine* engine = fl_view_get_engine(view);
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(engine);
  FlTextureRegistrar* texture_registrar = fl_engine_get_texture_registrar(engine);

  g_linux_plugin = std::make_unique<LinuxWeatherGpuPlugin>(texture_registrar, messenger);
}
