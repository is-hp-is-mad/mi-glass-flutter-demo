import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Controller for cross-platform zero-copy GPU native weather rendering.
/// Communicates with native Direct3D 11 (Windows), OpenGL/EGL (Linux),
/// Metal (macOS), and SurfaceTexture (Android) via MethodChannel.
class HyperGpuEngine extends ChangeNotifier {
  HyperGpuEngine({
    this.channelName = 'com.hyperos.glass/gpu_engine',
  }) : _channel = MethodChannel(channelName);

  final String channelName;
  final MethodChannel _channel;

  int? _textureId;
  int _width = 0;
  int _height = 0;
  String _sceneType = 'cloudy';
  double _intensity = 1.0;
  bool _isDark = false;
  double _timeOfDay = 0.5;

  bool _isInitializing = false;
  bool _isDisposed = false;
  bool _isSupported = true;

  int? get textureId => _textureId;
  bool get isReady => _textureId != null && _isSupported;
  bool get isSupported => _isSupported;
  int get width => _width;
  int get height => _height;
  String get sceneType => _sceneType;
  double get intensity => _intensity;
  bool get isDark => _isDark;
  double get timeOfDay => _timeOfDay;

  /// Initializes the native GPU texture surface.
  Future<int?> initialize({
    required int width,
    required int height,
    String sceneType = 'cloudy',
    double intensity = 1.0,
    bool isDark = false,
    double timeOfDay = 0.5,
  }) async {
    if (_isDisposed) return null;
    if (_textureId != null) return _textureId;
    if (_isInitializing) return null;

    _isInitializing = true;
    _width = width;
    _height = height;
    _sceneType = sceneType;
    _intensity = intensity;
    _isDark = isDark;
    _timeOfDay = timeOfDay;

    try {
      final result = await _channel.invokeMethod<dynamic>('initialize', {
        'width': width,
        'height': height,
        'sceneType': sceneType,
        'intensity': intensity,
        'isDark': isDark,
        'timeOfDay': timeOfDay,
      });
      final id = (result is num) ? result.toInt() : (result as int?);

      if (_isDisposed) {
        if (id != null) {
          await _channel.invokeMethod('dispose', {'textureId': id});
        }
        return null;
      }

      _textureId = id;
      _isSupported = (id != null);
      notifyListeners();
      return id;
    } on MissingPluginException {
      // Platform doesn't have native GPU plugin attached (e.g. pure web or unit tests)
      _isSupported = false;
      notifyListeners();
      return null;
    } on PlatformException catch (e) {
      debugPrint('HyperGpuEngine initialize error: $e');
      _isSupported = false;
      notifyListeners();
      return null;
    } finally {
      _isInitializing = false;
    }
  }

  /// Resizes the native GPU texture surface.
  Future<void> resize(int width, int height) async {
    if (_isDisposed || _textureId == null || !_isSupported) return;
    if (_width == width && _height == height) return;

    _width = width;
    _height = height;

    try {
      await _channel.invokeMethod('resize', {
        'textureId': _textureId,
        'width': width,
        'height': height,
      });
      notifyListeners();
    } catch (e) {
      debugPrint('HyperGpuEngine resize error: $e');
    }
  }

  /// Updates weather simulation parameters on the GPU.
  Future<void> updateWeather({
    String? sceneType,
    double? intensity,
    bool? isDark,
    double? timeOfDay,
  }) async {
    if (_isDisposed || _textureId == null || !_isSupported) return;

    if (sceneType != null) _sceneType = sceneType;
    if (intensity != null) _intensity = intensity;
    if (isDark != null) _isDark = isDark;
    if (timeOfDay != null) _timeOfDay = timeOfDay;

    try {
      await _channel.invokeMethod('updateWeather', {
        'textureId': _textureId,
        'type': _sceneType,
        'intensity': _intensity,
        'isDark': _isDark,
        'timeOfDay': _timeOfDay,
      });
      notifyListeners();
    } catch (e) {
      debugPrint('HyperGpuEngine updateWeather error: $e');
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    if (_textureId != null && _isSupported) {
      final id = _textureId;
      _textureId = null;
      _channel.invokeMethod('dispose', {'textureId': id}).catchError((_) {});
    }
    super.dispose();
  }
}

/// Seamless zero-copy GPU native weather backdrop widget.
/// Renders directly into Flutter's compositor via Texture(textureId: id),
/// avoiding any `layer.toImage` snapshotting, CPU allocations, or memory thrashing.
class HyperGpuWeatherBackdrop extends StatefulWidget {
  const HyperGpuWeatherBackdrop({
    super.key,
    this.controller,
    this.weatherType = 'cloudy',
    this.intensity = 1.0,
    this.isDark = false,
    this.timeOfDay = 0.5,
    this.fallback,
    this.child,
  });

  final HyperGpuEngine? controller;
  final String weatherType;
  final double intensity;
  final bool isDark;
  final double timeOfDay;
  final Widget? fallback;
  final Widget? child;

  @override
  State<HyperGpuWeatherBackdrop> createState() => _HyperGpuWeatherBackdropState();
}

class _HyperGpuWeatherBackdropState extends State<HyperGpuWeatherBackdrop> {
  HyperGpuEngine? _internalEngine;
  HyperGpuEngine get _effectiveEngine => widget.controller ?? (_internalEngine ??= HyperGpuEngine());

  int _lastWidth = 0;
  int _lastHeight = 0;

  @override
  void initState() {
    super.initState();
    _effectiveEngine.addListener(_onEngineChanged);
  }

  @override
  void didUpdateWidget(HyperGpuWeatherBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller?.removeListener(_onEngineChanged);
      widget.controller?.addListener(_onEngineChanged);
    }
    if (widget.weatherType != oldWidget.weatherType ||
        widget.intensity != oldWidget.intensity ||
        widget.isDark != oldWidget.isDark ||
        widget.timeOfDay != oldWidget.timeOfDay) {
      _effectiveEngine.updateWeather(
        sceneType: widget.weatherType,
        intensity: widget.intensity,
        isDark: widget.isDark,
        timeOfDay: widget.timeOfDay,
      );
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _internalEngine?.dispose();
    } else {
      widget.controller?.removeListener(_onEngineChanged);
    }
    super.dispose();
  }

  void _onEngineChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
        final w = (constraints.maxWidth * dpr).round();
        final h = (constraints.maxHeight * dpr).round();

        if (w > 0 && h > 0 && (w != _lastWidth || h != _lastHeight)) {
          _lastWidth = w;
          _lastHeight = h;
          if (_effectiveEngine.isReady) {
            _effectiveEngine.resize(w, h);
          } else if (!_effectiveEngine.isReady && _effectiveEngine.isSupported) {
            _effectiveEngine.initialize(
              width: w,
              height: h,
              sceneType: widget.weatherType,
              intensity: widget.intensity,
              isDark: widget.isDark,
              timeOfDay: widget.timeOfDay,
            );
          }
        }

        final textureId = _effectiveEngine.textureId;
        final hasNativeTexture = _effectiveEngine.isReady && textureId != null;

        return Stack(
          fit: StackFit.expand,
          children: [
            if (hasNativeTexture)
              Texture(textureId: textureId, filterQuality: FilterQuality.linear)
            else if (widget.fallback != null)
              widget.fallback!
            else
              const SizedBox.expand(),
            if (widget.child != null) widget.child!,
          ],
        );
      },
    );
  }
}
