#ifndef WEATHER_TEXTURE_GL_H_
#define WEATHER_TEXTURE_GL_H_

#include <flutter_linux/flutter_linux.h>
#include <epoxy/gl.h>

G_BEGIN_DECLS

#define FL_TYPE_WEATHER_TEXTURE_GL (fl_weather_texture_gl_get_type())
G_DECLARE_FINAL_TYPE(FlWeatherTextureGL, fl_weather_texture_gl, FL, WEATHER_TEXTURE_GL, FlTextureGL)

FlWeatherTextureGL* fl_weather_texture_gl_new(uint32_t width, uint32_t height);
void fl_weather_texture_gl_set_weather(FlWeatherTextureGL* self, int weather_type, float intensity, gboolean is_dark, float time_of_day);
void fl_weather_texture_gl_resize(FlWeatherTextureGL* self, uint32_t width, uint32_t height);
uint32_t fl_weather_texture_gl_get_width(FlWeatherTextureGL* self);
uint32_t fl_weather_texture_gl_get_height(FlWeatherTextureGL* self);

G_END_DECLS

#endif  // WEATHER_TEXTURE_GL_H_
