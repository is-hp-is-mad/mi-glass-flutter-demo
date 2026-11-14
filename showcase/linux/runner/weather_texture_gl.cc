#include "weather_texture_gl.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>

struct _FlWeatherTextureGL {
  FlTextureGL parent_instance;

  GLuint fbo;
  GLuint texture_id;
  GLuint program;
  GLuint vbo;

  uint32_t width;
  uint32_t height;

  int weather_type; // 0=sunny, 1=cloudy, 2=rain, 3=snow, 4=thunder
  float intensity;
  gboolean is_dark;
  float time_of_day;
  float anim_time;

  gint64 last_frame_time_us;
  gboolean needs_reallocate;
};

G_DEFINE_TYPE(FlWeatherTextureGL, fl_weather_texture_gl, fl_texture_gl_get_type())

namespace {

const char* kVertexShaderSource = R"(#version 120
attribute vec2 a_pos;
varying vec2 v_uv;
void main() {
    v_uv = a_pos * 0.5 + 0.5;
    v_uv.y = 1.0 - v_uv.y; // Flip Y for OpenGL texture coordinates
    gl_Position = vec4(a_pos, 0.0, 1.0);
}
)";

const char* kFragmentShaderSource = R"(#version 120
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
)";

GLuint CompileShader(GLenum type, const char* source) {
  GLuint shader = glCreateShader(type);
  glShaderSource(shader, 1, &source, NULL);
  glCompileShader(shader);
  GLint status = 0;
  glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
  if (!status) {
    glDeleteShader(shader);
    return 0;
  }
  return shader;
}

GLuint CreateProgram(const char* vs_source, const char* fs_source) {
  GLuint vs = CompileShader(GL_VERTEX_SHADER, vs_source);
  if (!vs) return 0;
  GLuint fs = CompileShader(GL_FRAGMENT_SHADER, fs_source);
  if (!fs) {
    glDeleteShader(vs);
    return 0;
  }
  GLuint prog = glCreateProgram();
  glAttachShader(prog, vs);
  glAttachShader(prog, fs);
  glBindAttribLocation(prog, 0, "a_pos");
  glLinkProgram(prog);
  glDeleteShader(vs);
  glDeleteShader(fs);

  GLint status = 0;
  glGetProgramiv(prog, GL_LINK_STATUS, &status);
  if (!status) {
    glDeleteProgram(prog);
    return 0;
  }
  return prog;
}

}  // namespace

static void ensure_gl_resources(FlWeatherTextureGL* self) {
  if (self->texture_id == 0 || self->needs_reallocate) {
    if (self->texture_id != 0) {
      glDeleteTextures(1, &self->texture_id);
      self->texture_id = 0;
    }
    if (self->fbo != 0) {
      glDeleteFramebuffers(1, &self->fbo);
      self->fbo = 0;
    }

    glGenTextures(1, &self->texture_id);
    glBindTexture(GL_TEXTURE_2D, self->texture_id);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, self->width, self->height, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    glGenFramebuffers(1, &self->fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, self->fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, self->texture_id, 0);

    self->needs_reallocate = FALSE;
  }

  if (self->program == 0) {
    self->program = CreateProgram(kVertexShaderSource, kFragmentShaderSource);
  }

  if (self->vbo == 0) {
    static const float kQuadVertices[] = {
        -1.0f, -1.0f,
         1.0f, -1.0f,
        -1.0f,  1.0f,
        -1.0f,  1.0f,
         1.0f, -1.0f,
         1.0f,  1.0f,
    };
    glGenBuffers(1, &self->vbo);
    glBindBuffer(GL_ARRAY_BUFFER, self->vbo);
    glBufferData(GL_ARRAY_BUFFER, sizeof(kQuadVertices), kQuadVertices, GL_STATIC_DRAW);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
  }
}

static gboolean fl_weather_texture_gl_populate(FlTextureGL* texture,
                                               uint32_t* target,
                                               uint32_t* name,
                                               uint32_t* width,
                                               uint32_t* height,
                                               GError** error) {
  FlWeatherTextureGL* self = FL_WEATHER_TEXTURE_GL(texture);

  gint64 now_us = g_get_monotonic_time();
  if (self->last_frame_time_us > 0) {
    float dt = static_cast<float>(now_us - self->last_frame_time_us) / 1000000.0f;
    if (dt > 0.1f) dt = 0.016f;
    self->anim_time += dt;
  }
  self->last_frame_time_us = now_us;

  ensure_gl_resources(self);

  GLint prev_fbo = 0;
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &prev_fbo);
  GLint prev_vp[4];
  glGetIntegerv(GL_VIEWPORT, prev_vp);

  glBindFramebuffer(GL_FRAMEBUFFER, self->fbo);
  glViewport(0, 0, self->width, self->height);

  if (self->program != 0 && self->vbo != 0) {
    glUseProgram(self->program);

    glUniform1f(glGetUniformLocation(self->program, "u_time"), self->anim_time);
    glUniform1i(glGetUniformLocation(self->program, "u_weather_type"), self->weather_type);
    glUniform1f(glGetUniformLocation(self->program, "u_is_dark"), self->is_dark ? 1.0f : 0.0f);
    glUniform1f(glGetUniformLocation(self->program, "u_intensity"), self->intensity);
    glUniform2f(glGetUniformLocation(self->program, "u_resolution"), static_cast<float>(self->width), static_cast<float>(self->height));

    glBindBuffer(GL_ARRAY_BUFFER, self->vbo);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(float), NULL);

    glDrawArrays(GL_TRIANGLES, 0, 6);

    glDisableVertexAttribArray(0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glUseProgram(0);
  } else {
    glClearColor(0.2f, 0.45f, 0.75f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
  }

  glBindFramebuffer(GL_FRAMEBUFFER, prev_fbo);
  glViewport(prev_vp[0], prev_vp[1], prev_vp[2], prev_vp[3]);

  *target = GL_TEXTURE_2D;
  *name = self->texture_id;
  *width = self->width;
  *height = self->height;
  return TRUE;
}

static void fl_weather_texture_gl_dispose(GObject* object) {
  FlWeatherTextureGL* self = FL_WEATHER_TEXTURE_GL(object);

  if (self->texture_id != 0) {
    glDeleteTextures(1, &self->texture_id);
    self->texture_id = 0;
  }
  if (self->fbo != 0) {
    glDeleteFramebuffers(1, &self->fbo);
    self->fbo = 0;
  }
  if (self->vbo != 0) {
    glDeleteBuffers(1, &self->vbo);
    self->vbo = 0;
  }
  if (self->program != 0) {
    glDeleteProgram(self->program);
    self->program = 0;
  }

  G_OBJECT_CLASS(fl_weather_texture_gl_parent_class)->dispose(object);
}

static void fl_weather_texture_gl_class_init(FlWeatherTextureGLClass* klass) {
  FL_TEXTURE_GL_CLASS(klass)->populate = fl_weather_texture_gl_populate;
  G_OBJECT_CLASS(klass)->dispose = fl_weather_texture_gl_dispose;
}

static void fl_weather_texture_gl_init(FlWeatherTextureGL* self) {
  self->fbo = 0;
  self->texture_id = 0;
  self->program = 0;
  self->vbo = 0;
  self->width = 800;
  self->height = 600;
  self->weather_type = 1; // cloudy
  self->intensity = 1.0f;
  self->is_dark = FALSE;
  self->time_of_day = 0.5f;
  self->anim_time = 0.0f;
  self->last_frame_time_us = 0;
  self->needs_reallocate = TRUE;
}

FlWeatherTextureGL* fl_weather_texture_gl_new(uint32_t width, uint32_t height) {
  FlWeatherTextureGL* self = FL_WEATHER_TEXTURE_GL(g_object_new(fl_weather_texture_gl_get_type(), NULL));
  self->width = (width == 0) ? 800 : width;
  self->height = (height == 0) ? 600 : height;
  self->needs_reallocate = TRUE;
  return self;
}

void fl_weather_texture_gl_set_weather(FlWeatherTextureGL* self, int weather_type, float intensity, gboolean is_dark, float time_of_day) {
  g_return_if_fail(FL_IS_WEATHER_TEXTURE_GL(self));
  self->weather_type = weather_type;
  self->intensity = intensity;
  self->is_dark = is_dark;
  self->time_of_day = time_of_day;
}

void fl_weather_texture_gl_resize(FlWeatherTextureGL* self, uint32_t width, uint32_t height) {
  g_return_if_fail(FL_IS_WEATHER_TEXTURE_GL(self));
  if (self->width != width || self->height != height) {
    self->width = (width == 0) ? 800 : width;
    self->height = (height == 0) ? 600 : height;
    self->needs_reallocate = TRUE;
  }
}

uint32_t fl_weather_texture_gl_get_width(FlWeatherTextureGL* self) {
  g_return_val_if_fail(FL_IS_WEATHER_TEXTURE_GL(self), 0);
  return self->width;
}

uint32_t fl_weather_texture_gl_get_height(FlWeatherTextureGL* self) {
  g_return_val_if_fail(FL_IS_WEATHER_TEXTURE_GL(self), 0);
  return self->height;
}
