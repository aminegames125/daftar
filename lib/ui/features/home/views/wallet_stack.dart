import 'package:flutter/material.dart';

import '../../../core/motion/daftar_motion.dart';
import '../../../core/motion/squish.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/theme/daftar_typography.dart';
import '../../accounts/views/accounts_card_body.dart';
import '../view_models/card_order.dart';
import '../view_models/home_summary.dart';

extension HomeCardPresentation on HomeCardId {
  String get title => switch (this) {
    HomeCardId.prices => 'Prices',
    HomeCardId.places => 'Places',
    HomeCardId.menus => 'Menus',
    HomeCardId.calculator => 'Calculator',
    HomeCardId.accounts => 'Accounts',
  };

  IconData get icon => switch (this) {
    HomeCardId.prices => Icons.sell_outlined,
    HomeCardId.places => Icons.place_outlined,
    HomeCardId.menus => Icons.menu_book_outlined,
    HomeCardId.calculator => Icons.calculate_outlined,
    HomeCardId.accounts => Icons.account_balance_wallet_outlined,
  };
}

/// Sizes of the wallet.
abstract final class WalletMetrics {
  static const double cardHeight = 164;
  static const double peek = 40;

  static double stackHeight(int cards) => cardHeight + peek * (cards - 1);
}

/// The stack of wallet cards: [order] first is the front card, the others peek out
/// 40 px above it. On first show the back cards fan up from behind the front one
///.
class WalletStack extends StatefulWidget {
  const WalletStack({
    super.key,
    required this.order,
    required this.summary,
    required this.onOpen,
  });

  final List<HomeCardId> order;

  /// null while loading.
  final HomeSummary? summary;
  final ValueChanged<HomeCardId> onOpen;

  @override
  State<WalletStack> createState() => _WalletStackState();
}

class _WalletStackState extends State<WalletStack>
    with SingleTickerProviderStateMixin {
  static final SpringCurve _spring = SpringCurve(DaftarMotion.bouncy);

  /// Delay between two cards of the fan, as a fraction of the animation.
  static const double _stagger = 0.12;

  late final AnimationController _fan = AnimationController(
    vsync: this,
    duration: DaftarMotion.write,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (DaftarMotion.reduced(context)) {
      _fan.value = 1;
    } else {
      _fan.forward();
    }
  }

  @override
  void dispose() {
    _fan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.order.length;
    final frontTop = WalletMetrics.peek * (n - 1);

    return AnimatedBuilder(
      animation: _fan,
      builder: (context, _) {
        return SizedBox(
          height: WalletMetrics.stackHeight(n),
          child: Stack(
            children: [
              // Back to front, so the front card is painted (and hit-tested) last.
              for (var i = n - 1; i >= 0; i--)
                Builder(
                  builder: (context) {
                    final finalTop = WalletMetrics.peek * (n - 1 - i);
                    final local = i == 0 ? 1.0 : _localT(i, n);
                    final progress = i == 0 ? 1.0 : _spring.transform(local);
                    return Positioned(
                      left: 0,
                      right: 0,
                      top: frontTop + (finalTop - frontTop) * progress,
                      height: WalletMetrics.cardHeight,
                      child: Opacity(
                        opacity: local,
                        child: WalletCard(
                          id: widget.order[i],
                          summary: widget.summary,
                          position: i,
                          total: n,
                          onTap: () => widget.onOpen(widget.order[i]),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  /// Local 0..1 progress of the card at [index] (1 = next to the front card).
  double _localT(int index, int total) {
    final start = (index - 1) * _stagger;
    return ((_fan.value - start) / (1 - (total - 2) * _stagger)).clamp(
      0.0,
      1.0,
    );
  }
}

/// One wallet card. [position] 0 is the front.
class WalletCard extends StatelessWidget {
  const WalletCard({
    super.key,
    required this.id,
    required this.summary,
    required this.position,
    required this.total,
    required this.onTap,
  });

  final HomeCardId id;
  final HomeSummary? summary;
  final int position;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final isPrices = id == HomeCardId.prices;
    final depth = total <= 1
        ? 1.0
        : 1 - position / (total - 1); // 1 front … 0 back
    final background = isPrices
        ? c.lime
        : Color.lerp(c.surface, c.raised, depth)!;
    final foreground = isPrices ? c.onLime : c.text;
    final secondary = isPrices ? c.onLime.withValues(alpha: 0.7) : c.muted;

    return Semantics(
      button: true,
      label:
          '${id.title}, ${_countText(summary, id) ?? (id.isSoon ? 'coming soon' : '')}',
      excludeSemantics: true,
      onTap: onTap,
      child: Squish(
        onTap: onTap,
        pressedScale: 0.98,
        // The card has a fixed height, so its text may grow only so far.
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.2,
          child: Container(
            padding: const EdgeInsets.fromLTRB(
              Space.xl,
              Space.md,
              Space.xl,
              Space.lg,
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius: Radii.cardR,
              border: isPrices ? null : Border.all(color: c.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: WalletMetrics.peek - Space.xl,
                  child: Row(
                    children: [
                      Icon(
                        id.icon,
                        size: 20,
                        color: isPrices ? foreground : secondary,
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: Text(
                          id.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleMedium?.copyWith(
                            color: isPrices
                                ? foreground
                                : (id.isSoon ? secondary : foreground),
                            fontWeight: isPrices
                                ? FontWeight.w800
                                : FontWeight.w700,
                          ),
                        ),
                      ),
                      if (id.isSoon)
                        _SoonChip(color: secondary)
                      else if (_countText(summary, id) case final count?)
                        Text(
                          count,
                          style: t.bodySmall?.copyWith(
                            color: secondary,
                            fontFeatures: DaftarType.tabular,
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  // Shrinks the body (never clips it) if big text needs more room.
                  child: LayoutBuilder(
                    builder: (context, box) => FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.bottomLeft,
                      child: SizedBox(
                        width: box.maxWidth,
                        child: _Body(
                          id: id,
                          summary: summary,
                          foreground: foreground,
                          secondary: secondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String? _countText(HomeSummary? s, HomeCardId id) {
    if (s == null) return null;
    return switch (id) {
      HomeCardId.prices => '${s.priceCount} logged',
      HomeCardId.places => '${s.placeCount} saved',
      HomeCardId.menus =>
        s.menuPlaceCount == 1 ? '1 place' : '${s.menuPlaceCount} places',
      _ => null,
    };
  }
}

class _SoonChip extends StatelessWidget {
  const _SoonChip({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: c.line),
        borderRadius: Radii.pillR,
      ),
      child: Text(
        'Soon',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
      ),
    );
  }
}

/// Lower part of a card (only the front card shows it fully).
class _Body extends StatelessWidget {
  const _Body({
    required this.id,
    required this.summary,
    required this.foreground,
    required this.secondary,
  });

  final HomeCardId id;
  final HomeSummary? summary;
  final Color foreground;
  final Color secondary;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = summary;

    switch (id) {
      case HomeCardId.prices:
        final latest = s?.latest;
        if (s == null) return const SizedBox.shrink();
        if (latest == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nothing logged yet',
                style: t.bodySmall?.copyWith(color: secondary),
              ),
              const SizedBox(height: Space.xs),
              Text(
                'Tap + to log your first price',
                style: t.titleLarge?.copyWith(color: foreground),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Latest · ${latest.title} · ${latest.where}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.bodySmall?.copyWith(color: secondary),
            ),
            const SizedBox(height: Space.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      latest.amountText,
                      style: DaftarType.price(40, foreground),
                    ),
                  ),
                ),
                const SizedBox(width: Space.sm - 2),
                Text(
                  latest.amount.currency.code,
                  style: t.labelLarge?.copyWith(color: foreground),
                ),
              ],
            ),
          ],
        );
      case HomeCardId.places:
        return _CountBody(
          count: s?.placeCount,
          caption: 'places saved',
          foreground: foreground,
          secondary: secondary,
        );
      case HomeCardId.menus:
        return _CountBody(
          count: s?.menuPlaceCount,
          caption: 'places with a menu',
          foreground: foreground,
          secondary: secondary,
        );
      case HomeCardId.accounts:
        return AccountsCardBody(foreground: foreground, secondary: secondary);
      case HomeCardId.calculator:
        return Text(
          'Arrives in a later update',
          style: t.bodySmall?.copyWith(color: secondary),
        );
    }
  }
}

class _CountBody extends StatelessWidget {
  const _CountBody({
    required this.count,
    required this.caption,
    required this.foreground,
    required this.secondary,
  });

  final int? count;
  final String caption;
  final Color foreground;
  final Color secondary;

  @override
  Widget build(BuildContext context) {
    if (count == null) return const SizedBox.shrink();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text('$count', style: DaftarType.price(40, foreground)),
        const SizedBox(width: Space.sm),
        Flexible(
          child: Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: secondary),
          ),
        ),
      ],
    );
  }
}

/// Edit mode of the wallet: the stack opens into a list; hold a card
/// and drag it to reorder. The first row becomes the front card.
class WalletReorderList extends StatelessWidget {
  const WalletReorderList({
    super.key,
    required this.order,
    required this.onReorder,
  });

  final List<HomeCardId> order;
  final void Function(int oldIndex, int newIndex) onReorder;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return ReorderableListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      onReorderItem: onReorder,
      proxyDecorator: (child, index, animation) => AnimatedBuilder(
        animation: animation,
        builder: (context, child) => Transform.scale(
          scale: 1 + 0.03 * animation.value,
          child: Material(type: MaterialType.transparency, child: child),
        ),
        child: child,
      ),
      children: [
        for (var i = 0; i < order.length; i++)
          Padding(
            key: ValueKey(order[i]),
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: ReorderableDelayedDragStartListener(
              index: i,
              child: Container(
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                decoration: BoxDecoration(
                  color: order[i] == HomeCardId.prices ? c.lime : c.surface,
                  borderRadius: Radii.cardR,
                  border: order[i] == HomeCardId.prices
                      ? null
                      : Border.all(color: c.line),
                ),
                child: Row(
                  children: [
                    Icon(
                      order[i].icon,
                      size: 20,
                      color: order[i] == HomeCardId.prices ? c.onLime : c.muted,
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Text(
                        order[i].title,
                        style: t.titleMedium?.copyWith(
                          color: order[i] == HomeCardId.prices
                              ? c.onLime
                              : c.text,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (order[i].isSoon) ...[
                      _SoonChip(color: c.muted),
                      const SizedBox(width: Space.md),
                    ],
                    Semantics(
                      label: 'Hold and drag to move ${order[i].title}',
                      child: Icon(
                        Icons.drag_indicator_rounded,
                        color: order[i] == HomeCardId.prices
                            ? c.onLime
                            : c.muted,
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
