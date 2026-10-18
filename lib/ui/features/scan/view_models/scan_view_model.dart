import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'barcode_lookup.dart';

/// What the scanner screen is doing.
sealed class ScanState {
  const ScanState();
}

/// Waiting for a barcode.
class ScanWaiting extends ScanState {
  const ScanWaiting();
}

/// A code was read; checking the database and Open Food Facts.
class ScanLooking extends ScanState {
  const ScanLooking(this.barcode);
  final String barcode;
}

class ScanResult extends ScanState {
  const ScanResult(this.match);
  final BarcodeMatch match;
}

final scanViewModelProvider =
    NotifierProvider.autoDispose<ScanViewModel, ScanState>(ScanViewModel.new);

class ScanViewModel extends Notifier<ScanState> {
  @override
  ScanState build() => const ScanWaiting();

  /// A barcode was read (or typed). Ignored while a lookup is running or shown.
  /// Returns false when it was ignored.
  Future<bool> onCode(String raw) async {
    final code = raw.trim();
    if (code.isEmpty || state is! ScanWaiting) return false;
    state = ScanLooking(code);
    final match = await ref.read(barcodeLookupProvider).lookup(code);
    if (ref.mounted) state = ScanResult(match);
    return true;
  }

  /// Back to scanning ("Scan again").
  void reset() => state = const ScanWaiting();
}
