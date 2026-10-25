import 'package:flutter/widgets.dart';

import 'driver.dart';

/// Capture mode needs dart:io; it is never requested on the web.
bool get captureRequested => false;

Future<void> runCapture(GlobalKey root, DemoDriver driver) async {}
