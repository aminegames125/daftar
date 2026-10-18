import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/core_routes.dart';
import '../../../../app/settings.dart';
import '../../../../domain/models/product.dart';
import '../../../core/brand/dal_mark.dart';
import '../../../core/motion/daftar_motion.dart';
import '../../../core/motion/squish.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/collapsing_header.dart';
import '../../../core/widgets/floating_toast.dart';
import '../../../core/widgets/theme_reveal.dart';
import '../../lock/view_models/lock_controller.dart';
import '../../lock/views/pin_flow_screen.dart';
import '../view_models/managed_lists.dart';
import 'backup_section.dart';
import 'nearby_alerts_section.dart';
import 'settings_widgets.dart';

/// App version shown in "About" (keep in sync with pubspec.yaml).
const String appVersion = '0.1.0';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: CustomScrollView(
        slivers: [
          CollapsingHeader(
            title: 'Settings',
            expandedHeight: 96,
            leading: HeaderIconButton(
              icon: Icons.arrow_back_rounded,
              label: 'Back',
              onTap: () => context.pop(),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.lg,
              Space.gutter,
              Space.xxxl,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate(const [
                _AppearanceSection(),
                _PricesSection(),
                _ListsSection(),
                NearbyAlertsSection(),
                _SecuritySection(),
                BackupSection(),
                _AboutSection(),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Appearance ---------------------------------------------------------------

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blur = ref.watch(glassBlurProvider);
    return SettingsSection(
      title: 'Appearance',
      children: [
        const Padding(
          padding: EdgeInsets.all(Space.lg),
          child: ThemeSwitcher(),
        ),
        SettingsSwitchTile(
          icon: Icons.blur_on_rounded,
          title: 'Glass blur',
          subtitle: blur
              ? 'Frosted bars and menus'
              : 'Off: lighter on older phones',
          value: blur,
          onChanged: (v) => ref.read(glassBlurProvider.notifier).set(v),
        ),
      ],
    );
  }
}

/// System / Dark / Light with the circular reveal starting at the tapped segment.
class ThemeSwitcher extends ConsumerWidget {
  const ThemeSwitcher({super.key});

  static const _options = [
    (ThemeMode.system, 'System', Icons.brightness_auto_rounded),
    (ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
    (ThemeMode.light, 'Light', Icons.light_mode_outlined),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return Row(
      children: [
        for (final (i, (value, label, icon)) in _options.indexed)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : Space.sm),
              child: Builder(
                builder: (segmentContext) => _ThemeSegment(
                  label: label,
                  icon: icon,
                  selected: value == mode,
                  onTap: () {
                    if (value == mode) return;
                    HapticFeedback.selectionClick();
                    final box = segmentContext.findRenderObject()! as RenderBox;
                    final origin = box.localToGlobal(
                      box.size.center(Offset.zero),
                    );
                    ref
                        .read(themeRevealProvider)
                        .run(
                          origin: origin,
                          animate: !DaftarMotion.reduced(segmentContext),
                          apply: () =>
                              ref.read(themeModeProvider.notifier).set(value),
                        );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ThemeSegment extends StatelessWidget {
  const _ThemeSegment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final color = selected ? c.accentText : c.text;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label theme',
      excludeSemantics: true,
      onTap: onTap,
      child: Squish(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(
            vertical: Space.sm,
            horizontal: Space.xs,
          ),
          decoration: BoxDecoration(
            color: selected ? c.lime.withValues(alpha: 0.12) : c.raised,
            borderRadius: Radii.inputR,
            border: Border.all(color: selected ? c.accentText : c.line),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: Space.xs),
              Text(
                label,
                style: t.labelMedium?.copyWith(color: color),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Prices -------------------------------------------------------------------

class _PricesSection extends ConsumerWidget {
  const _PricesSection();

  static const _staleChoices = [
    (30, '1 month'),
    (60, '2 months'),
    (90, '3 months'),
    (180, '6 months'),
    (365, '1 year'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stale = ref.watch(staleDaysProvider);
    final unit = ref.watch(defaultUnitProvider);
    final t = Theme.of(context).textTheme;
    final options = [
      if (!_staleChoices.any((o) => o.$1 == stale)) (stale, '$stale days'),
      ..._staleChoices,
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    return SettingsSection(
      title: 'Prices',
      children: [
        Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Prices become "old" after', style: t.titleMedium),
              const SizedBox(height: Space.xs),
              Text(
                'Old prices are faded and trusted less when comparing.',
                style: t.bodySmall,
              ),
              const SizedBox(height: Space.md),
              ChoiceChips<int>(
                options: options,
                selected: stale,
                onSelected: (days) =>
                    ref.read(staleDaysProvider.notifier).set(days),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Default unit', style: t.titleMedium),
              const SizedBox(height: Space.xs),
              Text(
                'Pre-selected when you add a size to a price.',
                style: t.bodySmall,
              ),
              const SizedBox(height: Space.md),
              ChoiceChips<SizeUnit?>(
                options: [
                  (null, 'None'),
                  for (final u in SizeUnit.values) (u, u.name),
                ],
                selected: unit,
                onSelected: (u) =>
                    ref.read(defaultUnitProvider.notifier).set(u),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- Lists --------------------------------------------------------------------

class _ListsSection extends StatelessWidget {
  const _ListsSection();

  static const _icons = {
    ManagedListKind.placeTypes: Icons.storefront_outlined,
    ManagedListKind.categories: Icons.category_outlined,
    ManagedListKind.paymentMethods: Icons.payments_outlined,
    ManagedListKind.globalPriceTypes: Icons.public,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SettingsSection(
      title: 'Manage lists',
      children: [
        for (final kind in ManagedListKind.values)
          SettingsTile(
            icon: _icons[kind]!,
            title: kind.title,
            trailing: Icon(Icons.chevron_right_rounded, color: c.muted),
            onTap: () => context.push(SettingsRoutes.manage(kind)),
          ),
      ],
    );
  }
}

// --- Security -----------------------------------------------------------------

class _SecuritySection extends ConsumerWidget {
  const _SecuritySection();

  Future<void> _enable(BuildContext context, WidgetRef ref) async {
    final pin = await context.push<String>(
      SettingsRoutes.pin(PinFlowMode.create),
    );
    if (pin == null || !context.mounted) return;
    final biometric = await ref.read(biometricAvailableProvider.future);
    await ref
        .read(lockControllerProvider.notifier)
        .enable(pin, biometric: biometric);
    if (context.mounted) {
      FloatingToast.show(context, 'App lock is on', kind: ToastKind.success);
    }
  }

  Future<void> _disable(BuildContext context, WidgetRef ref) async {
    final pin = await context.push<String>(
      SettingsRoutes.pin(PinFlowMode.verify),
    );
    if (pin == null || !context.mounted) return;
    await ref.read(lockControllerProvider.notifier).disable();
    if (context.mounted) FloatingToast.show(context, 'App lock is off');
  }

  Future<void> _change(BuildContext context, WidgetRef ref) async {
    final old = await context.push<String>(
      SettingsRoutes.pin(PinFlowMode.verify),
    );
    if (old == null || !context.mounted) return;
    final next = await context.push<String>(
      SettingsRoutes.pin(PinFlowMode.create),
    );
    if (next == null || !context.mounted) return;
    await ref.read(lockControllerProvider.notifier).changePin(next);
    if (context.mounted) {
      FloatingToast.show(context, 'PIN changed', kind: ToastKind.success);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final lock = ref.watch(lockControllerProvider);
    final biometricAvailable =
        ref.watch(biometricAvailableProvider).value ?? false;

    return SettingsSection(
      title: 'Security',
      children: [
        SettingsSwitchTile(
          icon: Icons.lock_outline_rounded,
          title: 'App lock',
          subtitle: lock.enabled
              ? 'Asks for your PIN. Screenshots are off.'
              : 'Ask for a PIN when you open Daftar',
          value: lock.enabled,
          onChanged: (on) =>
              on ? _enable(context, ref) : _disable(context, ref),
        ),
        if (lock.enabled) ...[
          SettingsTile(
            icon: Icons.pin_outlined,
            title: 'Change PIN',
            trailing: Icon(Icons.chevron_right_rounded, color: c.muted),
            onTap: () => _change(context, ref),
          ),
          if (biometricAvailable)
            SettingsSwitchTile(
              icon: Icons.fingerprint,
              title: 'Fingerprint',
              subtitle: 'Unlock without typing the PIN',
              value: lock.biometric,
              onChanged: (v) => ref
                  .read(lockControllerProvider.notifier)
                  .setBiometric(enabled: v),
            ),
          Padding(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Lock after leaving the app', style: t.titleMedium),
                const SizedBox(height: Space.md),
                ChoiceChips<Duration>(
                  options: [
                    for (final d in lockDelayChoices) (d, _delayLabel(d)),
                  ],
                  selected: lock.delay,
                  onSelected: (d) =>
                      ref.read(lockControllerProvider.notifier).setDelay(d),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static String _delayLabel(Duration d) {
    if (d == Duration.zero) return 'Immediately';
    if (d.inMinutes >= 1) return '${d.inMinutes} minutes';
    return '${d.inSeconds} seconds';
  }
}

// --- About --------------------------------------------------------------------

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: Column(
        children: [
          const DalMark(size: 40),
          const SizedBox(height: Space.md),
          Text('Daftar $appVersion', style: t.titleMedium),
          const SizedBox(height: Space.xs),
          Text('Your life, in your pocket.', style: t.bodySmall),
          const SizedBox(height: Space.xs),
          Text('Your data stays on this phone.', style: t.bodySmall),
        ],
      ),
    );
  }
}
