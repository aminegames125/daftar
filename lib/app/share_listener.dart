import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

/// Receives text shared into Daftar (Google Maps "Share" → Daftar) and opens
/// the new-place form filled from it. It does nothing on platforms or in tests
/// where there is no share channel.
class ShareListener extends ConsumerStatefulWidget {
  const ShareListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ShareListener> createState() => _ShareListenerState();
}

class _ShareListenerState extends ConsumerState<ShareListener> {
  static const _channel = MethodChannel('com.amineos.daftar/share');

  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shared' && call.arguments is String) {
        _open(call.arguments as String);
      }
    });
    _askInitial();
  }

  Future<void> _askInitial() async {
    try {
      final text = await _channel.invokeMethod<String>('initialShare');
      if (text != null && text.trim().isNotEmpty) _open(text);
    } on MissingPluginException {
      // No share channel here (tests, desktop).
    } on PlatformException {
      // Nothing was shared.
    }
  }

  void _open(String text) {
    if (!mounted) return;
    ref.read(routerProvider).push(Routes.placeNewFrom(text));
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
