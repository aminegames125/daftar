import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A fresh random UUID v4 for a new row.
String newId() => _uuid.v4();

/// A stable UUID (v5) for a built-in row, so every install seeds the *same* id
/// for "Supermarket", "Cash", …: this keeps a future cloud sync free of duplicates.
String builtInId(String table, String slug) =>
    _uuid.v5(Namespace.url.value, 'daftar:$table:$slug');
