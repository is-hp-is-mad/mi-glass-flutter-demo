"""Mechanically convert the engine's GLES 3.0 shaders to Flutter FragmentProgram GLSL.

Only the interface layer changes; every statement of the original math is kept:
  * std140 blocks  -> individual float uniforms   (inst.member -> inst_member)
  * int/uint/bool  -> float uniform + int() cast   (literals 1u -> 1, uint -> int)
  * mat2x4/mat3x4  -> mat4 (only indexed by column, as in the source)
  * fp16 types     -> #define to 32-bit types
  * do{...}while(false) -> single-iteration for (SkSL has no do/while)
  * dynamic loop bound  -> constant bound + break (SkSL ES2 loop rules)
  * vertex varyings     -> recomputed from FlutterFragCoord()
  * gl_FragCoord        -> FlutterFragCoord()
Also emits lib/src/shader_layout.g.dart with the float/sampler slot of every uniform.

usage: python -I to_flutter.py ENGINE_SHADER_DIR OUT_SHADER_DIR OUT_DART
"""
import os
import re
import sys

SRC, OUT, DART = sys.argv[1], sys.argv[2], sys.argv[3]

# shader file -> (flutter name, varying recipe)
SHADERS = {
    'mi_glass_sdf.frag.glsl': ('mi_glass_sdf', 'texcoords'),
    'mi_lm_blur.frag.glsl': ('mi_lm_blur', 'texcoords'),
    'mi_lm_downsample.frag.glsl': ('mi_lm_downsample', 'texcoords'),
    'mi_lm_upsample_tint.frag.glsl': ('mi_lm_upsample_tint', 'texcoords'),
    'mi_glass_v13_f16.frag.glsl': ('mi_glass_v13_f16', 'glass'),
}
FLOATS = {'float': 1, 'vec2': 2, 'vec3': 3, 'vec4': 4, 'mat4': 16, 'int': 1, 'uint': 1, 'bool': 1}
HEADER = '''#version 460 core
#include <flutter/runtime_effect.glsl>
// Converted from the HyperOS engine (libhyper_os_flutter.so) by tools/to_flutter.py.
// Interface changes only; the math below is the engine's spirv-cross output.
#define float16_t float
#define f16vec2 vec2
#define f16vec3 vec3
#define f16vec4 vec4
#define f16mat2 mat2
#define f16mat3 mat3
#define f16mat4 mat4
'''


def convert(src, recipe):
    src = src.replace('\r\n', '\n')
    src = re.sub(r'#version 300 es\n', '', src)
    src = re.sub(r'#if defined\(GL_AMD_gpu_shader_half_float\).*?#endif\n', '', src, flags=re.S)
    src = re.sub(r'precision \w+ (float|int);\n', '', src)
    layout = []  # (name, floats) in declaration order
    decls = []
    defines = []

    def add(name, typ, count=0):
        if typ in ('mat2x4', 'mat3x4'):
            typ = 'mat4'
        if typ in ('int', 'uint', 'bool'):
            decls.append(f'uniform float {name}__f;')
            defines.append(f'#define {name} int({name}__f)')
            layout.append((name + '__f', 1))
        elif count:
            decls.append(f'uniform {typ} {name}[{count}];')
            layout.append((name, FLOATS[typ] * count))
        else:
            decls.append(f'uniform {typ} {name};')
            layout.append((name, FLOATS[typ]))

    # Interface-specific inputs first so their slots are stable.
    add('_fl_size', 'vec2')
    if recipe == 'glass':
        add('_fl_rect', 'vec4')
    if NAME in ('mi_glass_sdf', 'mi_glass_v13_f16'):
        add('_fl_sdf_range', 'float')
    if NAME == 'mi_glass_sdf':
        add('_fl_sdf_pass', 'float')
    if NAME == 'mi_lm_upsample_tint':
        add('_fl_out_pass', 'float')

    def block(m):
        body, inst = m.group(1), m.group(2)
        for t, n, cnt in re.findall(r'(?:highp |mediump |lowp )?(\w+) (\w+)(?:\[(\d+)\])?;', body):
            add(f'{inst}_{n}', t, int(cnt) if cnt else 0)
            if NAME == 'mi_lm_upsample_tint':
                UPSAMPLE_UNIFORMS.append((f'{inst}_{n}', t, int(cnt) if cnt else 0))
        return ''

    if NAME == 'mi_glass_v13_f16':
        # fused (Skia) refract path, see FUSED_REFRACT
        add('_fl_fused', 'float')
        add('_fl_kr', 'float')
        add('_fl_k0', 'float')
        add('_fl_k', 'vec4')

    blocks = re.findall(r'layout\(std140\) uniform \w+\s*\{[^}]*\}\s*(\w+);', src)
    src = re.sub(r'layout\(std140\) uniform \w+\s*\{([^}]*)\}\s*(\w+);\n', block, src)
    for inst in blocks:
        src = re.sub(rf'\b{re.escape(inst)}\.(\w+)', rf'{inst}_\1', src)

    samplers = re.findall(r'uniform (?:highp |mediump |lowp )?sampler2D (\w+);', src)
    src = re.sub(r'uniform (?:highp |mediump |lowp )?sampler2D (\w+);', r'uniform sampler2D \1;', src)

    # varyings
    src = re.sub(r'\bin (?:highp |mediump )?vec[23] \w+;\n', '', src)
    if recipe == 'texcoords':
        entry = '    highp vec2 v_texture_coords = FlutterFragCoord().xy / _fl_size;\n'
    else:
        entry = ('    highp vec3 v_screen_pos = vec3(FlutterFragCoord().xy, 1.0);\n'
                 '    highp vec2 v_texcoord = (FlutterFragCoord().xy - _fl_rect.xy) / _fl_rect.zw;\n')
    src = src.replace('void main()\n{\n', 'void main()\n{\n' + entry, 1)
    src = src.replace('gl_FragCoord', 'FlutterFragCoord()')
    src = re.sub(r'layout\(location = 0\) out (?:highp )?vec4 (\w+);', r'out vec4 \1;', src)

    # integer types/literals
    src = re.sub(r'\b(\d+)u\b', r'\1', src)
    src = re.sub(r'\buint\b', 'int', src)

    # do { } while(false)  ->  for (once)
    n = [0]
    def once(_m):
        n[0] += 1
        return f'for (int _once{n[0]} = 0; _once{n[0]} < 1; _once{n[0]}++)\n'
    src = re.sub(r'\bdo\s*\n', once, src)
    # a trailing break makes the continue block unreachable and spirv-cross then emits `while`
    src = re.sub(r'\n\s*break;\n(\s*)\}\s*while\s*\(false\);', r'\n\1}', src)
    src = re.sub(r'\}\s*while\s*\(false\);', '}', src)

    # dynamic loop bound: for (int i = 0; i < X; ) { ... i++; continue; }
    def dyn(m):
        var, bound, body_indent = m.group(1), m.group(2), m.group(3)
        return f'for (int {var} = 0; {var} < 7; {var}++)\n{body_indent}{{\n{body_indent}    if ({var} >= {bound}) break;\n'
    src, k = re.subn(r'for \(int (\w+) = 0; \1 < ([\w.]+); \)\n(\s*)\{\n', dyn, src)
    if k:
        src = re.sub(r'\n\s*_\d+\+\+;\n(\s*continue;)', r'\n\1', src)

    if NAME == 'mi_glass_v13_f16':
        for u in UPSAMPLE_UNIFORMS:  # the original tint function's inputs
            add(*u)
    src = sdf_codec(src, samplers)
    out = HEADER + '\n'.join(defines) + '\n' + '\n'.join(decls) + '\n' + src
    return out, layout, samplers


# The engine renders the SDF into RGBA16F (signed gradient + distances). Flutter offscreen images are
# 8-bit premultiplied, so the SDF pass is run twice with opaque output: pass 0 = (grad.xy, w_hi),
# pass 1 = (z_hi, z_lo, w_lo), distances mapped from [-range, range]. The glass shader decodes it.
SDF_ENC = '''    {
        highp vec2 _fl_t = clamp(_fl_s.zw / (2.0 * _fl_sdf_range) + 0.5, 0.0, 1.0);
        highp vec2 _fl_hi = floor(_fl_t * 255.0) / 255.0;
        highp vec2 _fl_lo = fract(_fl_t * 255.0);
        outColor = _fl_sdf_pass < 0.5 ? vec4(clamp(_fl_s.xy * 0.5 + 0.5, 0.0, 1.0), _fl_hi.y, 1.0)
                                      : vec4(_fl_hi.x, _fl_lo.x, _fl_lo.y, 1.0);
    }
'''
SDF_DEC = '''uniform sampler2D _fl_sdfB;
highp vec4 _fl_sdf(highp vec2 uv)
{
    highp vec4 a = texture(uSdfTex, uv);
    highp vec4 b = texture(_fl_sdfB, uv);
    highp vec2 t = vec2(b.x + b.y / 255.0, a.z + b.z / 255.0);
    return vec4(a.xy * 2.0 - 1.0, (t - 0.5) * (2.0 * _fl_sdf_range));
}

'''


UPSAMPLE_UNIFORMS = []
TINT_FUNC = ''

# The tinted refract texture keeps data (not coverage) in alpha, which Skia would clamp as premultiplied
# colour (rgb <= a), so the multi-pass path splits it into an opaque RGB image and an opaque alpha image.
#
# Skia path (no intermediate textures): AcquireGlassBlurTextures' reflect blur, tint blur and
# MiLmUpsampleSimple are folded into one separable kernel over the backdrop (_fl_k0, _fl_k = taps 0..4,
# computed in Dart by running the LM blur taps on an impulse), followed by the upsample shader's own
# main() body, wrapped unchanged as _fl_tint(). Valid when both blurs run at factor 1 (the app's case).
FUSED_REFRACT = '''uniform sampler2D _fl_refractA;
uniform sampler2D _fl_backdrop;
highp float _fl_kw(int a)
{
    if (a == 0) return _fl_k0;
    if (a == 1) return _fl_k.x;
    if (a == 2) return _fl_k.y;
    if (a == 3) return _fl_k.z;
    return _fl_k.w;
}
@TINT@
highp vec4 _fl_refract(highp vec2 uv)
{
    if (_fl_fused < 0.5) return vec4(texture(uRefractTex, uv).rgb, texture(_fl_refractA, uv).r);
    highp vec3 acc = vec3(0.0);
    for (int j = -4; j <= 4; j++)
    {
        if (abs(float(j)) > _fl_kr) continue;
        highp float wj = _fl_kw(j < 0 ? -j : j);
        for (int i = -4; i <= 4; i++)
        {
            if (abs(float(i)) > _fl_kr) continue;
            acc += (wj * _fl_kw(i < 0 ? -i : i)) * texture(_fl_backdrop, uv + vec2(float(i), float(j)) * _198_uInvResolution).rgb;
        }
    }
    return _fl_tint(vec4(acc, 1.0), vec4(texture(_fl_backdrop, uv).rgb, 1.0), uv / _198_uInvResolution);
}

'''


def make_tint_func(src):
    head = 'void main()\n{\n'
    body = src[src.index(head) + len(head):src.rindex('}')]
    body = body.replace('    highp vec2 v_texture_coords = FlutterFragCoord().xy / _fl_size;\n', '', 1)
    for a, b in [('texture(texture_sampler, v_texture_coords)', '_fl_c'),
                 ('texture(big_blur_sampler, v_texture_coords)', '_fl_big'),
                 ('v_texture_coords * upsample_info_output_size', '_fl_px')]:
        assert a in body, a
        body = body.replace(a, b)
    assert 'v_texture_coords' not in body
    body, k = re.subn(r'frag_color = (_\d+);', r'return \1;', body)
    assert k == 1
    return 'highp vec4 _fl_tint(vec4 _fl_c, vec4 _fl_big, highp vec2 _fl_px)\n{\n' + body + '}\n'


def sdf_codec(src, samplers):
    global TINT_FUNC
    if NAME == 'mi_lm_upsample_tint':
        TINT_FUNC = make_tint_func(src)
        src, k = re.subn(r'    frag_color = (_\d+);\n',
                         r'    frag_color = _fl_out_pass < 0.5 ? vec4(\1.rgb, 1.0) : vec4(vec3(\1.a), 1.0);\n', src)
        assert k == 1
    if NAME == 'mi_glass_v13_f16':
        src, k = re.subn(r'texture\(uRefractTex, ', '_fl_refract(', src)
        assert k == 3
        src = src.replace('void main()\n', FUSED_REFRACT.replace('@TINT@', TINT_FUNC) + 'void main()\n', 1)
        samplers += ['_fl_refractA', '_fl_backdrop']
    if NAME == 'mi_glass_sdf':
        src, k = re.subn(r'    outColor = (vec4\(f16vec4\(_\d+\.xy, .*\));\n',
                         lambda m: f'    highp vec4 _fl_s = {m.group(1)};\n' + SDF_ENC, src)
        assert k == 1
    elif NAME == 'mi_glass_v13_f16':
        src, k = re.subn(r'texture\(uSdfTex, ', '_fl_sdf(', src)
        assert k == 1
        src = src.replace('void main()\n', SDF_DEC + 'void main()\n', 1)
        samplers.append('_fl_sdfB')
    return src


def main():
    os.makedirs(OUT, exist_ok=True)
    dart = ['// GENERATED by tools/to_flutter.py — float slot of every uniform in each converted shader.',
            '// ignore_for_file: constant_identifier_names', '']
    for fn, (name, recipe) in SHADERS.items():
        src = open(os.path.join(SRC, fn), encoding='utf-8').read()
        global NAME
        NAME = name
        out, layout, samplers = convert(src, recipe)
        open(os.path.join(OUT, name + '.frag'), 'w', encoding='utf-8', newline='\n').write(out)
        cls = ''.join(p.capitalize() for p in name.split('_'))
        dart.append(f'abstract final class {cls}Layout {{')
        dart.append(f"  static const asset = 'shaders/{name}.frag';")
        off = 0
        for n, c in layout:
            ident = re.sub(r'^_?\d+_', '', n).lstrip('_')
            dart.append(f'  static const {ident} = {off}; // {c} float(s)')
            off += c
        dart.append(f'  static const floatCount = {off};')
        for i, s in enumerate(samplers):
            dart.append(f'  static const sampler_{s.lstrip("_")} = {i};')
        dart.append('}\n')
        print(f'{name}: {off} floats, samplers {samplers}')
    open(DART, 'w', encoding='utf-8', newline='\n').write('\n'.join(dart))


main()
