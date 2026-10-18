import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../domain/models/lookups.dart';
import '../../../../domain/models/place.dart';
import '../../../../domain/place_logic/opening_hours_edit.dart';
import '../../../../domain/place_logic/place_tabs.dart';
import '../../../core/format/relative_date.dart';
import '../../../core/motion/daftar_motion.dart';
import '../../../core/motion/squish.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/collapsing_header.dart';
import '../../../core/widgets/daftar_action_bar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/floating_toast.dart';
import '../../../core/widgets/skeleton.dart';
import '../../menus/views/menu_tab.dart';
import '../view_models/place_activity.dart';
import '../view_models/place_launcher.dart';
import '../view_models/places_providers.dart';
import 'copy_chip.dart';
import 'open_status_badge.dart';
import 'place_icons.dart';
import 'rating_stars.dart';
import 'stored_image.dart';

/// A place: info, "Your usual", and the tab that fits its kind (Products or
/// Menu / Price list), History and Notes. Floating action toolbar: Call,
/// Directions, Copy Wi-Fi and the lime "Log price".
class PlaceDetailScreen extends ConsumerStatefulWidget {
  const PlaceDetailScreen({super.key, required this.placeId});

  final String placeId;

  @override
  ConsumerState<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

class _PlaceDetailScreenState extends ConsumerState<PlaceDetailScreen> {
  PlaceTab? _tab;

  void _back() => context.canPop() ? context.pop() : context.go(Routes.home);

  Future<void> _logPrice() async {
    await context.push('${Routes.logPrice}?placeId=${widget.placeId}');
    if (mounted) ref.invalidate(placeActivityProvider(widget.placeId));
  }

  Future<void> _openProduct(String productId) async {
    await context.push(Routes.productDetail(productId));
    if (mounted) ref.invalidate(placeActivityProvider(widget.placeId));
  }

  Future<void> _call(Place place) async {
    if (!await callPlace(place) && mounted) {
      FloatingToast.show(
        context,
        "Can't start a call from here",
        kind: ToastKind.error,
      );
    }
  }

  Future<void> _directions(Place place) async {
    if (!await directionsToPlace(place) && mounted) {
      FloatingToast.show(context, 'No maps app found', kind: ToastKind.error);
    }
  }

  Future<void> _copyWifi(Place place) async {
    await Clipboard.setData(ClipboardData(text: place.wifiPassword!));
    unawaited(HapticFeedback.mediumImpact());
    if (mounted) {
      FloatingToast.show(
        context,
        'Wi-Fi password copied',
        subtitle: place.wifiName,
        kind: ToastKind.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final placeAsync = ref.watch(placeProvider(widget.placeId));
    final types = ref.watch(placeTypesProvider).value ?? const <PlaceType>[];

    return placeAsync.when(
      loading: () => const Scaffold(
        body: SafeArea(
          child: SkeletonList(padding: EdgeInsets.all(Space.gutter)),
        ),
      ),
      error: (_, _) => Scaffold(
        body: Center(
          child: EmptyState(
            message: "Couldn't load this place.",
            actionLabel: 'Back',
            onAction: _back,
          ),
        ),
      ),
      data: (place) {
        if (place == null) {
          return Scaffold(
            body: Center(
              child: EmptyState(
                message: 'This place is gone.',
                actionLabel: 'Back',
                onAction: _back,
              ),
            ),
          );
        }
        final type = placeTypeFor(types, place.typeId);
        final tabs = tabsFor(type);
        final current = tabs.any((t) => t.tab == _tab) ? _tab! : tabs.first.tab;
        return _buildPage(place, type, tabs, current);
      },
    );
  }

  Widget _buildPage(
    Place place,
    PlaceType type,
    List<PlaceTabInfo> tabs,
    PlaceTab current,
  ) {
    final c = context.colors;
    final photos = ref.watch(placePhotosProvider(place.id)).value ?? const [];
    final hasPhoto = photos.isNotEmpty;
    final subtitle = [
      type.name,
      if (place.address != null && place.address!.isNotEmpty) place.address!,
    ].join(' · ');
    final menuLabel = tabs
        .firstWhere(
          (t) => t.tab == PlaceTab.menu,
          orElse: () => (tab: PlaceTab.menu, label: 'Menu'),
        )
        .label;

    return Scaffold(
      extendBody: true,
      bottomNavigationBar: DaftarActionBar(
        actions: [
          ToolbarAction(
            icon: Icons.call_outlined,
            label: 'Call',
            onTap: (place.phone ?? '').trim().isEmpty
                ? null
                : () => _call(place),
          ),
          ToolbarAction(
            icon: Icons.directions_outlined,
            label: 'Directions',
            onTap: place.hasLocation ? () => _directions(place) : null,
          ),
          ToolbarAction(
            icon: Icons.wifi_rounded,
            label: 'Copy Wi-Fi',
            onTap: (place.wifiPassword ?? '').isEmpty
                ? null
                : () => _copyWifi(place),
          ),
        ],
        primary: ToolbarAction(
          icon: Icons.add_rounded,
          label: 'Log price',
          onTap: _logPrice,
        ),
      ),
      body: CustomScrollView(
        slivers: [
          CollapsingHeader(
            title: place.name,
            subtitle: subtitle,
            expandedHeight: hasPhoto ? 232 : 168,
            leading: HeaderIconButton(
              icon: Icons.arrow_back_rounded,
              label: 'Back',
              onTap: _back,
            ),
            actions: [
              HeaderIconButton(
                icon: Icons.edit_outlined,
                label: 'Edit place',
                onTap: () => context.push(Routes.placeEdit(place.id)),
              ),
            ],
            background: hasPhoto
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      StoredImage(path: photos.first.filePath),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              c.background.withValues(alpha: 0.2),
                              c.background.withValues(alpha: 0.92),
                            ],
                          ),
                        ),
                      ),
                    ],
                  )
                : null,
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.sm,
              Space.gutter,
              Chrome.contentBottomPadding,
            ),
            sliver: SliverList.list(
              children: [
                _Summary(place: place),
                if (type.kind == PlaceKind.venue) ...[
                  const SizedBox(height: Space.lg),
                  UsualCard(placeId: place.id),
                ],
                const SizedBox(height: Space.lg),
                _DetailsCard(place: place),
                const SizedBox(height: Space.xl),
                _PlaceTabs(
                  tabs: tabs,
                  current: current,
                  onChanged: (t) => setState(() => _tab = t),
                ),
                const SizedBox(height: Space.lg),
                AnimatedSwitcher(
                  duration: _fade(context),
                  child: KeyedSubtree(
                    key: ValueKey(current),
                    child: switch (current) {
                      PlaceTab.products => _ProductsTab(
                        placeId: place.id,
                        onOpenProduct: _openProduct,
                        onLogPrice: _logPrice,
                      ),
                      PlaceTab.menu => MenuTab(
                        placeId: place.id,
                        label: menuLabel,
                      ),
                      PlaceTab.history => _HistoryTab(
                        placeId: place.id,
                        onOpenProduct: _openProduct,
                      ),
                      PlaceTab.notes => _NotesTab(
                        place: place,
                        photoPaths: [for (final p in photos) p.filePath],
                      ),
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Duration _fade(BuildContext context) =>
    DaftarMotion.reduced(context) ? Duration.zero : DaftarMotion.base;

class _Summary extends StatelessWidget {
  const _Summary({required this.place});

  final Place place;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Space.md,
          runSpacing: Space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OpenStatusBadge(hours: place.openingHours, chip: true),
            if (place.rating != null)
              RatingStars(rating: place.rating, size: 20),
          ],
        ),
        if (place.tags.isNotEmpty) ...[
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final tag in place.tags)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Space.md,
                    vertical: Space.sm - 2,
                  ),
                  decoration: BoxDecoration(
                    color: c.raised,
                    borderRadius: Radii.chipR,
                  ),
                  child: Text(
                    tag,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _DetailsCard extends ConsumerStatefulWidget {
  const _DetailsCard({required this.place});

  final Place place;

  @override
  ConsumerState<_DetailsCard> createState() => _DetailsCardState();
}

class _DetailsCardState extends ConsumerState<_DetailsCard> {
  var _hoursOpen = false;

  @override
  Widget build(BuildContext context) {
    final place = widget.place;
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final payments =
        ref.watch(paymentMethodsProvider).value ?? const <PaymentMethod>[];
    final accepted = [
      for (final m in payments)
        if (place.paymentMethodIds.contains(m.id)) m,
    ];
    final hours = place.openingHours;
    final hasWifi =
        (place.wifiName ?? '').isNotEmpty ||
        (place.wifiPassword ?? '').isNotEmpty;

    final rows = <Widget>[
      if ((place.phone ?? '').isNotEmpty)
        _InfoRow(
          icon: Icons.call_outlined,
          semanticsLabel: 'Call ${place.phone}',
          onTap: () => callPlace(place),
          child: Text(place.phone!, style: t.bodyLarge),
        ),
      if ((place.address ?? '').isNotEmpty)
        _InfoRow(
          icon: Icons.place_outlined,
          child: Text(place.address!, style: t.bodyLarge),
        ),
      if (hours != null && hours.days.isNotEmpty)
        _InfoRow(
          icon: Icons.schedule_rounded,
          onTap: () => setState(() => _hoursOpen = !_hoursOpen),
          semanticsLabel: _hoursOpen
              ? 'Hide opening hours'
              : 'Show opening hours',
          trailing: Icon(
            _hoursOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            color: c.muted,
          ),
          child: _hoursOpen
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final g in groupHours(hours))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 84,
                              child: Text(
                                g.days,
                                style: t.bodyMedium?.copyWith(color: c.muted),
                              ),
                            ),
                            Expanded(child: Text(g.hours, style: t.bodyMedium)),
                          ],
                        ),
                      ),
                  ],
                )
              : Text('Opening hours', style: t.bodyLarge),
        ),
      if (hasWifi)
        _InfoRow(
          icon: Icons.wifi_rounded,
          trailing: (place.wifiPassword ?? '').isNotEmpty
              ? CopyChip(value: place.wifiPassword!, label: 'Copy')
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((place.wifiName ?? '').isNotEmpty)
                Text(place.wifiName!, style: t.bodyLarge),
              if ((place.wifiPassword ?? '').isNotEmpty)
                SelectableText(place.wifiPassword!, style: t.bodySmall),
            ],
          ),
        ),
      if (accepted.isNotEmpty)
        _InfoRow(
          icon: Icons.payments_outlined,
          child: Wrap(
            spacing: Space.sm,
            runSpacing: Space.xs,
            children: [
              for (final m in accepted)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(paymentIcon(m.iconKey), size: 16, color: c.muted),
                    const SizedBox(width: Space.xs),
                    Text(m.name, style: t.bodyMedium),
                  ],
                ),
            ],
          ),
        ),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: Radii.cardR,
        border: Border.all(color: c.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i != rows.length - 1)
              Divider(color: c.line, indent: Space.lg, endIndent: Space.lg),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.child,
    this.trailing,
    this.onTap,
    this.semanticsLabel,
  });

  final IconData icon;
  final Widget child;
  final Widget? trailing;
  final VoidCallback? onTap;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: Chrome.minTouch + Space.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: c.muted),
            const SizedBox(width: Space.md),
            Expanded(child: child),
            if (trailing != null) ...[
              const SizedBox(width: Space.sm),
              trailing!,
            ],
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: InkWell(borderRadius: Radii.cardR, onTap: onTap, child: row),
    );
  }
}

class _PlaceTabs extends StatelessWidget {
  const _PlaceTabs({
    required this.tabs,
    required this.current,
    required this.onChanged,
  });

  final List<PlaceTabInfo> tabs;
  final PlaceTab current;
  final ValueChanged<PlaceTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        for (final info in tabs)
          Expanded(
            child: Semantics(
              button: true,
              selected: info.tab == current,
              label: info.label,
              excludeSemantics: true,
              child: Squish(
                pressedScale: 0.97,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(info.tab);
                },
                child: SizedBox(
                  height: Chrome.minTouch,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Center(
                          child: Text(
                            info.label,
                            style: t.titleSmall?.copyWith(
                              color: info.tab == current ? c.text : c.muted,
                            ),
                          ),
                        ),
                      ),
                      AnimatedContainer(
                        duration: _fade(context),
                        height: 2,
                        color: info.tab == current ? c.text : c.line,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ProductsTab extends ConsumerWidget {
  const _ProductsTab({
    required this.placeId,
    required this.onOpenProduct,
    required this.onLogPrice,
  });

  final String placeId;
  final ValueChanged<String> onOpenProduct;
  final VoidCallback onLogPrice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(placeProductPricesProvider(placeId));
    final staleDays = ref.watch(staleDaysProvider).value ?? 90;
    return rows.when(
      loading: () => const SkeletonList(itemCount: 3),
      error: (_, _) => const EmptyState(message: "Couldn't load the prices."),
      data: (list) {
        if (list.isEmpty) {
          return EmptyState(
            message: 'No products priced here yet.',
            actionLabel: 'Log a price',
            onAction: onLogPrice,
          );
        }
        return Column(
          children: [
            for (final a in list)
              _ActivityRow(
                activity: a,
                staleDays: staleDays,
                onTap: () => onOpenProduct(a.productId!),
              ),
          ],
        );
      },
    );
  }
}

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab({required this.placeId, required this.onOpenProduct});

  final String placeId;
  final ValueChanged<String> onOpenProduct;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(placeActivityProvider(placeId));
    final staleDays = ref.watch(staleDaysProvider).value ?? 90;
    return all.when(
      loading: () => const SkeletonList(itemCount: 3),
      error: (_, _) => const EmptyState(message: "Couldn't load the history."),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyState(
            message: 'Every price you log here shows up in this list.',
          );
        }
        return Column(
          children: [
            for (final a in list)
              _ActivityRow(
                activity: a,
                staleDays: staleDays,
                showAge: false,
                onTap: a.productId == null
                    ? null
                    : () => onOpenProduct(a.productId!),
              ),
          ],
        );
      },
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.activity,
    required this.staleDays,
    this.onTap,
    this.showAge = true,
  });

  final PlaceActivity activity;
  final int staleDays;
  final VoidCallback? onTap;

  /// Fade prices older than the stale threshold (latest-per-product list only).
  final bool showAge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final e = activity.entry;
    final stale =
        showAge && DateTime.now().difference(e.seenAt).inDays > staleDays;
    final name = [
      activity.title,
      if ((activity.subtitle ?? '').isNotEmpty) activity.subtitle!,
    ].join(' · ');
    final price = e.amountMax == null
        ? e.amount.format()
        : '${e.amount.format()}–${e.amountMax!.format()}';

    return Squish(
      onTap: onTap,
      pressedScale: 0.98,
      child: Opacity(
        opacity: stale ? 0.4 : 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleMedium,
                      ),
                      Text(
                        [
                          'Seen ${formatRelativeDate(e.seenAt)}',
                          if (stale) 'old',
                          if (e.isPromo) 'promo',
                        ].join(' · '),
                        style: t.bodySmall?.copyWith(
                          color: e.isPromo && !stale ? c.amber : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.md),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: price,
                        style: t.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      TextSpan(
                        text: ' ${e.amount.currency.code}',
                        style: t.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NotesTab extends StatelessWidget {
  const _NotesTab({required this.place, required this.photoPaths});

  final Place place;
  final List<String> photoPaths;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final notes = place.notes;
    if ((notes == null || notes.isEmpty) && photoPaths.isEmpty) {
      return const EmptyState(
        message: 'No notes or photos yet.\nUse Edit to add some.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (notes != null && notes.isNotEmpty)
          SelectableText(notes, textDirection: null, style: t.bodyLarge),
        if (photoPaths.isNotEmpty) ...[
          const SizedBox(height: Space.xl),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: Space.sm,
            crossAxisSpacing: Space.sm,
            children: [
              for (final p in photoPaths)
                ClipRRect(
                  borderRadius: Radii.inputR,
                  child: StoredImage(path: p, cacheWidth: 360),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
