import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

/// Stress mode for hunting overflows: run the whole suite on a small, narrow
/// phone with big text.
///
/// `flutter test --dart-define=SWEEP_W=320 --dart-define=SWEEP_H=640 --dart-define=SWEEP_TEXT=2`
///
/// Without the defines (the normal run) nothing changes.
const double _w = 0.0 + int.fromEnvironment('SWEEP_W');
const double _h = 0.0 + int.fromEnvironment('SWEEP_H', defaultValue: 640);
const double _text = 0.0 + int.fromEnvironment('SWEEP_TEXT', defaultValue: 1);

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (_w > 0) {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    setUp(() {
      final view = binding.platformDispatcher.views.first;
      view.physicalSize = const Size(_w * 3, _h * 3);
      view.devicePixelRatio = 3;
      binding.platformDispatcher.textScaleFactorTestValue = _text;
    });
    tearDown(() {
      final view = binding.platformDispatcher.views.first;
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
      binding.platformDispatcher.clearTextScaleFactorTestValue();
    });
  }
  await testMain();
}
