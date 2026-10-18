import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/services/nearby_alerts_service.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/floating_toast.dart';
import 'settings_widgets.dart';

/// Settings > Nearby alerts: an opt-in switch. Turning it on first shows what
/// the feature does and what it costs; only "Allow" asks for the permission.
class NearbyAlertsSection extends ConsumerWidget {
  const NearbyAlertsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(nearbyAlertsEnabledProvider);
    return SettingsSection(
      title: 'Nearby alerts',
      children: [
        SettingsSwitchTile(
          icon: Icons.near_me_outlined,
          title: 'Nearby alerts',
          subtitle: on
              ? 'Tells you when a saved place is cheaper for your list'
              : 'Off. Nothing about your location is used',
          value: on,
          onChanged: (v) => v ? _turnOn(context, ref) : _turnOff(ref),
        ),
      ],
    );
  }

  Future<void> _turnOff(WidgetRef ref) =>
      ref.read(nearbyAlertsEnabledProvider.notifier).disable();

  Future<void> _turnOn(BuildContext context, WidgetRef ref) async {
    final agreed = await showNearbyExplanation(context);
    if (agreed != true || !context.mounted) return;
    final result = await ref
        .read(nearbyAlertsEnabledProvider.notifier)
        .enable();
    if (!context.mounted) return;
    switch (result) {
      case NearbyPermission.granted:
        FloatingToast.show(
          context,
          'Nearby alerts are on',
          kind: ToastKind.success,
        );
      case NearbyPermission.serviceOff:
        FloatingToast.show(context, 'Turn on location in your phone first');
      case NearbyPermission.deniedForever:
        FloatingToast.show(
          context,
          'Location is blocked. Allow it in the phone settings',
        );
      case NearbyPermission.denied:
        FloatingToast.show(context, 'No permission, so alerts stay off');
    }
  }
}

/// The explanation shown before any permission request. Pops true on "Allow".
Future<bool?> showNearbyExplanation(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const NearbyExplanationSheet(),
  );
}

class NearbyExplanationSheet extends StatelessWidget {
  const NearbyExplanationSheet({super.key});

  static const _points = [
    (
      Icons.shopping_basket_outlined,
      'What it does',
      'When you are close to a saved place that has a cheaper price for '
          'something on your lists, Daftar sends one quiet notification.',
    ),
    (
      Icons.lock_outline_rounded,
      'Your privacy',
      'Your location is checked on this phone only. It is never saved, '
          'shared or uploaded.',
    ),
    (
      Icons.battery_saver_outlined,
      'Your battery',
      'Daftar looks only now and then, never tracks you, and stays quiet at '
          'night and for a few days after each alert.',
    ),
    (
      Icons.toggle_off_outlined,
      'Your choice',
      'It stays off until you allow it, and you can turn it off here any time.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.gutter),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Nearby alerts', style: t.headlineSmall),
            const SizedBox(height: Space.sm),
            Text(
              'Before Daftar asks for your location, here is what you are '
              'agreeing to.',
              style: t.bodyMedium?.copyWith(color: c.muted),
            ),
            const SizedBox(height: Space.lg),
            for (final (icon, title, body) in _points)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 22, color: c.muted),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: t.titleMedium),
                          const SizedBox(height: Space.xs),
                          Text(
                            body,
                            style: t.bodyMedium?.copyWith(color: c.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Allow location'),
            ),
            const SizedBox(height: Space.sm),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}
