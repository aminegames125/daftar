import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'repositories/accounts_repository.dart';
import 'repositories/bills_repository.dart';
import 'repositories/categories_repository.dart';
import 'repositories/debts_repository.dart';
import 'repositories/global_price_types_repository.dart';
import 'repositories/menu_repository.dart';
import 'repositories/payment_methods_repository.dart';
import 'repositories/photos_repository.dart';
import 'repositories/place_types_repository.dart';
import 'repositories/places_repository.dart';
import 'repositories/prices_repository.dart';
import 'repositories/products_repository.dart';
import 'repositories/rate_entries_repository.dart';
import 'repositories/saved_lists_repository.dart';
import 'repositories/settings_repository.dart';
import 'repositories/transactions_repository.dart';
import 'services/database/app_database.dart';

/// The one database. `main()` overrides it with an already-created instance;
/// tests override it with an in-memory one. Opening is lazy, so widget tests that
/// never touch data do not need it.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => DriftSettingsRepository(ref.watch(appDatabaseProvider)),
);

final placeTypesRepositoryProvider = Provider<PlaceTypesRepository>(
  (ref) => DriftPlaceTypesRepository(ref.watch(appDatabaseProvider)),
);

final paymentMethodsRepositoryProvider = Provider<PaymentMethodsRepository>(
  (ref) => DriftPaymentMethodsRepository(ref.watch(appDatabaseProvider)),
);

final placesRepositoryProvider = Provider<PlacesRepository>(
  (ref) => DriftPlacesRepository(ref.watch(appDatabaseProvider)),
);

final categoriesRepositoryProvider = Provider<CategoriesRepository>(
  (ref) => DriftCategoriesRepository(ref.watch(appDatabaseProvider)),
);

final productsRepositoryProvider = Provider<ProductsRepository>(
  (ref) => DriftProductsRepository(ref.watch(appDatabaseProvider)),
);

final menuRepositoryProvider = Provider<MenuRepository>(
  (ref) => DriftMenuRepository(ref.watch(appDatabaseProvider)),
);

final globalPriceTypesRepositoryProvider = Provider<GlobalPriceTypesRepository>(
  (ref) => DriftGlobalPriceTypesRepository(ref.watch(appDatabaseProvider)),
);

final pricesRepositoryProvider = Provider<PricesRepository>(
  (ref) => DriftPricesRepository(ref.watch(appDatabaseProvider)),
);

final accountsRepositoryProvider = Provider<AccountsRepository>(
  (ref) => DriftAccountsRepository(ref.watch(appDatabaseProvider)),
);

final transactionsRepositoryProvider = Provider<TransactionsRepository>(
  (ref) => DriftTransactionsRepository(ref.watch(appDatabaseProvider)),
);

final rateEntriesRepositoryProvider = Provider<RateEntriesRepository>(
  (ref) => DriftRateEntriesRepository(ref.watch(appDatabaseProvider)),
);

final savedListsRepositoryProvider = Provider<SavedListsRepository>(
  (ref) => DriftSavedListsRepository(ref.watch(appDatabaseProvider)),
);

final billsRepositoryProvider = Provider<BillsRepository>(
  (ref) => DriftBillsRepository(ref.watch(appDatabaseProvider)),
);

final debtsRepositoryProvider = Provider<DebtsRepository>(
  (ref) => DriftDebtsRepository(ref.watch(appDatabaseProvider)),
);

final photosRepositoryProvider = Provider<PhotosRepository>(
  (ref) => DriftPhotosRepository(ref.watch(appDatabaseProvider)),
);
