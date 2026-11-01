# HyperGlass Showcase

A catalogue of HyperOS 4 controls and materials in Flutter, built from what ROM OS4.0.4.0 actually does: settings rows,
tab bars, buttons, popups, and all 35 of miuix's named glass tokens over pictures.

- **设置**: every kind of preference miuix has.
- **控件**: tabs, buttons, switches, sliders, fields, spinner, dialog, bottom sheet, toast.
- **材质**: a media card and dialer keys, the `GlassToken` and `ColorBlend` materials, plus a lab with every parameter
  on a slider.

MiSans is not committed: run `python tool/fetch_misans.py` before building. No Xiaomi image assets are included; the
wallpapers and photos are drawn in code.

The design itself lives in `packages/hyper_glass`, and this app uses it like any other host. See [PORTING.md](PORTING.md).

## Where the values come from

| Source | What |
|---|---|
| `miuix.jar` | `GlassToken`, `BloomStrokeToken`, `ShadowToken`, `ColorBlendToken`, dimens, spring constants |
| App-bundled miuix | `BottomNavigator`: bar, pill and its two-spring motion |
| `libhwui.so` SkSL | Bloom stroke, press light, view shadow (`shaders/mi_view_shadow.frag`) |
| `libhyper_os_flutter.so` | Glass shaders and the LM blur, `sigma = radius * 0.1125` |

Not verified against a device, and some choices, such as the page transition, are inferred. Mobile runs on
Impeller, which is only exercised by CI here.

## Performance

`.github/workflows/showcase.yml` runs the timed scenarios of `lib/ci/shots.dart` on each platform and publishes curves to
the [`perf-results`](https://github.com/is-hp-is-mad/mi-glass-flutter-demo/tree/perf-results) branch. To run it locally, set
`SHOWCASE_PERF=out.csv` and start a release build; `tool/plot_perf.py` draws the result.
