import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/routes/prices_routes.dart';
import '../../../../domain/use_cases/unit_price.dart';
import '../../../core/motion/squish.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/skeleton.dart';
import '../view_models/barcode_lookup.dart';
import '../view_models/scan_view_model.dart';
import 'barcode_laser.dart';
import 'camera_scanner_view.dart';

/// Barcode scanner (`/scan`).
///
/// * `pickMode` (`/scan?pick=1`): pops with the scanned code. Used by the scan
///   button on "Log a price", which does its own lookup.
/// * otherwise: looks the code up (your products first, then Open Food Facts) and
///   offers "Log a price" / "View prices". Works offline: a code that cannot be
///   found online just opens a blank "Log a price" with the barcode attached.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key, this.pickMode = false});

  final bool pickMode;

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  bool _torch = false;
  bool _popped = false;
  ScannerProblem? _problem;

  void _back() => context.canPop() ? context.pop() : context.go(Routes.home);

  Future<void> _onCode(String code) async {
    if (_popped) return;
    unawaited(HapticFeedback.mediumImpact());
    if (widget.pickMode) {
      _popped = true;
      context.pop(code.trim());
      return;
    }
    await ref.read(scanViewModelProvider.notifier).onCode(code);
  }

  Future<void> _typeCode() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _TypeCodeDialog(),
    );
    if (code != null && code.trim().isNotEmpty && mounted) await _onCode(code);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final state = ref.watch(scanViewModelProvider);
    final scannerView = ref.watch(scannerViewBuilderProvider);
    final showCard = state is! ScanWaiting;

    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          scannerView(context, _onCode, _torch, (p) {
            if (mounted && _problem != p) setState(() => _problem = p);
          }),
          if (_problem != null) _CameraProblem(problem: _problem!),
          // Dim everything except the frame.
          if (_problem == null)
            IgnorePointer(
              child: ColoredBox(color: c.background.withValues(alpha: 0.35)),
            ),
          if (!showCard && _problem == null)
            const IgnorePointer(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 90),
                  child: BarcodeLaser(),
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Space.gutter),
              child: Row(
                children: [
                  _RoundButton(
                    icon: Icons.arrow_back_rounded,
                    label: 'Back',
                    onTap: _back,
                  ),
                  const Spacer(),
                  if (_problem == null)
                    _RoundButton(
                      icon: _torch
                          ? Icons.flashlight_on_rounded
                          : Icons.flashlight_off_rounded,
                      label: _torch
                          ? 'Turn the light off'
                          : 'Turn the light on',
                      onTap: () => setState(() => _torch = !_torch),
                    ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  0,
                  Space.gutter,
                  Chrome.barBottom,
                ),
                child: showCard
                    ? _ResultCard(
                        state: state,
                        onAgain: ref.read(scanViewModelProvider.notifier).reset,
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _problem == null
                                ? 'Point the camera at a barcode'
                                : 'You can still enter the barcode by hand',
                            style: t.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: Space.md),
                          Squish(
                            onTap: _typeCode,
                            child: Semantics(
                              container: true,
                              button: true,
                              label: 'Type the code instead',
                              excludeSemantics: true,
                              child: Container(
                                height: Chrome.minTouch,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: Space.xl,
                                ),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: c.raised,
                                  borderRadius: Radii.pillR,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.keyboard_outlined,
                                      size: 20,
                                      color: c.text,
                                    ),
                                    const SizedBox(width: Space.sm),
                                    Text(
                                      'Type the code',
                                      style: t.labelLarge?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Empty state when the camera cannot be used (permission refused, no camera).
class _CameraProblem extends StatelessWidget {
  const _CameraProblem({required this.problem});

  final ScannerProblem problem;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final denied = problem == ScannerProblem.permissionDenied;
    return ColoredBox(
      color: c.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(Space.gutter),
          child: Semantics(
            container: true,
            liveRegion: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.no_photography_outlined, size: 56, color: c.muted),
                const SizedBox(height: Space.lg),
                Text(
                  denied
                      ? 'Camera access is off'
                      : 'The camera is not available',
                  style: t.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Space.sm),
                Text(
                  denied
                      ? 'Allow the camera for Daftar in Android Settings > Apps > Daftar > Permissions, then come back. Or type the code under the barcode.'
                      : 'Something is using the camera, or this phone has none. Type the code under the barcode instead.',
                  style: t.bodyMedium?.copyWith(color: c.muted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: label,
      child: Semantics(
        container: true,
        button: true,
        label: label,
        excludeSemantics: true,
        child: Squish(
          onTap: onTap,
          child: Container(
            width: Chrome.minTouch,
            height: Chrome.minTouch,
            decoration: BoxDecoration(
              color: c.glass,
              shape: BoxShape.circle,
              border: Border.all(color: c.glassBorder),
            ),
            child: Icon(icon, size: 22, color: c.text),
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.state, required this.onAgain});

  final ScanState state;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;

    Widget body;
    switch (state) {
      case ScanLooking(:final barcode):
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(barcode, style: t.bodySmall),
            const SizedBox(height: Space.md),
            const Skeleton(width: 200, height: 20),
            const SizedBox(height: Space.sm),
            const Skeleton(width: 120, height: 14),
          ],
        );
      case ScanResult(:final match):
        body = _matchBody(context, match);
      case ScanWaiting():
        body = const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: Radii.sheetR,
        border: Border.all(color: c.line),
      ),
      child: body,
    );
  }

  Widget _matchBody(BuildContext context, BarcodeMatch match) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;

    final (title, subtitle) = switch (match) {
      LocalMatch(:final product, :final variant) => (
        product.name,
        [
          'In your notebook',
          if (product.brand != null) product.brand!,
          if (variant.name != null) variant.name!,
          if (variant.sizeValue != null && variant.sizeUnit != null)
            formatSize(variant.sizeValue!, variant.sizeUnit!),
        ].join(' · '),
      ),
      OffMatch(:final product) => (
        product.name,
        ['Open Food Facts', ?product.brand, ?product.quantityText].join(' · '),
      ),
      NoMatch(:final offline) => (
        'New barcode',
        offline
            ? 'You are offline, so we could not look it up. Type the product in.'
            : 'Not found online. Type the product in.',
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(match.barcode, style: t.bodySmall),
        const SizedBox(height: Space.xs),
        Text(
          title,
          style: t.headlineSmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: Space.xs),
        Text(subtitle, style: t.bodySmall),
        const SizedBox(height: Space.lg),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: match is LocalMatch
                    ? () => context.pushReplacement(
                        '${Routes.productDetail(match.product.id)}?variantId=${match.variant.id}',
                      )
                    : onAgain,
                child: Text(match is LocalMatch ? 'View prices' : 'Scan again'),
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: FilledButton(
                onPressed: () => context.pushReplacement(switch (match) {
                  LocalMatch(:final product, :final variant) =>
                    logPriceLocation(
                      productId: product.id,
                      variantId: variant.id,
                    ),
                  _ => logPriceLocation(barcode: match.barcode),
                }),
                child: const Text('Log price'),
              ),
            ),
          ],
        ),
        if (match is LocalMatch)
          Align(
            alignment: Alignment.center,
            child: TextButton(
              onPressed: onAgain,
              style: TextButton.styleFrom(
                foregroundColor: c.muted,
                minimumSize: const Size(0, Chrome.minTouch),
              ),
              child: const Text('Scan another'),
            ),
          ),
      ],
    );
  }
}

/// Owns its controller, so it is disposed only after the dialog has gone.
class _TypeCodeDialog extends StatefulWidget {
  const _TypeCodeDialog();

  @override
  State<_TypeCodeDialog> createState() => _TypeCodeDialogState();
}

class _TypeCodeDialogState extends State<_TypeCodeDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Type the code'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: const InputDecoration(hintText: 'Digits under the barcode'),
      onSubmitted: (v) => Navigator.of(context).pop(v),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(_controller.text),
        child: const Text('Use code'),
      ),
    ],
  );
}
