import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/money.dart';
import '../../../../domain/use_cases/basket_optimizer.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/theme/daftar_typography.dart';
import '../../../core/widgets/empty_state.dart';
import '../view_models/best_store_view_model.dart';
import '../view_models/calculator_providers.dart';

/// Best store mode: prices the basket at every place and shows the winner (lime),
/// the runner-ups, and the optional cheapest split.
class BestStoreMode extends ConsumerWidget {
  const BestStoreMode({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final basket = ref.watch(basketProvider);
    if (basket.isEmpty) {
      return const _Message(
        'Your basket is empty.\nAdd items in Basket mode to compare stores.',
      );
    }
    final state = ref.watch(bestStoreProvider);
    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) =>
          const _Message('Could not read your prices.\nTry again in a moment.'),
      data: (s) => _Body(state: s),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(child: EmptyState(message: text)),
  );
}

class _Body extends StatelessWidget {
  const _Body({required this.state});
  final BestStoreState state;

  @override
  Widget build(BuildContext context) {
    final opt = state.optimization;
    final best = opt.best;
    if (best == null) {
      return _Message(
        state.skippedCount > 0 && state.itemNames.isEmpty
            ? 'Your items were typed by hand, so there are no prices to compare.\nPick items from your catalog in Basket mode.'
            : 'No place has a price for these items yet.\nLog some prices first.',
      );
    }
    final split = opt.split;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.sm,
        Space.gutter,
        Chrome.contentBottomPadding,
      ),
      children: [
        _WinnerCard(state: state, store: best),
        if (state.skippedCount > 0) ...[
          const SizedBox(height: Space.md),
          _Note(
            icon: Icons.edit_note_rounded,
            text: state.skippedCount == 1
                ? '1 hand-typed item is not compared (it has no catalog prices).'
                : '${state.skippedCount} hand-typed items are not compared (they have no catalog prices).',
          ),
        ],
        if (opt.stores.length > 1) ...[
          const SizedBox(height: Space.lg),
          const _SectionTitle('Other stores'),
          for (final s in opt.stores.skip(1)) ...[
            const SizedBox(height: Space.sm),
            _RunnerUp(state: state, store: s, best: best),
          ],
        ],
        if (split != null && split.storesUsed > 1) ...[
          const SizedBox(height: Space.lg),
          _SplitCard(state: state, split: split),
        ],
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.titleSmall
        ?.copyWith(color: context.colors.muted),
  );
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: c.muted),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}

/// A price with its currency, shrinking instead of overflowing.
class _Amount extends StatelessWidget {
  const _Amount(this.money, {required this.size, required this.color});
  final Money money;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    alignment: Alignment.centerRight,
    child: Text(
      money.formatWithCode(),
      maxLines: 1,
      style: DaftarType.price(size, color).copyWith(letterSpacing: 0),
    ),
  );
}

class _WinnerCard extends StatelessWidget {
  const _WinnerCard({required this.state, required this.store});
  final BestStoreState state;
  final StoreBasket store;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final name = state.placeName(store.placeId);
    return Semantics(
      container: true,
      label:
          'Best store: $name, ${store.total.formatWithCode()}. '
          '${store.reasons.map(describeReason).join('. ')}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(color: c.lime, borderRadius: Radii.cardR),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.emoji_events_outlined, size: 18, color: c.onLime),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    'Best store',
                    style: t.labelLarge?.copyWith(color: c.onLime),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.sm),
            Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.headlineSmall?.copyWith(color: c.onLime),
            ),
            const SizedBox(height: Space.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: _Amount(store.total, size: 32, color: c.onLime),
            ),
            const SizedBox(height: Space.md),
            for (final r in store.reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      isWarningReason(r)
                          ? Icons.warning_amber_rounded
                          : Icons.check_rounded,
                      size: 18,
                      color: c.onLime,
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(
                        describeReason(r),
                        style: t.bodyMedium?.copyWith(color: c.onLime),
                      ),
                    ),
                  ],
                ),
              ),
            if (store.missingKeys.isNotEmpty)
              _ItemFlag(
                label: 'No price here',
                names: [for (final k in store.missingKeys) state.itemName(k)],
                color: c.onLime,
              ),
            if (store.staleKeys.isNotEmpty)
              _ItemFlag(
                label: 'Old price',
                names: [for (final k in store.staleKeys) state.itemName(k)],
                color: c.onLime,
              ),
          ],
        ),
      ),
    );
  }
}

/// "No price here: Milk, Bread" in one wrapping line.
class _ItemFlag extends StatelessWidget {
  const _ItemFlag({
    required this.label,
    required this.names,
    required this.color,
  });
  final String label;
  final List<String> names;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: Space.xs),
    child: Text(
      '$label: ${names.join(', ')}',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
    ),
  );
}

class _RunnerUp extends StatelessWidget {
  const _RunnerUp({
    required this.state,
    required this.store,
    required this.best,
  });
  final BestStoreState state;
  final StoreBasket store;
  final StoreBasket best;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final comparable = store.coveredCount == best.coveredCount;
    final extra = store.total - best.total;
    final lines = <String>[
      if (comparable && extra.minor > 0)
        '${extra.formatWithCode()} more than ${state.placeName(best.placeId)}'
      else if (comparable)
        'Same total as ${state.placeName(best.placeId)}'
      else
        'Prices ${store.coveredCount} of ${store.totalLines} items, '
            'so the total is not comparable',
    ];
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: Radii.cardR,
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  state.placeName(store.placeId),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: t.titleMedium,
                ),
              ),
              const SizedBox(width: Space.sm),
              Flexible(child: _Amount(store.total, size: 18, color: c.text)),
            ],
          ),
          const SizedBox(height: Space.xs),
          for (final l in lines) Text(l, style: t.bodySmall),
          if (store.missingKeys.isNotEmpty)
            _Flag(
              icon: Icons.remove_circle_outline_rounded,
              text: store.missingKeys.length == 1
                  ? 'Missing: ${state.itemName(store.missingKeys.first)}'
                  : 'Missing ${store.missingKeys.length} items: '
                        '${store.missingKeys.map(state.itemName).join(', ')}',
            ),
          if (store.staleKeys.isNotEmpty)
            _Flag(
              icon: Icons.history_toggle_off_rounded,
              text: store.staleKeys.length == 1
                  ? 'Old price: ${state.itemName(store.staleKeys.first)}'
                  : 'Old prices: ${store.staleKeys.map(state.itemName).join(', ')}',
            ),
        ],
      ),
    );
  }
}

class _Flag extends StatelessWidget {
  const _Flag({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: c.amber),
          const SizedBox(width: Space.xs),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: c.amber),
            ),
          ),
        ],
      ),
    );
  }
}

class _SplitCard extends StatelessWidget {
  const _SplitCard({required this.state, required this.split});
  final BestStoreState state;
  final CheapestSplit split;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final worth = split.isWorthIt;
    final saving = split.savingVersusBest;
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
          Row(
            children: [
              Icon(Icons.call_split_rounded, size: 18, color: c.muted),
              const SizedBox(width: Space.sm),
              Expanded(child: Text('Cheapest split', style: t.titleMedium)),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            'Buy each item where it costs least, across '
            '${split.storesUsed} stores.',
            style: t.bodySmall,
          ),
          for (final entry in split.perStore.entries) ...[
            const SizedBox(height: Space.md),
            Row(
              children: [
                Expanded(
                  child: Text(
                    state.placeName(entry.key),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.titleSmall,
                  ),
                ),
                const SizedBox(width: Space.sm),
                Flexible(child: _Amount(entry.value, size: 16, color: c.text)),
              ],
            ),
            for (final a in split.assignments.where(
              (a) => a.placeId == entry.key,
            ))
              Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        state.itemName(a.key),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall,
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Text(
                      a.lineTotal.format(),
                      style: t.bodySmall?.copyWith(
                        fontFeatures: DaftarType.tabular,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: Space.md),
          Divider(height: 1, color: c.line),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(child: Text('Split total', style: t.titleSmall)),
              const SizedBox(width: Space.sm),
              Flexible(child: _Amount(split.total, size: 18, color: c.text)),
            ],
          ),
          if (saving != null && saving.minor > 0) ...[
            const SizedBox(height: Space.xs),
            Text(
              'Extra saving: ${saving.formatWithCode()} versus the best single store',
              style: t.bodyMedium?.copyWith(color: worth ? c.text : c.muted),
            ),
          ],
          for (final r in split.reasons.whereType<NotWorthSecondTripReason>())
            Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                describeReason(r),
                style: t.bodySmall?.copyWith(color: c.amber),
              ),
            ),
          if (split.unpricedKeys.isNotEmpty)
            _Flag(
              icon: Icons.remove_circle_outline_rounded,
              text:
                  'No store has a price for '
                  '${split.unpricedKeys.map(state.itemName).join(', ')}',
            ),
        ],
      ),
    );
  }
}
