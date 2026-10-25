import 'package:flutter/foundation.dart';

/// Demo-wide temperature unit (the settings page edits it, the weather page shows it).
abstract final class TemperatureUnit {
  static final fahrenheit = ValueNotifier<bool>(false);

  /// [celsius] formatted in the current unit, e.g. 23 -> "23°" or "73°".
  static String format(int celsius) => fahrenheit.value ? '${(celsius * 9 / 5 + 32).round()}°' : '$celsius°';

  static String get label => fahrenheit.value ? '华氏度 °F' : '摄氏度 °C';
}
