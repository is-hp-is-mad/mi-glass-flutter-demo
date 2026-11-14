# hyper_showcase performance

CI runners have no real GPU unless noted: Windows and Linux render in software, the Android emulator uses SwiftShader and the iOS simulator runs a debug build. Read these for regressions, crashes and the relative weight of scenes, not as what a phone would do.

![compare](compare.png)

Did not finish: linux

## linux

linux, skia, 0 Hz, 374x720 @1.0

![linux](curve_linux.png)

| scene | frames | fps | gap p50 | gap p95 | gap max | >33 ms | raster p95 | RSS MB |
|---|---|---|---|---|---|---|---|---|
| idle | 55 | 18 | 17.6 | 22.2 | 84.2 | 1 | 22.1 | 290 |
| settings scroll | 120 | 28 | 18.3 | 65.4 | 829.3 | 9 | 23.9 | 363 |
| controls scroll | 244 | 57 | 16.7 | 19.4 | 38.2 | 1 | 14.6 | 360 |
| materials open | 31 | 34 | 16.8 | 66.7 | 393.9 | 4 | 66.4 | 363 |
| materials scroll | 193 | 45 | 17.5 | 22.7 | 371.4 | 7 | 19.8 | 403 |


From b8d82c793825b89c376c5148d9fb89fb57ba7932, run 43586130947.
