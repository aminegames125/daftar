import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/basket.dart';
import '../../../../domain/models/money.dart';
import '../../../../domain/use_cases/bill_splitter.dart';

enum SplitStyle { equal, byItem }

/// Where the amount to split comes from.
enum SplitSource { basket, typed }

const Object _keep = Object();

class SplitState {
  const SplitState({
    this.people = 2,
    this.style = SplitStyle.equal,
    this.source = SplitSource.basket,
    this.typedAmount,
    this.cashRounding = false,
    this.remainderIndex = 0,
    this.owners = const {},
    this.tax,
    this.tip,
  });

  static const minPeople = 2;
  static const maxPeople = 20;

  final int people;
  final SplitStyle style;
  final SplitSource source;
  final Money? typedAmount;
  final bool cashRounding;

  /// Index (0-based) of the person who absorbs the remainder.
  final int remainderIndex;

  /// Basket item id -> person indexes sharing it. Empty = everyone.
  final Map<String, Set<int>> owners;
  final Money? tax;
  final Money? tip;

  List<String> get personIds => [for (var i = 0; i < people; i++) 'p$i'];

  static String personName(int i) => 'Person ${i + 1}';

  SplitState copyWith({
    int? people,
    SplitStyle? style,
    SplitSource? source,
    Object? typedAmount = _keep,
    bool? cashRounding,
    int? remainderIndex,
    Map<String, Set<int>>? owners,
    Object? tax = _keep,
    Object? tip = _keep,
  }) {
    final n = people ?? this.people;
    return SplitState(
      people: n,
      style: style ?? this.style,
      source: source ?? this.source,
      typedAmount: identical(typedAmount, _keep)
          ? this.typedAmount
          : typedAmount as Money?,
      cashRounding: cashRounding ?? this.cashRounding,
      remainderIndex: (remainderIndex ?? this.remainderIndex).clamp(0, n - 1),
      owners: owners ?? this.owners,
      tax: identical(tax, _keep) ? this.tax : tax as Money?,
      tip: identical(tip, _keep) ? this.tip : tip as Money?,
    );
  }
}

/// The outcome of a split, or why there is none yet.
class SplitOutcome {
  const SplitOutcome({this.result, this.hint});
  final SplitResult? result;
  final String? hint;
}

/// Effective owners of an item: the chosen people, or everyone when none chosen.
List<int> effectiveOwners(SplitState s, String itemId) {
  final chosen = [
    for (final i in s.owners[itemId] ?? const <int>{})
      if (i < s.people) i,
  ]..sort();
  return chosen.isEmpty ? [for (var i = 0; i < s.people; i++) i] : chosen;
}

/// Pure: runs [BillSplitter] for [state] over [basket].
SplitOutcome computeSplit(SplitState state, Basket basket) {
  const splitter = BillSplitter();
  final policy = state.cashRounding
      ? RoundingPolicy.cash050
      : RoundingPolicy.exact;
  final ids = state.personIds;
  final remainder = ids[state.remainderIndex];
  if (state.style == SplitStyle.byItem) {
    if (basket.isEmpty) {
      return const SplitOutcome(
        hint: 'Add items in Basket mode to split by item.',
      );
    }
    final items = [
      for (final item in basket.items)
        SplitItem(
          id: item.id,
          name: item.name,
          price: item.lineTotal,
          ownerIds: [for (final i in effectiveOwners(state, item.id)) 'p$i'],
        ),
    ];
    return SplitOutcome(
      result: splitter.splitByItem(
        personIds: ids,
        items: items,
        tax: state.tax,
        tip: state.tip,
        policy: policy,
        remainderPersonId: remainder,
      ),
    );
  }
  final total = state.source == SplitSource.basket
      ? (basket.isEmpty ? null : basket.total)
      : state.typedAmount;
  if (total == null || total.minor <= 0) {
    return SplitOutcome(
      hint: state.source == SplitSource.basket
          ? 'Your basket is empty. Add items or type an amount.'
          : 'Type the amount to split.',
    );
  }
  return SplitOutcome(
    result: splitter.splitEqually(
      total: total,
      personIds: ids,
      policy: policy,
      remainderPersonId: remainder,
    ),
  );
}

class SplitNotifier extends Notifier<SplitState> {
  @override
  SplitState build() => const SplitState();

  void setPeople(int n) => state = state.copyWith(
    people: n.clamp(SplitState.minPeople, SplitState.maxPeople),
  );

  void setStyle(SplitStyle s) => state = state.copyWith(style: s);
  void setSource(SplitSource s) => state = state.copyWith(source: s);
  void setTyped(Money? m) => state = state.copyWith(typedAmount: m);
  void setCashRounding(bool v) => state = state.copyWith(cashRounding: v);
  void setRemainder(int i) => state = state.copyWith(remainderIndex: i);
  void setTax(Money? m) => state = state.copyWith(tax: m);
  void setTip(Money? m) => state = state.copyWith(tip: m);

  /// Adds or removes [person] from an item's owners.
  void toggleOwner(String itemId, int person) {
    final set = {...(state.owners[itemId] ?? const <int>{})};
    if (!set.remove(person)) set.add(person);
    state = state.copyWith(owners: {...state.owners, itemId: set});
  }

  /// Back to "everyone shares it".
  void shareWithAll(String itemId) =>
      state = state.copyWith(owners: {...state.owners, itemId: <int>{}});
}

final splitProvider = NotifierProvider<SplitNotifier, SplitState>(
  SplitNotifier.new,
);
