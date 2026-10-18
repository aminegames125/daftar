import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../../../domain/backup/csv.dart';
import '../database/app_database.dart';

/// The backup file could not be read or must not be restored. [message] is safe
/// to show to the owner.
class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Quick facts about a backup, shown in the confirm-before-overwrite dialog.
class BackupSummary {
  const BackupSummary({
    required this.schemaVersion,
    required this.exportedAt,
    required this.rowCounts,
  });

  final int schemaVersion;
  final DateTime? exportedAt;
  final Map<String, int> rowCounts;

  int get totalRows => rowCounts.values.fold(0, (a, b) => a + b);
}

/// Whole-database export / import as one JSON file plus CSV exports.
///
/// Rows are copied as raw SQL values (integers stay integers, so money never
/// passes through a `double`). Photo *files* are not included, only their paths.
class BackupService {
  BackupService(this._db);

  final AppDatabase _db;

  static const formatId = 'daftar-backup';
  static const formatVersion = 1;

  static final _columnName = RegExp(r'^[A-Za-z0-9_]+$');

  List<String> get _tableNames => [
    for (final t in _db.allTables) t.actualTableName,
  ];

  /// Serialises every row (soft-deleted ones too, so sync stays correct).
  Future<String> exportJson() async {
    final tables = <String, Object?>{};
    for (final name in _tableNames) {
      final rows = await _db.customSelect('SELECT * FROM "$name"').get();
      tables[name] = [for (final r in rows) _encodeRow(r.data)];
    }
    return jsonEncode({
      'format': formatId,
      'formatVersion': formatVersion,
      'schemaVersion': _db.schemaVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'tables': tables,
    });
  }

  /// Parses and checks [json] without touching any database.
  /// Throws [BackupException] for anything that should not be restored.
  BackupSummary inspect(String json) => _summary(_parse(json));

  BackupSummary _summary(Map<String, dynamic> doc) {
    final tables = doc['tables'] as Map<String, dynamic>;
    return BackupSummary(
      schemaVersion: doc['schemaVersion'] as int,
      exportedAt: DateTime.tryParse(doc['exportedAt'] as String? ?? ''),
      rowCounts: {
        for (final e in tables.entries) e.key: (e.value as List).length,
      },
    );
  }

  /// Replaces all data with the backup. The backup is first restored into a
  /// throw-away in-memory database; only if that succeeds is the real database
  /// changed, inside one transaction that rolls back on any error. On failure
  /// the existing data is untouched and a [BackupException] is thrown.
  Future<BackupSummary> restoreJson(String json) async {
    final doc = _parse(json);

    final scratch = AppDatabase(NativeDatabase.memory());
    try {
      await BackupService(scratch)._apply(doc);
    } catch (_) {
      throw const BackupException(
        'This backup is damaged or does not fit this version of Daftar. Nothing was changed.',
      );
    } finally {
      await scratch.close();
    }

    try {
      await _apply(doc);
    } catch (_) {
      throw const BackupException(
        'Restoring failed. Your existing data was not changed.',
      );
    }
    return _summary(doc);
  }

  Future<void> _apply(Map<String, dynamic> doc) async {
    final tables = doc['tables'] as Map<String, dynamic>;
    await _db.transaction(() async {
      // Foreign keys are checked at commit, so insert order does not matter.
      await _db.customStatement('PRAGMA defer_foreign_keys = ON');
      for (final name in _tableNames.reversed) {
        await _db.customStatement('DELETE FROM "$name"');
      }
      for (final name in _tableNames) {
        final rows = (tables[name] as List?) ?? const [];
        for (final raw in rows) {
          final row = _decodeRow(raw as Map<String, dynamic>);
          if (row.isEmpty) continue;
          final cols = row.keys.map((c) => '"$c"').join(',');
          final marks = List.filled(row.length, '?').join(',');
          await _db.customInsert(
            'INSERT INTO "$name" ($cols) VALUES ($marks)',
            variables: [for (final v in row.values) _variable(v)],
          );
        }
      }
      final violations = await _db
          .customSelect('PRAGMA foreign_key_check')
          .get();
      if (violations.isNotEmpty) {
        throw const BackupException('The backup refers to missing rows.');
      }
    });
  }

  Map<String, dynamic> _parse(String json) {
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException {
      throw const BackupException('This is not a Daftar backup file.');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != formatId ||
        decoded['schemaVersion'] is! int ||
        decoded['tables'] is! Map<String, dynamic>) {
      throw const BackupException('This is not a Daftar backup file.');
    }
    final version = decoded['schemaVersion'] as int;
    if (version > _db.schemaVersion) {
      throw const BackupException(
        'This backup was made by a newer version of Daftar. Update the app, then try again.',
      );
    }
    if (version < 1) {
      throw const BackupException('This is not a Daftar backup file.');
    }
    final known = _tableNames.toSet();
    final tables = decoded['tables'] as Map<String, dynamic>;
    for (final e in tables.entries) {
      if (!known.contains(e.key) || e.value is! List) {
        throw const BackupException('This backup has unexpected contents.');
      }
    }
    return decoded;
  }

  Map<String, Object?> _encodeRow(Map<String, Object?> data) => {
    for (final e in data.entries)
      e.key: e.value is Uint8List
          ? {r'$b64': base64Encode(e.value! as Uint8List)}
          : e.value,
  };

  Map<String, Object?> _decodeRow(Map<String, dynamic> row) {
    final out = <String, Object?>{};
    for (final e in row.entries) {
      if (!_columnName.hasMatch(e.key)) {
        throw const BackupException('This backup has unexpected contents.');
      }
      final v = e.value;
      out[e.key] = v is Map ? base64Decode(v[r'$b64'] as String) : v;
    }
    return out;
  }

  Variable _variable(Object? v) => switch (v) {
    null => const Variable<Object>(null),
    final int i => Variable<int>(i),
    final double d => Variable<double>(d),
    final String s => Variable<String>(s),
    final Uint8List b => Variable<Uint8List>(b),
    final bool b => Variable<int>(b ? 1 : 0),
    _ => throw const BackupException('This backup has unexpected contents.'),
  };

  // --- CSV ---------------------------------------------------------------

  /// Every logged price, oldest first. Amounts are exact decimals.
  Future<String> priceHistoryCsv() async {
    final rows = await _db.customSelect('''
      SELECT pe.seen_at, p.name AS product, v.name AS variant, mi.name AS menu_item,
             mo.name AS menu_option, pl.name AS place, gt.name AS global_type,
             pe.amount_minor, pe.amount_max_minor, pe.currency, pe.is_promo,
             pe.promo_ends_at, pe.note
      FROM price_entries pe
      LEFT JOIN variants v ON v.id = pe.variant_id
      LEFT JOIN products p ON p.id = v.product_id
      LEFT JOIN menu_item_options mo ON mo.id = pe.menu_option_id
      LEFT JOIN menu_items mi ON mi.id = mo.menu_item_id
      LEFT JOIN places pl ON pl.id = pe.place_id
      LEFT JOIN global_price_types gt ON gt.id = pe.global_type_id
      WHERE pe.deleted_at IS NULL
      ORDER BY pe.seen_at, pe.id
    ''').get();
    return encodeCsv([
      const [
        'date',
        'product',
        'variant',
        'menu_item',
        'menu_option',
        'place',
        'global_type',
        'amount',
        'amount_max',
        'currency',
        'promo',
        'promo_ends',
        'note',
      ],
      for (final r in rows) _priceRow(r),
    ]);
  }

  List<String> _priceRow(QueryRow r) {
    final cur = currencyFromText(r.read<String?>('currency'));
    final max = r.read<int?>('amount_max_minor');
    return [
      isoFromMillis(r.read<int?>('seen_at')),
      r.read<String?>('product') ?? '',
      r.read<String?>('variant') ?? '',
      r.read<String?>('menu_item') ?? '',
      r.read<String?>('menu_option') ?? '',
      r.read<String?>('place') ?? '',
      r.read<String?>('global_type') ?? '',
      plainAmount(r.read<int>('amount_minor'), cur),
      max == null ? '' : plainAmount(max, cur),
      cur.code,
      r.read<int>('is_promo') == 1 ? 'yes' : 'no',
      isoFromMillis(r.read<int?>('promo_ends_at')),
      r.read<String?>('note') ?? '',
    ];
  }

  /// Every account transaction, oldest first.
  Future<String> transactionsCsv() async {
    final rows = await _db.customSelect('''
      SELECT t.occurred_at, a.name AS account, t.kind, t.amount_minor, t.currency,
             c.name AS category, t.note, t.fee_minor, t.rate_ten_thousandths
      FROM transactions t
      LEFT JOIN accounts a ON a.id = t.account_id
      LEFT JOIN categories c ON c.id = t.category_id
      WHERE t.deleted_at IS NULL
      ORDER BY t.occurred_at, t.id
    ''').get();
    return encodeCsv([
      const [
        'date',
        'account',
        'kind',
        'amount',
        'currency',
        'category',
        'note',
        'fee',
        'rate_tnd_per_usd',
      ],
      for (final r in rows) _transactionRow(r),
    ]);
  }

  List<String> _transactionRow(QueryRow r) {
    final cur = currencyFromText(r.read<String?>('currency'));
    final fee = r.read<int?>('fee_minor');
    final rate = r.read<int?>('rate_ten_thousandths');
    return [
      isoFromMillis(r.read<int?>('occurred_at')),
      r.read<String?>('account') ?? '',
      r.read<String?>('kind') ?? '',
      plainAmount(r.read<int>('amount_minor'), cur),
      cur.code,
      r.read<String?>('category') ?? '',
      r.read<String?>('note') ?? '',
      fee == null ? '' : plainAmount(fee, cur),
      // Rate is stored x 10 000: 3.1250 TND per USD -> 31250.
      rate == null
          ? ''
          : '${rate ~/ 10000}.${(rate % 10000).toString().padLeft(4, '0')}',
    ];
  }
}
