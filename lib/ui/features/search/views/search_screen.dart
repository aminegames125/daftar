import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/routes/prices_routes.dart';
import '../../../../domain/models/product.dart';
import '../../../../domain/use_cases/unit_price.dart';
import '../../../core/motion/squish.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/glass_surface.dart';
import '../../../core/widgets/skeleton.dart';
import '../../map/views/price_map_view.dart';
import '../../products/view_models/offer_rows.dart';
import '../../products/views/offer_widgets.dart';
import '../../products/views/price_widgets.dart';
import '../../products/views/select_chip.dart';
import '../view_models/search_engine.dart';
import '../view_models/search_view_model.dart';
import 'shimmer_text.dart';

/// The Search tab: one bottom-first search box over products, variants, menu items
/// and places. A product / menu item shows the **Best option** card with the
/// reasons it won, then the other offers; a List / Map toggle shows the same
/// offers as price pins.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  SearchViewModel get _vm => ref.read(searchViewModelProvider.notifier);

  /// The body ends above the nav bar, so the box only sits near the bottom;
  /// the "+" is now inside the nav bar, so it spans the width.
  static const double _boxBottom = Space.md + Space.xs;
  static const double _boxRight = Space.gutter;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(searchViewModelProvider);
    final t = Theme.of(context).textTheme;
    const boxBottom = _boxBottom;
    const boxHeight = 52.0;
    const listBottom = boxBottom + boxHeight + Space.xl;
    final isMap = s.mode == SearchMode.map;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: isMap
              ? _MapMode(
                  state: s,
                  bottomInset: boxBottom + boxHeight + Space.md,
                )
              : SafeArea(
                  bottom: false,
                  child: _ListMode(
                    state: s,
                    bottomPadding: listBottom,
                    onRecent: _useRecent,
                  ),
                ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.lg,
                Space.gutter,
                0,
              ),
              child: Row(
                children: [
                  if (!isMap)
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text('Search', style: t.headlineLarge),
                      ),
                    )
                  else
                    const Spacer(),
                  _ModeToggle(mode: s.mode, onChanged: _vm.setMode),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: Space.gutter,
          right: _boxRight,
          bottom: boxBottom,
          child: _SearchBox(
            controller: _controller,
            onChanged: _vm.setQuery,
            onClear: _clear,
            onScan: () => context.push(Routes.scan),
            height: boxHeight,
          ),
        ),
      ],
    );
  }

  void _useRecent(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _vm.setQuery(text);
  }

  void _clear() {
    _controller.clear();
    _vm.setQuery('');
  }
}

// ------------------------------------------------------------------ chrome

class _SearchBox extends StatelessWidget {
  const _SearchBox({
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.onScan,
    required this.height,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onScan;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return GlassSurface(
      height: height,
      padding: const EdgeInsets.only(left: Space.lg, right: Space.xs),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 20, color: c.muted),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Semantics(
              container: true,
              textField: true,
              label: 'Search products, places and menus',
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                textDirection: null,
                textInputAction: TextInputAction.search,
                style: t.titleMedium,
                cursorColor: c.lime,
                decoration: InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: 'Search products, places, menus',
                  hintStyle: t.bodyMedium?.copyWith(color: c.muted),
                ),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    tooltip: 'Clear',
                    constraints: const BoxConstraints.tightFor(
                      width: Chrome.minTouch,
                      height: Chrome.minTouch,
                    ),
                    icon: Icon(Icons.close_rounded, size: 20, color: c.muted),
                    onPressed: onClear,
                  ),
          ),
          Tooltip(
            message: 'Scan barcode',
            child: Semantics(
              container: true,
              button: true,
              label: 'Scan barcode',
              excludeSemantics: true,
              child: Squish(
                onTap: onScan,
                child: SizedBox.square(
                  dimension: Chrome.minTouch,
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: c.line,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.qr_code_scanner_rounded,
                        size: 18,
                        color: c.text,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final SearchMode mode;
  final ValueChanged<SearchMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    Widget segment(SearchMode value, String label) {
      final selected = mode == value;
      return Semantics(
        container: true,
        button: true,
        selected: selected,
        label: '$label view',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            onChanged(value);
          },
          child: SizedBox(
            height: Chrome.minTouch,
            child: Center(
              child: Container(
                height: 36,
                constraints: const BoxConstraints(minWidth: 64),
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? c.text.withValues(alpha: 0.14)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  label,
                  style: t.labelMedium?.copyWith(
                    color: selected ? c.text : c.muted,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: GlassSurface(
        padding: const EdgeInsets.all(Space.xs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            segment(SearchMode.list, 'List'),
            segment(SearchMode.map, 'Map'),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- list mode

class _ListMode extends ConsumerWidget {
  const _ListMode({
    required this.state,
    required this.bottomPadding,
    required this.onRecent,
  });

  final SearchState state;
  final double bottomPadding;
  final ValueChanged<String> onRecent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final padding = EdgeInsets.fromLTRB(
      Space.gutter,
      72,
      Space.gutter,
      bottomPadding,
    );

    switch (state.status) {
      case SearchStatus.idle:
        if (state.recents.isNotEmpty) {
          return _Recents(state: state, padding: padding, onPick: onRecent);
        }
        return Padding(
          padding: padding,
          child: const Center(
            child: EmptyState(message: 'Search prices, places and menus.'),
          ),
        );
      case SearchStatus.searching:
        return ListView(
          padding: padding,
          children: [
            ShimmerText(
              'Searching for “${state.query.trim()}”…',
              style: t.titleMedium,
            ),
            const SizedBox(height: Space.lg),
            const Skeleton(height: 150, radius: Radii.card),
            const SizedBox(height: Space.lg),
            const SkeletonList(itemCount: 3),
          ],
        );
      case SearchStatus.failed:
        return Padding(
          padding: padding,
          child: const Center(
            child: EmptyState(message: 'Search hit a snag. Try again.'),
          ),
        );
      case SearchStatus.done:
        if (state.shown.isEmpty) {
          final filtered =
              state.filter != SearchFilter.all && !state.results.isEmpty;
          return ListView(
            padding: padding,
            children: [
              if (!state.results.isEmpty) _FilterChips(filter: state.filter),
              const SizedBox(height: Space.xxl),
              EmptyState(
                message: filtered
                    ? 'No ${state.filter.label.toLowerCase()} match “${state.query.trim()}”.'
                    : 'Nothing matches “${state.query.trim()}”.',
                actionLabel: filtered ? null : 'Log a price',
                onAction: filtered
                    ? null
                    : () => context.push(logPriceLocation()),
              ),
            ],
          );
        }
        return _Results(state: state, padding: padding);
    }
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.state, required this.padding});

  final SearchState state;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final vm = ref.read(searchViewModelProvider.notifier);
    final results = state.shown;
    final active = state.active;
    final others = [
      for (var i = 0; i < results.priced.length; i++)
        if (i != state.selected) (i, results.priced[i]),
    ];

    return ListView(
      padding: padding,
      children: [
        _FilterChips(filter: state.filter),
        const SizedBox(height: Space.lg),
        if (active != null) ..._active(context, active),
        if (others.isNotEmpty) ...[
          const SizedBox(height: Space.xxl),
          Text('More results', style: t.headlineSmall),
          const SizedBox(height: Space.sm),
          for (final (index, hit) in others)
            _HitRow(hit: hit, onTap: () => vm.select(index)),
        ],
        if (results.places.isNotEmpty) ...[
          const SizedBox(height: Space.xxl),
          Text('Places', style: t.headlineSmall),
          const SizedBox(height: Space.sm),
          for (final hit in results.places)
            _PlaceRow(hit: hit, onOpen: () => unawaited(vm.remember())),
        ],
      ],
    );
  }

  List<Widget> _active(BuildContext context, PricedHit active) {
    switch (active) {
      case ProductPriced(:final hit):
        return _productSection(context, hit);
      case MenuPriced(:final hit):
        return _menuSection(context, hit);
    }
  }

  List<Widget> _productSection(BuildContext context, ProductHit hit) {
    final offers = hit.offers;
    final best = offers.best;
    if (best == null) {
      return [
        _NoPrices(
          title: hit.title,
          onLog: () =>
              context.push(logPriceLocation(productId: hit.product.id)),
        ),
      ];
    }
    final variants = {for (final r in offers.rows) ?r.variant?.id}.length;
    final now = state.now ?? DateTime.now();
    return [
      BestOptionCard(
        title: _variantTitle(hit.product, best.variant),
        store: best.title,
        amount: best.entry.amount,
        amountMax: best.entry.amountMax,
        reasons: offers.reasons,
        caption:
            '${offers.rows.length} ${offers.rows.length == 1 ? 'offer' : 'offers'}${variants > 1 ? ' · $variants variants' : ''}',
        unitLabel: best.unitPrice == null
            ? null
            : '${best.unitPrice!.formatWithCode()} ${offers.basis.unitLabel}',
        onTap: () => _open(
          context,
          '${Routes.productDetail(hit.product.id)}${best.variant == null ? '' : '?variantId=${best.variant!.id}'}',
        ),
      ),
      if (offers.rows.length > 1) ...[
        const SizedBox(height: Space.xl),
        Text('Other offers', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: Space.sm),
        for (final row in offers.rows.skip(1))
          OfferTile(
            row: row,
            now: now,
            subtitlePrefix: variants > 1 && row.variant != null
                ? _variantLabel(row.variant!)
                : null,
            onTap: row.place == null
                ? null
                : () => _open(context, Routes.placeDetail(row.place!.id)),
          ),
      ],
    ];
  }

  List<Widget> _menuSection(BuildContext context, MenuHit hit) {
    if (hit.groups.isEmpty) {
      return [
        _NoPrices(
          title: hit.title,
          onLog: () => context.push(logPriceLocation()),
        ),
      ];
    }
    final group = hit.groups[state.optionGroup.clamp(0, hit.groups.length - 1)];
    final offers = group.offers;
    final best = offers.best!;
    final now = state.now ?? DateTime.now();
    return [
      if (hit.groups.length > 1) ...[
        Consumer(
          builder: (context, ref, _) => Wrap(
            spacing: Space.sm,
            children: [
              for (var i = 0; i < hit.groups.length; i++)
                SelectChip(
                  label: hit.groups[i].label ?? 'Standard',
                  selected: i == state.optionGroup,
                  onTap: () => ref
                      .read(searchViewModelProvider.notifier)
                      .selectOptionGroup(i),
                ),
            ],
          ),
        ),
        const SizedBox(height: Space.md),
      ],
      BestOptionCard(
        title: group.label == null
            ? hit.title
            : '${hit.title} · ${group.label}',
        store: best.title,
        amount: best.entry.amount,
        amountMax: best.entry.amountMax,
        reasons: offers.reasons,
        caption:
            '${offers.rows.length} ${offers.rows.length == 1 ? 'venue' : 'venues'}',
        onTap: best.place == null
            ? null
            : () => _open(context, Routes.placeDetail(best.place!.id)),
      ),
      if (offers.rows.length > 1) ...[
        const SizedBox(height: Space.xl),
        Text(
          'Everywhere else',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: Space.sm),
        for (final row in offers.rows.skip(1))
          OfferTile(
            row: row,
            now: now,
            onTap: row.place == null
                ? null
                : () => _open(context, Routes.placeDetail(row.place!.id)),
          ),
      ],
    ];
  }
}

/// Opens a result and remembers the query that found it.
void _open(BuildContext context, String location) {
  unawaited(
    ProviderScope.containerOf(context)
        .read(searchViewModelProvider.notifier)
        .remember(),
  );
  context.push(location);
}

String _variantLabel(Variant v) {
  final size = v.sizeValue != null && v.sizeUnit != null
      ? formatSize(v.sizeValue!, v.sizeUnit!)
      : null;
  return [?v.name, ?size].join(' · ');
}

String _variantTitle(Product product, Variant? variant) {
  final label = variant == null ? '' : _variantLabel(variant);
  return label.isEmpty ? product.name : '${product.name} · $label';
}

class _NoPrices extends StatelessWidget {
  const _NoPrices({required this.title, required this.onLog});

  final String title;
  final VoidCallback onLog;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: Radii.cardR,
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: t.headlineSmall),
          const SizedBox(height: Space.xs),
          Text('No price logged yet.', style: t.bodySmall),
          const SizedBox(height: Space.lg),
          FilledButton(onPressed: onLog, child: const Text('Log a price')),
        ],
      ),
    );
  }
}

/// A compact row for another priced match: name and its best price.
class _HitRow extends StatelessWidget {
  const _HitRow({required this.hit, required this.onTap});

  final PricedHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final (subtitle, best) = switch (hit) {
      ProductPriced(:final hit) => (
        [
          ?hit.product.brand,
          if (hit.offers.best != null)
            hit.offers.best!.title
          else
            'No price yet',
        ].join(' · '),
        hit.offers.best?.entry,
      ),
      MenuPriced(:final hit) => (
        '${hit.venueCount} ${hit.venueCount == 1 ? 'venue' : 'venues'}',
        hit.groups.firstOrNull?.offers.best?.entry,
      ),
    };
    return Semantics(
      container: true,
      button: true,
      label:
          '${hit.title}, $subtitle${best == null ? '' : ', ${best.amount.formatWithCode()}'}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: Radii.inputR,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 58),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.raised,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  hit is ProductPriced
                      ? Icons.shopping_bag_outlined
                      : Icons.local_cafe_outlined,
                  size: 20,
                  color: c.text,
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hit.title,
                      style: t.titleMedium?.copyWith(fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: t.bodySmall?.copyWith(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (best != null)
                PriceAmount(
                  amount: best.amount,
                  amountMax: best.amountMax,
                  size: 16,
                  showCode: false,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({required this.hit, required this.onOpen});

  final PlaceHit hit;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final place = hit.place;
    return Semantics(
      container: true,
      button: true,
      label:
          '${place.name}${place.address == null ? '' : ', ${place.address}'}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: Radii.inputR,
        onTap: () {
          onOpen();
          context.push(Routes.placeDetail(place.id));
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 58),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.raised,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.place_outlined, size: 20, color: c.text),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place.name,
                      style: t.titleMedium?.copyWith(fontSize: 15),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (place.address != null)
                      Text(
                        place.address!,
                        style: t.bodySmall?.copyWith(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.muted),
            ],
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------- map mode

class _MapMode extends ConsumerWidget {
  const _MapMode({required this.state, required this.bottomInset});

  final SearchState state;
  final double bottomInset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final vm = ref.read(searchViewModelProvider.notifier);
    final results = state.shown;
    final active = state.active;
    final searching = state.status == SearchStatus.searching;

    // The Best option card floats over the map, above the search box (brand board).
    Widget? card;
    final (OffersView? offers, String title) = switch (active) {
      ProductPriced(:final hit) => (
        hit.offers,
        _variantTitle(hit.product, hit.offers.best?.variant),
      ),
      MenuPriced(:final hit) => (
        hit.groups.isEmpty
            ? null
            : hit
                  .groups[state.optionGroup.clamp(0, hit.groups.length - 1)]
                  .offers,
        hit.title,
      ),
      null => (null, ''),
    };
    if (offers?.best != null) {
      final best = offers!.best!;
      card = BestOptionCard(
        title: title,
        store: best.title,
        amount: best.entry.amount,
        amountMax: best.entry.amountMax,
        reasons: offers.reasons,
        caption:
            '${offers.rows.length} ${offers.rows.length == 1 ? 'offer' : 'offers'}',
        onTap: best.place == null
            ? null
            : () => _open(context, Routes.placeDetail(best.place!.id)),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: PriceMapView(
            pins: state.pins,
            bottomInset: bottomInset + (card == null ? 0 : 190),
          ),
        ),
        if (results.priced.length > 1)
          Positioned(
            left: 0,
            right: 0,
            top: 72 + MediaQuery.paddingOf(context).top,
            height: Chrome.minTouch,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              children: [
                for (var i = 0; i < results.priced.length && i < 8; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: Space.sm),
                    child: SelectChip(
                      label: results.priced[i].title,
                      selected: i == state.selected,
                      onTap: () => vm.select(i),
                    ),
                  ),
              ],
            ),
          ),
        if (searching)
          Positioned(
            top: 72 + MediaQuery.paddingOf(context).top,
            left: Space.gutter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: c.glass,
                borderRadius: Radii.pillR,
                border: Border.all(color: c.glassBorder),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.lg,
                  vertical: Space.sm,
                ),
                child: ShimmerText('Searching…', style: t.labelLarge),
              ),
            ),
          ),
        if (card != null)
          Positioned(
            left: Space.md,
            right: Space.md,
            bottom: bottomInset,
            child: card,
          ),
      ],
    );
  }
}

// ---------------------------------------------------------- filters, recents

class _FilterChips extends ConsumerWidget {
  const _FilterChips({required this.filter});

  final SearchFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: Chrome.minTouch,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final f in SearchFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: Space.sm),
              child: SelectChip(
                label: f.label,
                selected: f == filter,
                onTap: () =>
                    ref.read(searchViewModelProvider.notifier).setFilter(f),
              ),
            ),
        ],
      ),
    );
  }
}

class _Recents extends ConsumerWidget {
  const _Recents({
    required this.state,
    required this.padding,
    required this.onPick,
  });

  final SearchState state;
  final EdgeInsets padding;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final vm = ref.read(searchViewModelProvider.notifier);
    return ListView(
      padding: padding,
      children: [
        Row(
          children: [
            Expanded(child: Text('Recent searches', style: t.headlineSmall)),
            TextButton(
              onPressed: () => unawaited(vm.clearRecents()),
              child: const Text('Clear'),
            ),
          ],
        ),
        for (final r in state.recents)
          Semantics(
            container: true,
            button: true,
            label: 'Search $r again',
            excludeSemantics: true,
            child: InkWell(
              borderRadius: Radii.inputR,
              onTap: () => onPick(r),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: Chrome.minTouch),
                child: Row(
                  children: [
                    Icon(Icons.history_rounded, size: 20, color: c.muted),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Text(
                        r,
                        style: t.titleMedium?.copyWith(fontSize: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
