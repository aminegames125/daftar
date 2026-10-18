import '../models/ids.dart';
import '../models/menu.dart';
import '../models/money.dart';
import '../search/normalize_for_search.dart';
import 'menu_line_parser.dart';

/// One size/option row on the review screen. Texts stay strings while editing.
class ReviewOption {
  const ReviewOption({required this.id, this.name = '', this.price = ''});

  final String id;

  /// Empty = single price.
  final String name;
  final String price;

  ReviewOption copyWith({String? name, String? price}) =>
      ReviewOption(id: id, name: name ?? this.name, price: price ?? this.price);

  /// null when empty (price not set), invalid when the text is not an amount.
  Money? get money => Money.tryParse(price);
  bool get hasInvalidPrice => price.trim().isNotEmpty && money == null;
}

class ReviewItem {
  const ReviewItem({
    required this.id,
    this.name = '',
    this.options = const [],
    this.isUsual = false,
  });

  final String id;
  final String name;
  final List<ReviewOption> options;
  final bool isUsual;

  ReviewItem copyWith({
    String? name,
    List<ReviewOption>? options,
    bool? isUsual,
  }) => ReviewItem(
    id: id,
    name: name ?? this.name,
    options: options ?? this.options,
    isUsual: isUsual ?? this.isUsual,
  );
}

class ReviewSection {
  const ReviewSection({
    required this.id,
    this.name = '',
    this.items = const [],
  });

  final String id;

  /// Empty = items without a section.
  final String name;
  final List<ReviewItem> items;

  ReviewSection copyWith({String? name, List<ReviewItem>? items}) =>
      ReviewSection(
        id: id,
        name: name ?? this.name,
        items: items ?? this.items,
      );
}

/// What the user edits on the review screen after a scan (or a typed menu).
class MenuReviewDraft {
  const MenuReviewDraft(this.sections);

  const MenuReviewDraft.empty() : sections = const [];

  final List<ReviewSection> sections;

  /// Turns the parser output into an editable draft. [idGen] is injectable for tests.
  factory MenuReviewDraft.fromParsed(
    ParsedMenu parsed, {
    String Function()? idGen,
  }) {
    final gen = idGen ?? newId;
    String money(ParsedOption o) => o.price.format();
    return MenuReviewDraft([
      for (final s in parsed.sections)
        ReviewSection(
          id: gen(),
          name: s.name ?? '',
          items: [
            for (final i in s.items)
              ReviewItem(
                id: gen(),
                name: i.name,
                options: [
                  for (final o in i.options)
                    ReviewOption(
                      id: gen(),
                      name: o.name ?? '',
                      price: money(o),
                    ),
                ],
              ),
          ],
        ),
    ]);
  }

  int get itemCount => sections.fold(0, (n, s) => n + s.items.length);

  /// Items that have a name but a price that is not a number.
  int get invalidPriceCount => sections
      .expand((s) => s.items)
      .where((i) => i.name.trim().isNotEmpty)
      .expand((i) => i.options)
      .where((o) => o.hasInvalidPrice)
      .length;

  bool get canSave =>
      sections.any((s) => s.items.any((i) => i.name.trim().isNotEmpty)) &&
      invalidPriceCount == 0;

  // ---- editing (all return a new draft) ----

  MenuReviewDraft _mapSection(
    String sectionId,
    ReviewSection Function(ReviewSection) f,
  ) =>
      MenuReviewDraft([for (final s in sections) s.id == sectionId ? f(s) : s]);

  MenuReviewDraft renameSection(String sectionId, String name) =>
      _mapSection(sectionId, (s) => s.copyWith(name: name));

  MenuReviewDraft removeSection(String sectionId) => MenuReviewDraft([
    for (final s in sections)
      if (s.id != sectionId) s,
  ]);

  MenuReviewDraft addSection({String? id, String name = ''}) => MenuReviewDraft(
    [...sections, ReviewSection(id: id ?? newId(), name: name)],
  );

  MenuReviewDraft addItem(String sectionId, {String? id, String? optionId}) =>
      _mapSection(
        sectionId,
        (s) => s.copyWith(
          items: [
            ...s.items,
            ReviewItem(
              id: id ?? newId(),
              options: [ReviewOption(id: optionId ?? newId())],
            ),
          ],
        ),
      );

  MenuReviewDraft updateItem(
    String itemId,
    ReviewItem Function(ReviewItem) f,
  ) => MenuReviewDraft([
    for (final s in sections)
      s.copyWith(items: [for (final i in s.items) i.id == itemId ? f(i) : i]),
  ]);

  MenuReviewDraft removeItem(String itemId) => MenuReviewDraft([
    for (final s in sections)
      s.copyWith(
        items: [
          for (final i in s.items)
            if (i.id != itemId) i,
        ],
      ),
  ]);

  MenuReviewDraft renameItem(String itemId, String name) =>
      updateItem(itemId, (i) => i.copyWith(name: name));

  MenuReviewDraft setOption(
    String itemId,
    String optionId, {
    String? name,
    String? price,
  }) => updateItem(
    itemId,
    (i) => i.copyWith(
      options: [
        for (final o in i.options)
          o.id == optionId ? o.copyWith(name: name, price: price) : o,
      ],
    ),
  );

  /// Adds a size. Going from one price to two names them "S" and "L" for a start.
  MenuReviewDraft addOption(String itemId, {String? id}) => updateItem(itemId, (
    i,
  ) {
    final first = i.options.length == 1 && i.options.first.name.trim().isEmpty;
    return i.copyWith(
      options: [
        if (first) i.options.first.copyWith(name: 'S') else ...i.options,
        ReviewOption(id: id ?? newId(), name: first ? 'L' : ''),
      ],
    );
  });

  MenuReviewDraft removeOption(String itemId, String optionId) => updateItem(
    itemId,
    (i) => i.options.length <= 1
        ? i
        : i.copyWith(
            options: [
              for (final o in i.options)
                if (o.id != optionId) o,
            ],
          ),
  );

  MenuReviewDraft toggleUsual(String itemId) =>
      updateItem(itemId, (i) => i.copyWith(isUsual: !i.isUsual));
}

/// A price to log for an option when the plan is applied.
class PlannedPrice {
  const PlannedPrice({required this.menuOptionId, required this.amount});

  final String menuOptionId;
  final Money amount;
}

/// Everything to write for one saved menu.
class MenuSavePlan {
  const MenuSavePlan({
    required this.newSections,
    required this.items,
    required this.prices,
  });

  /// Sections that do not exist yet (sections with a matching name are reused).
  final List<MenuSection> newSections;
  final List<MenuItem> items;
  final List<PlannedPrice> prices;
}

/// Builds the rows to store for [draft]. Items without a name are dropped;
/// options without a price are kept without a price entry. A section whose name
/// matches an existing one (accent/case-insensitive) is reused.
MenuSavePlan buildMenuSavePlan(
  MenuReviewDraft draft, {
  required String placeId,
  List<MenuSection> existingSections = const [],
  int existingSectionCount = 0,
  int existingItemCount = 0,
}) {
  final byName = {
    for (final s in existingSections) normalizeForSearch(s.name): s,
  };
  final newSections = <MenuSection>[];
  final items = <MenuItem>[];
  final prices = <PlannedPrice>[];
  var sectionOrder = existingSectionCount;
  var itemOrder = existingItemCount;

  for (final rs in draft.sections) {
    final named = rs.items.where((i) => i.name.trim().isNotEmpty).toList();
    if (named.isEmpty) continue;

    String? sectionId;
    final sectionName = rs.name.trim();
    if (sectionName.isNotEmpty) {
      final key = normalizeForSearch(sectionName);
      final existing = byName[key];
      if (existing != null) {
        sectionId = existing.id;
      } else {
        final created = MenuSection(
          id: rs.id,
          placeId: placeId,
          name: sectionName,
          sortOrder: sectionOrder++,
        );
        newSections.add(created);
        byName[key] = created;
        sectionId = created.id;
      }
    }

    for (final ri in named) {
      final single = ri.options.length <= 1;
      final options = <MenuItemOption>[];
      for (var n = 0; n < ri.options.length; n++) {
        final ro = ri.options[n];
        // A single-price item uses the same default option id the repository would create.
        final optionId = single ? builtInId('default_option', ri.id) : ro.id;
        options.add(
          MenuItemOption(
            id: optionId,
            menuItemId: ri.id,
            name: single || ro.name.trim().isEmpty ? null : ro.name.trim(),
            sortOrder: n,
          ),
        );
        final money = ro.money;
        if (money != null && money.minor > 0) {
          prices.add(PlannedPrice(menuOptionId: optionId, amount: money));
        }
      }
      items.add(
        MenuItem(
          id: ri.id,
          placeId: placeId,
          sectionId: sectionId,
          name: ri.name.trim(),
          isUsual: ri.isUsual,
          sortOrder: itemOrder++,
          options: options,
        ),
      );
    }
  }
  return MenuSavePlan(newSections: newSections, items: items, prices: prices);
}
