/// A reusable shopping list ("Monthly groceries").
class SavedList {
  const SavedList({required this.id, required this.name, this.sortOrder = 0});

  final String id;
  final String name;
  final int sortOrder;
}

/// A line of a [SavedList]: a product variant or free text, never both.
class SavedListItem {
  const SavedListItem({
    required this.id,
    required this.listId,
    this.variantId,
    this.freeText,
    this.quantity = 1,
    this.isChecked = false,
    this.sortOrder = 0,
  }) : assert(
         (variantId == null) != (freeText == null),
         'Set exactly one of variantId / freeText',
       ),
       assert(quantity > 0);

  final String id;
  final String listId;
  final String? variantId;
  final String? freeText;
  final int quantity;
  final bool isChecked;
  final int sortOrder;

  SavedListItem copyWith({int? quantity, bool? isChecked, int? sortOrder}) =>
      SavedListItem(
        id: id,
        listId: listId,
        variantId: variantId,
        freeText: freeText,
        quantity: quantity ?? this.quantity,
        isChecked: isChecked ?? this.isChecked,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}
