import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Builds the live camera view. Tests override [scannerViewBuilderProvider] with
/// a fake that needs no camera.
typedef ScannerViewBuilder = Widget Function(
  BuildContext context,
  ValueChanged<String> onCode,
  bool torchOn,
  ValueChanged<ScannerProblem> onProblem,
);

/// Why the camera cannot be used. The scan screen shows the empty state.
enum ScannerProblem { permissionDenied, unavailable }

final scannerViewBuilderProvider = Provider<ScannerViewBuilder>(
  (ref) =>
      (context, onCode, torchOn, onProblem) => CameraScannerView(
        onCode: onCode,
        torchOn: torchOn,
        onProblem: onProblem,
      ),
);

/// The product barcode types worth reading (shop items), not QR codes.
const _formats = [
  BarcodeFormat.ean13,
  BarcodeFormat.ean8,
  BarcodeFormat.upcA,
  BarcodeFormat.upcE,
  BarcodeFormat.code128,
  BarcodeFormat.code39,
  BarcodeFormat.itf2of5,
];

/// `mobile_scanner` camera preview that reports each new barcode once.
class CameraScannerView extends StatefulWidget {
  const CameraScannerView({
    super.key,
    required this.onCode,
    required this.onProblem,
    this.torchOn = false,
  });

  final ValueChanged<String> onCode;
  final ValueChanged<ScannerProblem> onProblem;
  final bool torchOn;

  @override
  State<CameraScannerView> createState() => _CameraScannerViewState();
}

class _CameraScannerViewState extends State<CameraScannerView>
    with WidgetsBindingObserver {
  final _controller = MobileScannerController(
    formats: _formats,
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _torch = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(CameraScannerView old) {
    super.didUpdateWidget(old);
    if (old.torchOn != widget.torchOn && widget.torchOn != _torch) {
      _torch = widget.torchOn;
      unawaited(_controller.toggleTorch().catchError((_) {}));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.hasCameraPermission) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _controller.start();
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _controller.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MobileScanner(
      controller: _controller,
      onDetect: (capture) {
        final code = capture.barcodes
            .map((b) => b.rawValue)
            .whereType<String>()
            .firstOrNull;
        if (code != null) widget.onCode(code);
      },
      errorBuilder: (context, error) {
        final problem =
            error.errorCode == MobileScannerErrorCode.permissionDenied
            ? ScannerProblem.permissionDenied
            : ScannerProblem.unavailable;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) widget.onProblem(problem);
        });
        return const SizedBox.shrink();
      },
    );
  }
}
