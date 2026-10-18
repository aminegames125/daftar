import '../models/money.dart';

/// How final shares are rounded.
enum RoundingPolicy {
  /// Exact millimes.
  exact(1),

  /// Everyone pays a multiple of 0.050 TND (cash); the remainder person pays
  /// whatever is left so the total is still exact.
  cash050(50);

  const RoundingPolicy(this.step);

  /// Step in minor units.
  final int step;
}

/// A shared item in by-item mode.
class SplitItem {
  const SplitItem({
    required this.id,
    required this.price,
    required this.ownerIds,
    this.name,
  });
  final String id;
  final String? name;
  final Money price;

  /// People sharing this item (equal split among them). Must not be empty.
  final List<String> ownerIds;
}

class SplitResult {
  const SplitResult({
    required this.shares,
    required this.total,
    required this.remainderPersonId,
  });

  /// Person id -> amount owed, in participant order. Sums exactly to [total].
  final Map<String, Money> shares;
  final Money total;

  /// Who absorbed the rounding remainder (only meaningful for cash rounding).
  final String remainderPersonId;

  Money get sum =>
      Money(shares.values.fold<int>(0, (a, b) => a + b.minor), total.currency);
}

/// Splits a bill. Shares always sum exactly to the total.
class BillSplitter {
  const BillSplitter();

  /// Equal split among [personIds]. Leftover millimes go one each to the first
  /// people in order. With [RoundingPolicy.cash050] each person except
  /// [remainderPersonId] (default: the first) pays a multiple of 0.050.
  SplitResult splitEqually({
    required Money total,
    required List<String> personIds,
    RoundingPolicy policy = RoundingPolicy.exact,
    String? remainderPersonId,
  }) {
    _check(total, personIds);
    final shares = _even(total.minor, personIds.length);
    return _finish(total, personIds, shares, policy, remainderPersonId);
  }

  /// By-item split. Each item is shared equally by its owners; [tax] and [tip]
  /// (amounts, not percentages: see [percentOf]) are shared in proportion to
  /// each person's item subtotal. The total is items + tax + tip.
  SplitResult splitByItem({
    required List<String> personIds,
    required List<SplitItem> items,
    Money? tax,
    Money? tip,
    RoundingPolicy policy = RoundingPolicy.exact,
    String? remainderPersonId,
  }) {
    final currency = items.isNotEmpty
        ? items.first.price.currency
        : (tax ?? tip ?? Money.zeroTnd).currency;
    final index = {for (var i = 0; i < personIds.length; i++) personIds[i]: i};
    if (personIds.isEmpty || index.length != personIds.length) {
      throw ArgumentError('personIds must be non-empty and unique');
    }
    final sub = List<int>.filled(personIds.length, 0);
    var itemsTotal = 0;
    for (final item in items) {
      if (item.price.currency != currency) {
        throw ArgumentError('Currency mismatch in items');
      }
      if (item.price.minor < 0) throw ArgumentError('Negative item ${item.id}');
      if (item.ownerIds.isEmpty) {
        throw ArgumentError('Item ${item.id} has no owner');
      }
      for (final o in item.ownerIds) {
        _idx(index, o);
      }
      final owners = item.ownerIds.toSet().toList()
        ..sort((a, b) => _idx(index, a).compareTo(_idx(index, b)));
      final part = _even(item.price.minor, owners.length);
      for (var k = 0; k < owners.length; k++) {
        sub[index[owners[k]]!] += part[k];
      }
      itemsTotal += item.price.minor;
    }
    final shares = List<int>.from(sub);
    var total = itemsTotal;
    for (final extra in [tax, tip]) {
      if (extra == null) continue;
      if (extra.currency != currency) throw ArgumentError('Currency mismatch');
      if (extra.minor < 0) throw ArgumentError('Negative tax/tip');
      final alloc = itemsTotal == 0
          ? _even(extra.minor, personIds.length)
          : _proportional(extra.minor, sub);
      for (var i = 0; i < shares.length; i++) {
        shares[i] += alloc[i];
      }
      total += extra.minor;
    }
    return _finish(
      Money(total, currency),
      personIds,
      shares,
      policy,
      remainderPersonId,
    );
  }

  /// [basisPoints] of [base] (1000 = 10%), rounded half up.
  static Money percentOf(Money base, int basisPoints) {
    final q = (base.minor.abs() * basisPoints + 5000) ~/ 10000;
    return Money(base.minor < 0 ? -q : q, base.currency);
  }

  int _idx(Map<String, int> index, String id) {
    final i = index[id];
    if (i == null) throw ArgumentError('Unknown person: $id');
    return i;
  }

  void _check(Money total, List<String> ids) {
    if (total.minor < 0) throw ArgumentError('Negative total');
    if (ids.isEmpty) throw ArgumentError('Need at least one person');
    if (ids.toSet().length != ids.length) {
      throw ArgumentError('Duplicate person ids');
    }
  }

  /// [amount] split into [n] parts, leftover one each to the first parts.
  List<int> _even(int amount, int n) {
    final base = amount ~/ n;
    final rem = amount % n;
    return [for (var i = 0; i < n; i++) base + (i < rem ? 1 : 0)];
  }

  /// Largest-remainder allocation of [amount] by [weights] (all >= 0, sum > 0).
  /// Ties go to the earlier person.
  List<int> _proportional(int amount, List<int> weights) {
    final sum = weights.fold<int>(0, (a, b) => a + b);
    final big = BigInt.from(amount);
    final bigSum = BigInt.from(sum);
    final out = <int>[];
    final fracs = <BigInt>[];
    for (final w in weights) {
      final num = big * BigInt.from(w);
      out.add((num ~/ bigSum).toInt());
      fracs.add(num % bigSum);
    }
    var left = amount - out.fold<int>(0, (a, b) => a + b);
    final order = List<int>.generate(weights.length, (i) => i)
      ..sort((a, b) {
        final c = fracs[b].compareTo(fracs[a]);
        return c != 0 ? c : a.compareTo(b);
      });
    for (final i in order) {
      if (left == 0) break;
      out[i]++;
      left--;
    }
    return out;
  }

  SplitResult _finish(
    Money total,
    List<String> ids,
    List<int> shares,
    RoundingPolicy policy,
    String? remainderId,
  ) {
    final rIdx = remainderId == null ? 0 : ids.indexOf(remainderId);
    if (rIdx < 0) throw ArgumentError('Unknown remainder person: $remainderId');
    var result = shares;
    if (policy.step > 1) {
      result = _cash(total.minor, shares, rIdx, policy.step, up: true);
      if (result[rIdx] < 0) {
        result = _cash(total.minor, shares, rIdx, policy.step, up: false);
      }
    }
    return SplitResult(
      shares: Map.unmodifiable({
        for (var i = 0; i < ids.length; i++)
          ids[i]: Money(result[i], total.currency),
      }),
      total: total,
      remainderPersonId: ids[rIdx],
    );
  }

  List<int> _cash(
    int total,
    List<int> shares,
    int rIdx,
    int step, {
    required bool up,
  }) {
    final out = List<int>.from(shares);
    var others = 0;
    for (var i = 0; i < out.length; i++) {
      if (i == rIdx) continue;
      out[i] = up
          ? ((shares[i] + step ~/ 2) ~/ step) * step
          : (shares[i] ~/ step) * step;
      others += out[i];
    }
    out[rIdx] = total - others;
    return out;
  }
}
