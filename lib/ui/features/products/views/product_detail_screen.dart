import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/routes/prices_routes.dart';
import '../../../../domain/models/product.dart';
import '../../../../domain/use_cases/relative_time.dart';
import '../../../../domain/use_cases/unit_price.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/collapsing_header.dart';
import '../../../core/widgets/daftar_action_bar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/floating_toast.dart';
import '../../../core/widgets/skeleton.dart';
import '../../places/views/stored_image.dart';
import '../view_models/directions.dart';
import '../view_models/product_detail_view_model.dart';
import 'offer_widgets.dart';
import 'price_history_chart.dart';
import 'price_widgets.dart';
import 'select_chip.dart';

/// A product: its current offers (best first), price history chart and list.
/// Detail pages show the floating action toolbar, never the nav (D7).
class ProductDetailScreen extends ConsumerStatefulWidget {
  const ProductDetailScreen({
    super.key,
    required this.productId,
    this.variantId,
  });

  final String productId;
  final String? variantId;

  @override
  ConsumerState<ProductDetailScreen> createState() =>
      _ProductDetailScreenState();
}

class _ProductDetailScreenState extends ConsumerState<ProductDetailScreen> {
  String? _variantId;

  @override
  void initState() {
    super.initState();
    _variantId = widget.variantId;
  }

  void _back() => context.canPop() ? context.pop() : context.go(Routes.home);

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(
      productDetailProvider((
        productId: widget.productId,
        variantId: _variantId,
      )),
    );
    return Scaffold(
      extendBody: true,
      body: detail.when(
        loading: () => const _Loading(),
        error: (_, _) => EmptyState(
          message: 'Could not load this product.',
          actionLabel: 'Back',
          onAction: _back,
        ),
        data: (d) => d == null
            ? EmptyState(
                message: 'This product is gone.',
                actionLabel: 'Back',
                onAction: _back,
              )
            : _Body(
                detail: d,
                onBack: _back,
                onVariant: (id) => setState(() => _variantId = id),
              ),
      ),
      bottomNavigationBar: detail.value == null
          ? null
          : _toolbar(detail.value!),
    );
  }

  Widget _toolbar(ProductDetail d) {
    final best = d.offers.best;
    final place = best?.place;
    return DaftarActionBar(
      actions: [
        ToolbarAction(
          icon: Icons.directions_outlined,
          label: 'Directions to the best place',
          onTap: place != null && place.hasLocation
              ? () async {
                  if (!await openDirections(place) && mounted) {
                    FloatingToast.show(
                      context,
                      'No maps app found',
                      kind: ToastKind.error,
                    );
                  }
                }
              : null,
        ),
      ],
      primary: ToolbarAction(
        icon: Icons.add_rounded,
        label: 'Log price',
        onTap: () => context.push(
          logPriceLocation(productId: d.product.id, variantId: d.variant.id),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const SafeArea(
    child: Padding(
      padding: EdgeInsets.all(Space.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Skeleton(width: 180, height: 28),
          SizedBox(height: Space.xl),
          Skeleton(height: 150, radius: Radii.card),
          SizedBox(height: Space.xl),
          Expanded(child: SkeletonList()),
        ],
      ),
    ),
  );
}

class _Body extends StatelessWidget {
  const _Body({
    required this.detail,
    required this.onBack,
    required this.onVariant,
  });

  final ProductDetail detail;
  final VoidCallback onBack;
  final ValueChanged<String> onVariant;

  String _variantLabel(Variant v) {
    final size = v.sizeValue != null && v.sizeUnit != null
        ? formatSize(v.sizeValue!, v.sizeUnit!)
        : null;
    final name = v.name ?? (size == null ? 'Standard' : null);
    return [?name, ?size].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final d = detail;
    final product = d.product;
    final best = d.offers.best;
    final others = d.offers.rows.skip(1).toList();
    final photo = product.photoPath;

    void openPlace(String? id) {
      if (id != null) context.push(Routes.placeDetail(id));
    }

    final subtitle = [
      ?product.brand,
      if (d.offers.rows.isNotEmpty)
        '${d.offers.rows.length} ${d.offers.rows.length == 1 ? 'offer' : 'offers'}',
    ].join(' · ');

    return CustomScrollView(
      slivers: [
        CollapsingHeader(
          title: product.name,
          subtitle: subtitle.isEmpty ? null : subtitle,
          leading: HeaderIconButton(
            icon: Icons.arrow_back_rounded,
            label: 'Back',
            onTap: onBack,
          ),
          background: photo == null ? null : StoredImage(path: photo),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            Space.gutter,
            Space.lg,
            Space.gutter,
            Chrome.contentBottomPadding,
          ),
          sliver: SliverList.list(
            children: [
              if (product.variants.length > 1) ...[
                Wrap(
                  spacing: Space.sm,
                  children: [
                    for (final v in product.variants)
                      SelectChip(
                        label: _variantLabel(v),
                        selected: v.id == d.variant.id,
                        onTap: () => onVariant(v.id),
                      ),
                  ],
                ),
                const SizedBox(height: Space.lg),
              ],
              if (best == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.xxxl),
                  child: EmptyState(
                    message: 'No prices yet. Log the first one.',
                    actionLabel: 'Log price',
                    onAction: () => context.push(
                      logPriceLocation(
                        productId: product.id,
                        variantId: d.variant.id,
                      ),
                    ),
                  ),
                )
              else ...[
                BestOptionCard(
                  title: [
                    product.name,
                    if (d.variant.name != null) d.variant.name!,
                    if (d.variant.sizeValue != null)
                      formatSize(d.variant.sizeValue!, d.variant.sizeUnit!),
                  ].join(' · '),
                  store: best.title,
                  amount: best.entry.amount,
                  amountMax: best.entry.amountMax,
                  reasons: d.offers.reasons,
                  caption:
                      '${d.offers.rows.length} ${d.offers.rows.length == 1 ? 'offer' : 'offers'}',
                  unitLabel: best.unitPrice == null
                      ? null
                      : '${best.unitPrice!.formatWithCode()} ${d.offers.basis.unitLabel}',
                  onTap: best.place == null
                      ? null
                      : () => openPlace(best.entry.placeId),
                ),
                if (best.change != null || best.isStale) ...[
                  const SizedBox(height: Space.sm),
                  Row(
                    children: [
                      if (best.change != null)
                        PriceChangeLabel(change: best.change!, now: d.now),
                      if (best.isStale)
                        Padding(
                          padding: const EdgeInsets.only(left: Space.sm),
                          child: Text('old price', style: t.bodySmall),
                        ),
                    ],
                  ),
                ],
                if (others.isNotEmpty) ...[
                  const SizedBox(height: Space.xxl),
                  Text('Other offers', style: t.headlineSmall),
                  const SizedBox(height: Space.sm),
                  for (var i = 0; i < others.length; i++) ...[
                    if (i > 0) Divider(color: c.surface, height: 1),
                    OfferTile(
                      row: others[i],
                      now: d.now,
                      onTap: others[i].place == null
                          ? null
                          : () => openPlace(others[i].entry.placeId),
                    ),
                  ],
                ],
                const SizedBox(height: Space.xxl),
                Text('Price history', style: t.headlineSmall),
                const SizedBox(height: Space.md),
                PriceHistoryChart(series: d.series),
                const SizedBox(height: Space.xxl),
                Text('All prices', style: t.headlineSmall),
                const SizedBox(height: Space.sm),
                for (final row in d.history) _HistoryTile(row: row, now: d.now),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.row, required this.now});

  final HistoryRow row;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final e = row.entry;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.surface)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    row.title,
                    style: t.titleMedium?.copyWith(fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${shortDate(e.seenAt, now)} · ${relativeAge(e.seenAt, now)}${e.isPromo ? ' · promo' : ''}',
                    style: t.bodySmall?.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                PriceAmount(
                  amount: e.amount,
                  amountMax: e.amountMax,
                  size: 16,
                  showCode: false,
                ),
                if (row.change != null)
                  PriceChangeLabel(change: row.change!, now: now),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
