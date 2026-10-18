import 'package:drift/drift.dart';

import '../../domain/models/money.dart';
import '../../domain/models/price_entry.dart';
import '../../domain/use_cases/current_offers.dart';
import '../services/database/app_database.dart';
import 'repository_support.dart';

abstract interface class PricesRepository {
  /// Every logged price of a product variant, newest first (history + charts).
  Stream<List<PriceEntry>> watchHistoryForVariant(String variantId);

  /// Every logged price of a menu option, newest first.
  Stream<List<PriceEntry>> watchHistoryForMenuOption(String menuOptionId);

  /// Current offers for a variant: newest price per place / global type, expired
  /// promos ignored (DATA_MODEL § 2 notes). Input for `BestOfferScorer`.
  Future<List<PriceEntry>> currentOffersForVariant(String variantId);

  Future<List<PriceEntry>> currentOffersForMenuOption(String menuOptionId);

  /// Insert or update a price entry. History is kept: log a *new* entry for a new
  /// price instead of editing an old one.
  Future<void> save(PriceEntry entry);

  /// Soft delete (e.g. a mistyped price).
  Future<void> delete(String id);
}

class DriftPricesRepository implements PricesRepository {
  DriftPricesRepository(this._db, {this._now = DateTime.now});

  final AppDatabase _db;
  final Now _now;

  SimpleSelectStatement<$PriceEntriesTable, PriceEntryRow> _history(
    Expression<bool> Function($PriceEntriesTable t) match,
  ) => _db.select(_db.priceEntries)
    ..where((t) => match(t) & t.deletedAt.isNull())
    ..orderBy([(t) => OrderingTerm.desc(t.seenAt)]);

  @override
  Stream<List<PriceEntry>> watchHistoryForVariant(String variantId) =>
      _history((t) => t.variantId.equals(variantId)).watch().map(_mapAll);

  @override
  Stream<List<PriceEntry>> watchHistoryForMenuOption(String menuOptionId) =>
      _history((t) => t.menuOptionId.equals(menuOptionId)).watch().map(_mapAll);

  @override
  Future<List<PriceEntry>> currentOffersForVariant(String variantId) async =>
      currentOffers(
        _mapAll(await _history((t) => t.variantId.equals(variantId)).get()),
        _now(),
      );

  @override
  Future<List<PriceEntry>> currentOffersForMenuOption(
    String menuOptionId,
  ) async => currentOffers(
    _mapAll(await _history((t) => t.menuOptionId.equals(menuOptionId)).get()),
    _now(),
  );

  List<PriceEntry> _mapAll(List<PriceEntryRow> rows) => rows.map(_map).toList();

  PriceEntry _map(PriceEntryRow r) {
    final currency = Currency.values.firstWhere((c) => c.code == r.currency);
    return PriceEntry(
      id: r.id,
      variantId: r.variantId,
      menuOptionId: r.menuOptionId,
      placeId: r.placeId,
      globalTypeId: r.globalTypeId,
      amount: Money(r.amountMinor, currency),
      amountMax: r.amountMaxMinor == null
          ? null
          : Money(r.amountMaxMinor!, currency),
      seenAt: fromEpochMs(r.seenAt),
      isPromo: r.isPromo,
      promoEndsAt: r.promoEndsAt == null ? null : fromEpochMs(r.promoEndsAt!),
      note: r.note,
    );
  }

  @override
  Future<void> save(PriceEntry entry) async {
    final now = toEpochMs(_now());
    final existing = await (_db.select(
      _db.priceEntries,
    )..where((t) => t.id.equals(entry.id))).getSingleOrNull();
    final values = PriceEntriesCompanion(
      variantId: Value(entry.variantId),
      menuOptionId: Value(entry.menuOptionId),
      placeId: Value(entry.placeId),
      globalTypeId: Value(entry.globalTypeId),
      amountMinor: Value(entry.amount.minor),
      amountMaxMinor: Value(entry.amountMax?.minor),
      currency: Value(entry.amount.currency.code),
      seenAt: Value(toEpochMs(entry.seenAt)),
      isPromo: Value(entry.isPromo),
      promoEndsAt: Value(
        entry.promoEndsAt == null ? null : toEpochMs(entry.promoEndsAt!),
      ),
      note: Value(entry.note),
      updatedAt: Value(now),
      deletedAt: const Value(null),
    );
    if (existing == null) {
      await _db
          .into(_db.priceEntries)
          .insert(values.copyWith(id: Value(entry.id), createdAt: Value(now)));
    } else {
      await (_db.update(
        _db.priceEntries,
      )..where((t) => t.id.equals(entry.id))).write(values);
    }
  }

  @override
  Future<void> delete(String id) {
    final now = toEpochMs(_now());
    return (_db.update(_db.priceEntries)..where((t) => t.id.equals(id))).write(
      PriceEntriesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }
}
