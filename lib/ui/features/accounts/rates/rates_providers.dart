import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/data_providers.dart';
import '../../../../domain/models/account.dart';

/// Every saved USD/TND rate, newest first.
final rateEntriesProvider = StreamProvider<List<RateEntry>>(
  (ref) => ref.watch(rateEntriesRepositoryProvider).watchAll(),
);

/// The most recent saved rate, or null when none exists yet.
final latestRateProvider = StreamProvider<RateEntry?>(
  (ref) => ref.watch(rateEntriesRepositoryProvider).watchLatest(),
);
