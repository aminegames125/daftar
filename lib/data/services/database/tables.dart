import 'package:drift/drift.dart';

import '../../../domain/models/account.dart';
import '../../../domain/models/bill.dart';
import '../../../domain/models/debt.dart';
import '../../../domain/models/lookups.dart';
import '../../../domain/models/money.dart';
import '../../../domain/models/photo.dart';
import '../../../domain/models/product.dart';

/// Columns every table row carries (DATA_MODEL § 1). Times are UTC epoch ms.
mixin BaseColumns on Table {
  TextColumn get id => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  /// Soft delete. All reads filter `deleted_at IS NULL`.
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DataClassName('PlaceTypeRow')
class PlaceTypes extends Table with BaseColumns {
  TextColumn get name => text()();
  TextColumn get iconKey => text()();
  TextColumn get kind => textEnum<PlaceKind>()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isBuiltIn => boolean().withDefault(const Constant(false))();
}

@TableIndex(name: 'places_search_key', columns: {#searchKey})
@DataClassName('PlaceRow')
class Places extends Table with BaseColumns {
  TextColumn get name => text()();
  TextColumn get typeId => text().references(PlaceTypes, #id)();
  RealColumn get lat => real().nullable()();
  RealColumn get lng => real().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get phone => text().nullable()();

  /// JSON, see DATA_MODEL § 5.
  TextColumn get openingHours => text().nullable()();
  TextColumn get wifiName => text().nullable()();
  TextColumn get wifiPassword => text().nullable()();
  IntColumn get rating => integer().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get searchKey => text()();

  @override
  List<String> get customConstraints => [
    'CHECK (rating IS NULL OR (rating BETWEEN 1 AND 5))',
  ];
}

@DataClassName('PaymentMethodRow')
class PaymentMethods extends Table with BaseColumns {
  TextColumn get name => text()();
  TextColumn get iconKey => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isBuiltIn => boolean().withDefault(const Constant(false))();
}

class PlacePaymentMethods extends Table {
  TextColumn get placeId => text().references(Places, #id)();
  TextColumn get paymentMethodId => text().references(PaymentMethods, #id)();

  @override
  Set<Column> get primaryKey => {placeId, paymentMethodId};
}

class PlaceTags extends Table {
  TextColumn get placeId => text().references(Places, #id)();
  TextColumn get tag => text()();

  @override
  Set<Column> get primaryKey => {placeId, tag};
}

@DataClassName('CategoryRow')
class Categories extends Table with BaseColumns {
  TextColumn get name => text()();
  TextColumn get iconKey => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isBuiltIn => boolean().withDefault(const Constant(false))();
}

@TableIndex(name: 'products_search_key', columns: {#searchKey})
@DataClassName('ProductRow')
class Products extends Table with BaseColumns {
  TextColumn get name => text()();
  TextColumn get brand => text().nullable()();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get photoPath => text().nullable()();
  TextColumn get searchKey => text()();
}

@TableIndex(name: 'variants_barcode', columns: {#barcode})
@TableIndex(name: 'variants_search_key', columns: {#searchKey})
@TableIndex(name: 'variants_product', columns: {#productId})
@DataClassName('VariantRow')
class Variants extends Table with BaseColumns {
  TextColumn get productId => text().references(Products, #id)();

  /// NULL = the default variant.
  TextColumn get name => text().nullable()();
  TextColumn get barcode => text().nullable()();
  RealColumn get sizeValue => real().nullable()();
  TextColumn get sizeUnit => textEnum<SizeUnit>().nullable()();

  /// Size normalised to g, ml or pieces.
  IntColumn get baseQuantity => integer().nullable()();
  TextColumn get searchKey => text()();
}

@TableIndex(name: 'menu_sections_place', columns: {#placeId})
@DataClassName('MenuSectionRow')
class MenuSections extends Table with BaseColumns {
  TextColumn get placeId => text().references(Places, #id)();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

@TableIndex(name: 'menu_items_place', columns: {#placeId})
@TableIndex(name: 'menu_items_search_key', columns: {#searchKey})
@DataClassName('MenuItemRow')
class MenuItems extends Table with BaseColumns {
  TextColumn get placeId => text().references(Places, #id)();
  TextColumn get sectionId => text().nullable().references(MenuSections, #id)();
  TextColumn get name => text()();
  BoolColumn get isUsual => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get searchKey => text()();
}

@TableIndex(name: 'menu_item_options_item', columns: {#menuItemId})
@DataClassName('MenuItemOptionRow')
class MenuItemOptions extends Table with BaseColumns {
  TextColumn get menuItemId => text().references(MenuItems, #id)();

  /// NULL = the item has a single price.
  TextColumn get name => text().nullable()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

@DataClassName('GlobalPriceTypeRow')
class GlobalPriceTypes extends Table with BaseColumns {
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get isBuiltIn => boolean().withDefault(const Constant(false))();
}

@TableIndex(
  name: 'price_entries_variant',
  columns: {#variantId, #placeId, #seenAt},
)
@TableIndex(
  name: 'price_entries_menu_option',
  columns: {#menuOptionId, #seenAt},
)
@DataClassName('PriceEntryRow')
class PriceEntries extends Table with BaseColumns {
  TextColumn get variantId => text().nullable().references(Variants, #id)();
  TextColumn get menuOptionId =>
      text().nullable().references(MenuItemOptions, #id)();

  /// NULL = a global price.
  TextColumn get placeId => text().nullable().references(Places, #id)();
  TextColumn get globalTypeId =>
      text().nullable().references(GlobalPriceTypes, #id)();
  IntColumn get amountMinor => integer()();

  /// Upper end of a min–max range.
  IntColumn get amountMaxMinor => integer().nullable()();
  TextColumn get currency => text().withDefault(const Constant('TND'))();
  IntColumn get seenAt => integer()();
  BoolColumn get isPromo => boolean().withDefault(const Constant(false))();
  IntColumn get promoEndsAt => integer().nullable()();
  TextColumn get note => text().nullable()();

  /// "I bought it" link to a transaction. No foreign key until that table exists.
  TextColumn get transactionId => text().nullable()();

  @override
  List<String> get customConstraints => [
    'CHECK ((variant_id IS NULL) != (menu_option_id IS NULL))',
    'CHECK (place_id IS NOT NULL OR global_type_id IS NOT NULL)',
  ];
}

@TableIndex(name: 'photos_owner', columns: {#ownerType, #ownerId})
@DataClassName('PhotoRow')
class Photos extends Table with BaseColumns {
  TextColumn get ownerType => textEnum<PhotoOwner>()();
  TextColumn get ownerId => text()();
  TextColumn get filePath => text()();
  TextColumn get ocrText => text().nullable()();
}

// ---------------------------------------------------------------------------
// Schema v2 (DATA_MODEL § 4-7). Enums are stored by name (`textEnum`), so the
// Dart enum member names are part of the on-disk format: never rename them.
// ---------------------------------------------------------------------------

@TableIndex(name: 'accounts_search_key', columns: {#searchKey})
@DataClassName('AccountRow')
class Accounts extends Table with BaseColumns {
  TextColumn get name => text()();
  TextColumn get kind => textEnum<AccountKind>()();
  TextColumn get currency => textEnum<Currency>()();
  IntColumn get openingBalanceMinor =>
      integer().withDefault(const Constant(0))();
  BoolColumn get includeInTotals =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get hideAmount => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get iconKey => text()();
  TextColumn get searchKey => text()();
}

@TableIndex(
  name: 'transactions_account_time',
  columns: {#accountId, #occurredAt},
)
@TableIndex(name: 'transactions_pair', columns: {#pairId})
@DataClassName('TransactionRow')
class Transactions extends Table with BaseColumns {
  TextColumn get accountId => text().references(Accounts, #id)();
  TextColumn get kind => textEnum<TransactionKind>()();

  /// Magnitude, except `exchange` which is signed (see AccountTransaction).
  IntColumn get amountMinor => integer()();
  TextColumn get currency => textEnum<Currency>()();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get note => text().nullable()();
  IntColumn get occurredAt => integer()();

  /// "I bought it": the logged price this expense paid for.
  TextColumn get priceEntryId =>
      text().nullable().references(PriceEntries, #id)();

  /// Shared by both legs of a transfer / exchange.
  TextColumn get pairId => text().nullable()();
  IntColumn get feeMinor => integer().nullable()();

  /// TND per 1 USD x 10 000.
  IntColumn get rateTenThousandths => integer().nullable()();
}

@TableIndex(name: 'rate_entries_date', columns: {#date})
@DataClassName('RateEntryRow')
class RateEntries extends Table with BaseColumns {
  IntColumn get date => integer()();

  /// TND per 1 USD x 10 000 (3.1250 -> 31250).
  IntColumn get tndPerUsdTenThousandths => integer()();
  TextColumn get sourceNote => text().nullable()();
}

@TableIndex(name: 'saved_lists_search_key', columns: {#searchKey})
@DataClassName('SavedListRow')
class SavedLists extends Table with BaseColumns {
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get searchKey => text()();
}

@TableIndex(name: 'saved_list_items_list', columns: {#listId, #sortOrder})
@DataClassName('SavedListItemRow')
class SavedListItems extends Table with BaseColumns {
  TextColumn get listId => text().references(SavedLists, #id)();
  TextColumn get variantId => text().nullable().references(Variants, #id)();
  TextColumn get freeText => text().nullable()();
  IntColumn get quantity => integer().withDefault(const Constant(1))();
  BoolColumn get isChecked => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  List<String> get customConstraints => [
    'CHECK ((variant_id IS NULL) != (free_text IS NULL))',
  ];
}

@TableIndex(name: 'bills_search_key', columns: {#searchKey})
@TableIndex(name: 'bills_next_due', columns: {#nextDueAt})
@DataClassName('BillRow')
class Bills extends Table with BaseColumns {
  TextColumn get name => text()();
  IntColumn get amountMinor => integer()();
  TextColumn get currency => textEnum<Currency>()();
  TextColumn get cycle => textEnum<BillCycle>()();
  IntColumn get customDays => integer().nullable()();
  IntColumn get nextDueAt => integer()();
  IntColumn get reminderDaysBefore =>
      integer().withDefault(const Constant(3))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get iconKey => text()();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get searchKey => text()();
}

@TableIndex(name: 'bill_payments_bill', columns: {#billId, #paidAt})
@DataClassName('BillPaymentRow')
class BillPayments extends Table with BaseColumns {
  TextColumn get billId => text().references(Bills, #id)();
  IntColumn get amountMinor => integer()();
  IntColumn get paidAt => integer()();
}

@TableIndex(name: 'debts_search_key', columns: {#searchKey})
@DataClassName('DebtRow')
class Debts extends Table with BaseColumns {
  TextColumn get name => text()();
  TextColumn get direction => textEnum<DebtDirection>()();
  IntColumn get amountMinor => integer()();
  TextColumn get currency => textEnum<Currency>()();
  TextColumn get note => text().nullable()();
  IntColumn get dueAt => integer().nullable()();
  TextColumn get sourceAccountId =>
      text().nullable().references(Accounts, #id)();
  TextColumn get searchKey => text()();
}

@TableIndex(name: 'debt_payments_debt', columns: {#debtId, #paidAt})
@DataClassName('DebtPaymentRow')
class DebtPayments extends Table with BaseColumns {
  TextColumn get debtId => text().references(Debts, #id)();
  IntColumn get amountMinor => integer()();
  IntColumn get paidAt => integer()();
}
