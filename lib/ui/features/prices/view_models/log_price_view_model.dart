import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/data_providers.dart';
import '../../../../data/repositories/settings_repository.dart';
import '../../../../data/services/open_food_facts_provider.dart';
import '../../../../data/services/open_food_facts_service.dart';
import '../../../../domain/models/ids.dart';
import '../../../../domain/models/lookups.dart';
import '../../../../domain/models/money.dart';
import '../../../../domain/models/photo.dart';
import '../../../../domain/models/place.dart';
import '../../../../domain/models/price_entry.dart';
import '../../../../domain/models/product.dart';
import '../../../../domain/search/normalize_for_search.dart';
import '../../../../domain/use_cases/best_offer_scorer.dart';
import '../../../../domain/use_cases/relative_time.dart';
import '../../../../domain/use_cases/unit_price.dart';
import '../../../../domain/use_cases/variant_resolver.dart';
import '../../products/view_models/catalog_providers.dart';
import '../../scan/view_models/barcode_lookup.dart';
import 'photo_store.dart';
import 'user_location.dart';

/// Pre-filled values of the form (all optional); they come from the route's query
/// parameters: `?placeId=`, `?productId=`, `?variantId=`, `?barcode=`.
class LogPriceArgs {
  const LogPriceArgs({
    this.placeId,
    this.productId,
    this.variantId,
    this.barcode,
  });

  final String? placeId;
  final String? productId;
  final String? variantId;
  final String? barcode;

  @override
  bool operator ==(Object other) =>
      other is LogPriceArgs &&
      other.placeId == placeId &&
      other.productId == productId &&
      other.variantId == variantId &&
      other.barcode == barcode;

  @override
  int get hashCode => Object.hash(placeId, productId, variantId, barcode);
}

enum LogPriceField { product, variant, amount, amountMax, where, promoEnd }

/// What the barcode lookup is doing / found.
enum LookupStatus { idle, loading, foundLocal, foundOff, notFound, offline }

/// How close a place must be to be suggested as "You are here".
const double kHereRadiusKm = 0.15;

const Object _keep = Object();

class LogPriceState {
  const LogPriceState({
    this.productText = '',
    this.product,
    this.variantId,
    this.newVariantName,
    this.categoryId,
    this.brand,
    this.barcode,
    this.productImageUrl,
    this.productPhotoPath,
    this.sizeText = '',
    this.unit = SizeUnit.g,
    this.amount,
    this.amountMax,
    this.isRange = false,
    this.isGlobal = false,
    this.place,
    this.placeHint,
    this.globalTypeId,
    this.isPromo = false,
    this.promoEndsAt,
    this.photoPath,
    this.note = '',
    this.lookup = LookupStatus.idle,
    this.saving = false,
    this.savedEntryId,
    this.errors = const {},
  });

  /// What is typed in the product box.
  final String productText;

  /// The existing product that was picked; null while typing a new one.
  final Product? product;

  /// The selected existing variant; null = none / the product's default.
  final String? variantId;

  /// Set while the user is creating a new variant ("+ Variant").
  final String? newVariantName;

  /// Only used when a new product is created.
  final String? categoryId;
  final String? brand;
  final String? barcode;
  final String? productImageUrl;
  final String? productPhotoPath;

  final String sizeText;
  final SizeUnit unit;
  final Money? amount;
  final Money? amountMax;
  final bool isRange;

  final bool isGlobal;
  final Place? place;

  /// "You are here · 20 m" when the place was suggested from the GPS position.
  final String? placeHint;
  final String? globalTypeId;
  final bool isPromo;
  final DateTime? promoEndsAt;

  /// A photo of the price tag (local path, copied into the photo store on save).
  final String? photoPath;
  final String note;
  final LookupStatus lookup;
  final bool saving;
  final String? savedEntryId;
  final Map<LogPriceField, String> errors;

  bool get isNewProduct => product == null && productText.trim().isNotEmpty;
  bool get hasPhoto => photoPath != null;

  double? get size => parseSize(sizeText);

  /// "= 44.000 TND / kg" while a size and a price are known.
  UnitPrice? get unitPrice =>
      amount == null ? null : unitPriceFor(amount!, size, unit);

  LogPriceState copyWith({
    String? productText,
    Object? product = _keep,
    Object? variantId = _keep,
    Object? newVariantName = _keep,
    Object? categoryId = _keep,
    Object? brand = _keep,
    Object? barcode = _keep,
    Object? productImageUrl = _keep,
    Object? productPhotoPath = _keep,
    String? sizeText,
    SizeUnit? unit,
    Object? amount = _keep,
    Object? amountMax = _keep,
    bool? isRange,
    bool? isGlobal,
    Object? place = _keep,
    Object? placeHint = _keep,
    Object? globalTypeId = _keep,
    bool? isPromo,
    Object? promoEndsAt = _keep,
    Object? photoPath = _keep,
    String? note,
    LookupStatus? lookup,
    bool? saving,
    Object? savedEntryId = _keep,
    Map<LogPriceField, String>? errors,
  }) {
    return LogPriceState(
      productText: productText ?? this.productText,
      product: identical(product, _keep) ? this.product : product as Product?,
      variantId: identical(variantId, _keep)
          ? this.variantId
          : variantId as String?,
      newVariantName: identical(newVariantName, _keep)
          ? this.newVariantName
          : newVariantName as String?,
      categoryId: identical(categoryId, _keep)
          ? this.categoryId
          : categoryId as String?,
      brand: identical(brand, _keep) ? this.brand : brand as String?,
      barcode: identical(barcode, _keep) ? this.barcode : barcode as String?,
      productImageUrl: identical(productImageUrl, _keep)
          ? this.productImageUrl
          : productImageUrl as String?,
      productPhotoPath: identical(productPhotoPath, _keep)
          ? this.productPhotoPath
          : productPhotoPath as String?,
      sizeText: sizeText ?? this.sizeText,
      unit: unit ?? this.unit,
      amount: identical(amount, _keep) ? this.amount : amount as Money?,
      amountMax: identical(amountMax, _keep)
          ? this.amountMax
          : amountMax as Money?,
      isRange: isRange ?? this.isRange,
      isGlobal: isGlobal ?? this.isGlobal,
      place: identical(place, _keep) ? this.place : place as Place?,
      placeHint: identical(placeHint, _keep)
          ? this.placeHint
          : placeHint as String?,
      globalTypeId: identical(globalTypeId, _keep)
          ? this.globalTypeId
          : globalTypeId as String?,
      isPromo: isPromo ?? this.isPromo,
      promoEndsAt: identical(promoEndsAt, _keep)
          ? this.promoEndsAt
          : promoEndsAt as DateTime?,
      photoPath: identical(photoPath, _keep)
          ? this.photoPath
          : photoPath as String?,
      note: note ?? this.note,
      lookup: lookup ?? this.lookup,
      saving: saving ?? this.saving,
      savedEntryId: identical(savedEntryId, _keep)
          ? this.savedEntryId
          : savedEntryId as String?,
      errors: errors ?? this.errors,
    );
  }
}

/// Checks the form; the returned map is empty when it can be saved. Pure, so it
/// is unit-tested without a database.
Map<LogPriceField, String> validateLogPrice(LogPriceState s, DateTime now) {
  final errors = <LogPriceField, String>{};
  if (s.productText.trim().isEmpty) {
    errors[LogPriceField.product] = 'What did you see? Type a product.';
  }
  if (s.newVariantName != null && s.newVariantName!.trim().isEmpty) {
    errors[LogPriceField.variant] = 'Name the variant, or remove it.';
  }
  final amount = s.amount;
  if (amount == null || amount.minor <= 0) {
    errors[LogPriceField.amount] = 'Enter the price.';
  } else if (s.isRange) {
    final max = s.amountMax;
    if (max == null || max.minor <= 0) {
      errors[LogPriceField.amountMax] = 'Enter the highest price.';
    } else if (max.minor < amount.minor) {
      errors[LogPriceField.amountMax] =
          'The highest price must not be below the lowest.';
    }
  }
  if (s.isGlobal) {
    if (s.globalTypeId == null) {
      errors[LogPriceField.where] = 'Pick what kind of global price this is.';
    }
  } else if (s.place == null) {
    errors[LogPriceField.where] = 'Pick the place, or choose Global.';
  }
  final ends = s.promoEndsAt;
  if (s.isPromo &&
      ends != null &&
      ends.isBefore(DateTime(now.year, now.month, now.day))) {
    errors[LogPriceField.promoEnd] = 'That date has already passed.';
  }
  return errors;
}

final logPriceViewModelProvider = NotifierProvider.autoDispose
    .family<LogPriceViewModel, LogPriceState, LogPriceArgs>(
      LogPriceViewModel.new,
    );

class LogPriceViewModel extends Notifier<LogPriceState> {
  LogPriceViewModel(this.args);

  final LogPriceArgs args;

  @override
  LogPriceState build() {
    unawaited(Future.microtask(_init));
    return const LogPriceState();
  }

  // ---------------------------------------------------------------- start-up

  Future<void> _init() async {
    try {
      await _prefill();
    } on Object {
      // The provider was disposed while loading (screen closed): nothing to do.
      if (ref.mounted) rethrow;
    }
  }

  Future<void> _prefill() async {
    final unitName = await ref
        .read(settingsRepositoryProvider)
        .get(SettingKeys.defaultUnit);
    final unit = SizeUnit.values.asNameMap()[unitName];
    if (!ref.mounted) return;
    if (unit != null) state = state.copyWith(unit: unit);

    final productId = args.productId;
    if (productId != null) {
      final product = await ref.read(productsRepositoryProvider).get(productId);
      if (!ref.mounted) return;
      if (product != null) selectProduct(product, variantId: args.variantId);
    }

    final placeId = args.placeId;
    if (placeId != null) {
      final place = await ref.read(placesRepositoryProvider).get(placeId);
      if (!ref.mounted) return;
      if (place != null) state = state.copyWith(place: place, isGlobal: false);
    }

    final barcode = args.barcode;
    if (barcode != null && barcode.isNotEmpty) await applyBarcode(barcode);

    if (placeId == null) await _suggestNearbyPlace();
  }

  /// Pre-selects the place you are standing in ("You are here · 20 m").
  Future<void> _suggestNearbyPlace() async {
    final here = await ref.read(userLocationProvider.future);
    if (here == null || !ref.mounted) return;
    final places = await ref.read(placesRepositoryProvider).watchAll().first;
    if (!ref.mounted || state.place != null || state.isGlobal) return;

    Place? nearest;
    var nearestKm = double.infinity;
    for (final place in places) {
      if (!place.hasLocation) continue;
      final km = distanceKm(here.lat, here.lng, place.lat!, place.lng!);
      if (km < nearestKm) {
        nearest = place;
        nearestKm = km;
      }
    }
    if (nearest == null || nearestKm > kHereRadiusKm) return;
    final distance = nearestKm < 1
        ? '${(nearestKm * 1000).round()} m'
        : formatKm(nearestKm);
    state = state.copyWith(
      place: nearest,
      placeHint: 'You are here · $distance',
    );
  }

  // ----------------------------------------------------------------- product

  /// Typing in the product box. Editing the text drops the picked product.
  void setProductText(String text) {
    final picked = state.product;
    final stillSame =
        picked != null &&
        normalizeForSearch(picked.name) == normalizeForSearch(text);
    state = state.copyWith(
      productText: text,
      product: stillSame ? picked : null,
      variantId: stillSame ? state.variantId : null,
      newVariantName: stillSame ? state.newVariantName : null,
      errors: _without(LogPriceField.product),
    );
  }

  void selectProduct(Product product, {String? variantId}) {
    final variants = product.variants;
    final chosen =
        variants.where((v) => v.id == variantId).firstOrNull ??
        variants.firstOrNull;
    state = state.copyWith(
      productText: product.name,
      product: product,
      brand: product.brand,
      categoryId: product.categoryId,
      productPhotoPath: product.photoPath,
      newVariantName: null,
      errors: _without(LogPriceField.product),
    );
    selectVariant(chosen?.id);
  }

  /// Picks one of the product's variants and pre-fills its size.
  void selectVariant(String? id) {
    final variant = state.product?.variants
        .where((v) => v.id == id)
        .firstOrNull;
    state = state.copyWith(
      variantId: id,
      newVariantName: null,
      sizeText: variant?.sizeValue == null ? '' : _plain(variant!.sizeValue!),
      unit: variant?.sizeUnit ?? state.unit,
      errors: _without(LogPriceField.variant),
    );
  }

  /// "+ Variant": starts a new, named variant.
  void startNewVariant() =>
      state = state.copyWith(variantId: null, newVariantName: '');

  void setNewVariantName(String name) => state = state.copyWith(
    newVariantName: name,
    errors: _without(LogPriceField.variant),
  );

  void cancelNewVariant() {
    final first = state.product?.variants.firstOrNull;
    if (first != null) {
      selectVariant(first.id);
    } else {
      state = state.copyWith(newVariantName: null);
    }
  }

  void setCategory(String? id) => state = state.copyWith(categoryId: id);

  // -------------------------------------------------------------------- size

  void setSizeText(String text) => state = state.copyWith(sizeText: text);

  void setUnit(SizeUnit unit) => state = state.copyWith(unit: unit);

  // ------------------------------------------------------------------- price

  void setAmount(Money? amount) => state = state.copyWith(
    amount: amount,
    errors: _without(LogPriceField.amount),
  );

  void setAmountMax(Money? amount) => state = state.copyWith(
    amountMax: amount,
    errors: _without(LogPriceField.amountMax),
  );

  void setRange({required bool on}) => state = state.copyWith(
    isRange: on,
    amountMax: on ? state.amountMax : null,
    errors: _without(LogPriceField.amountMax),
  );

  // ------------------------------------------------------------------- where

  void setPlace(Place place) => state = state.copyWith(
    place: place,
    placeHint: null,
    isGlobal: false,
    errors: _without(LogPriceField.where),
  );

  /// "Global": a price that is not tied to a store. Defaults to the first type label.
  Future<void> useGlobal() async {
    state = state.copyWith(
      isGlobal: true,
      placeHint: null,
      errors: _without(LogPriceField.where),
    );
    if (state.globalTypeId != null) return;
    final types = await ref
        .read(globalPriceTypesRepositoryProvider)
        .watchAll()
        .first;
    if (!ref.mounted || types.isEmpty) return;
    state = state.copyWith(globalTypeId: state.globalTypeId ?? types.first.id);
  }

  void usePlace() => state = state.copyWith(isGlobal: false);

  void setGlobalType(String id) => state = state.copyWith(
    globalTypeId: id,
    errors: _without(LogPriceField.where),
  );

  /// A new editable type label ("Online price", …).
  Future<void> addGlobalType(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final repo = ref.read(globalPriceTypesRepositoryProvider);
    final existing = await repo.watchAll().first;
    final type = GlobalPriceType(
      id: newId(),
      name: trimmed,
      sortOrder: existing.length,
    );
    await repo.save(type);
    if (ref.mounted) setGlobalType(type.id);
  }

  // ------------------------------------------------------------------- promo

  void setPromo({required bool on}) => state = state.copyWith(
    isPromo: on,
    promoEndsAt: on ? state.promoEndsAt : null,
    errors: _without(LogPriceField.promoEnd),
  );

  void setPromoEnd(DateTime? date) => state = state.copyWith(
    promoEndsAt: date,
    errors: _without(LogPriceField.promoEnd),
  );

  // ------------------------------------------------------------ photo + note

  Future<void> pickPhoto(PhotoSource source) async {
    final path = await ref.read(photoPickerProvider)(source);
    if (path != null && ref.mounted) state = state.copyWith(photoPath: path);
  }

  void removePhoto() => state = state.copyWith(photoPath: null);

  void setNote(String note) => state = state.copyWith(note: note);

  // ----------------------------------------------------------------- barcode

  /// Looks a scanned code up (local database first, then Open Food Facts) and
  /// fills the form. Never blocks: offline simply leaves the form for typing.
  Future<void> applyBarcode(String code) async {
    state = state.copyWith(barcode: code, lookup: LookupStatus.loading);
    final match = await ref.read(barcodeLookupProvider).lookup(code);
    if (!ref.mounted) return;

    switch (match) {
      case LocalMatch(:final product, :final variant):
        selectProduct(product, variantId: variant.id);
        state = state.copyWith(barcode: code, lookup: LookupStatus.foundLocal);
      case OffMatch(:final product):
        await _applyOff(code, product);
      case NoMatch(:final offline):
        state = state.copyWith(
          lookup: offline ? LookupStatus.offline : LookupStatus.notFound,
        );
    }
  }

  Future<void> _applyOff(String code, OffProduct off) async {
    // The same product may already be here under another barcode: reuse it.
    final key = normalizeForSearch(off.name);
    final known = (await ref.read(productsRepositoryProvider).watchAll().first)
        .where((p) => normalizeForSearch(p.name) == key)
        .firstOrNull;
    if (!ref.mounted) return;

    if (known != null) {
      selectProduct(known);
    } else {
      state = state.copyWith(
        productText: off.name,
        product: null,
        variantId: null,
        newVariantName: null,
        brand: off.brand,
        productImageUrl: off.imageUrl,
      );
    }
    if (off.sizeValue != null && off.sizeUnit != null) {
      state = state.copyWith(
        sizeText: _plain(off.sizeValue!),
        unit: off.sizeUnit,
      );
    }
    state = state.copyWith(
      barcode: code,
      lookup: LookupStatus.foundOff,
      errors: _without(LogPriceField.product),
    );

    final url = off.imageUrl;
    if (url != null && known?.photoPath == null) {
      unawaited(_downloadProductPhoto(url, code));
    }
  }

  /// Downloads the product picture in the background; failures are silent.
  Future<void> _downloadProductPhoto(String url, String code) async {
    final bytes = await ref
        .read(openFoodFactsServiceProvider)
        .downloadImage(url);
    if (bytes == null || !ref.mounted || state.barcode != code) return;
    final path = await ref.read(photoStoreProvider).saveBytes(bytes);
    if (ref.mounted && state.barcode == code) {
      state = state.copyWith(productPhotoPath: path);
    }
  }

  // -------------------------------------------------------------------- save

  /// Validates and saves the product (if new), its variant (if new) and the
  /// price. Returns true on success; [LogPriceState.savedEntryId] is then set.
  Future<bool> save() async {
    if (state.saving) return false;
    final now = ref.read(clockProvider)();
    final errors = validateLogPrice(state, now);
    if (errors.isNotEmpty) {
      state = state.copyWith(errors: errors);
      return false;
    }
    state = state.copyWith(saving: true, errors: const {});
    try {
      final s = state;
      final products = ref.read(productsRepositoryProvider);

      // Typing the exact name of a known product must not create a duplicate.
      final typedKey = normalizeForSearch(s.productText);
      final sameName =
          s.product ??
          (await products.watchAll().first)
              .where((p) => normalizeForSearch(p.name) == typedKey)
              .firstOrNull;
      final base =
          sameName ??
          Product(
            id: newId(),
            name: s.productText.trim(),
            brand: s.brand,
            categoryId: s.categoryId,
            photoPath: s.productPhotoPath,
          );
      final selected = base.variants
          .where((v) => v.id == s.variantId)
          .firstOrNull;
      final size = s.size;
      final resolution = resolveVariant(
        product: base,
        newVariantId: newId,
        variantName: s.newVariantName ?? selected?.name,
        sizeValue: size,
        sizeUnit: size == null ? null : s.unit,
        barcode: s.barcode,
      );
      if (sameName == null || resolution.changed) {
        await products.save(resolution.product);
      }

      final entry = PriceEntry(
        id: newId(),
        variantId: resolution.variant.id,
        placeId: s.isGlobal ? null : s.place!.id,
        globalTypeId: s.isGlobal ? s.globalTypeId : null,
        amount: s.amount!,
        amountMax: s.isRange ? s.amountMax : null,
        seenAt: now,
        isPromo: s.isPromo,
        promoEndsAt: s.isPromo ? s.promoEndsAt : null,
        note: s.note.trim().isEmpty ? null : s.note.trim(),
      );
      await ref.read(pricesRepositoryProvider).save(entry);

      final photo = s.photoPath;
      if (photo != null) {
        final stored = await ref.read(photoStoreProvider).importFile(photo);
        await ref
            .read(photosRepositoryProvider)
            .save(
              Photo(
                id: newId(),
                ownerType: PhotoOwner.price,
                ownerId: entry.id,
                filePath: stored,
              ),
            );
      }
      if (ref.mounted) {
        state = state.copyWith(saving: false, savedEntryId: entry.id);
      }
      return true;
    } on Object {
      if (ref.mounted) state = state.copyWith(saving: false);
      rethrow;
    }
  }

  Map<LogPriceField, String> _without(LogPriceField field) =>
      state.errors.containsKey(field)
      ? ({...state.errors}..remove(field))
      : state.errors;
}

/// 100.0 → "100", 1.5 → "1.5".
String _plain(double value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toString();
