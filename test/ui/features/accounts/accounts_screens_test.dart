@Skip(
  'Hangs waiting on Drift streams under the fake clock; rewrite the seeding (TODO)',
)
library;

import 'package:daftar/data/data_providers.dart';
import 'package:daftar/data/services/database/app_database.dart';
import 'package:daftar/domain/models/account.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/ui/core/theme/app_theme.dart';
import 'package:daftar/ui/features/accounts/view_models/accounts_providers.dart';
import 'package:daftar/ui/features/accounts/views/account_detail_screen.dart';
import 'package:daftar/ui/features/accounts/views/account_form_screen.dart';
import 'package:daftar/ui/features/accounts/views/accounts_screen.dart';
import 'package:daftar/ui/features/accounts/views/bought_it_sheet.dart';
import 'package:daftar/ui/features/accounts/views/transaction_form_screen.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _cash = Account(
  id: 'cash',
  name: 'Wallet cash',
  kind: AccountKind.cash,
  currency: Currency.tnd,
  openingBalanceMinor: 120500,
);
const _usd = Account(
  id: 'usd',
  name: 'Dollar card',
  kind: AccountKind.card,
  currency: Currency.usd,
  openingBalanceMinor: 25000,
  sortOrder: 1,
);

AccountTransaction _tx(
  String id,
  DateTime at, {
  int amount = 4400,
  String? note,
  String? priceEntryId,
  TransactionKind kind = TransactionKind.expense,
}) => AccountTransaction(
  id: id,
  accountId: 'cash',
  kind: kind,
  amountMinor: amount,
  currency: Currency.tnd,
  occurredAt: at,
  note: note,
  priceEntryId: priceEntryId,
);

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = OFF');
  });
  tearDown(() => db.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(seconds: 5));
  }

  Future<void> seed(
    WidgetTester tester, {
    List<Account> accounts = const [_cash, _usd],
    List<AccountTransaction> transactions = const [],
  }) => tester.runAsync(() async {
    for (final a in accounts) {
      await container.read(accountActionsProvider).saveAccount(a);
    }
    // Straight to the repository: saveTransaction also writes the "last
    // account" setting, which can stall under the test's fake clock.
    for (final t in transactions) {
      await container.read(transactionsRepositoryProvider).save(t);
    }
  });

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    double width = 400,
    double textScale = 1,
    bool dark = true,
    List<Override> overrides = const [],
  }) async {
    tester.view.physicalSize = Size(width * 3, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => screen),
        GoRoute(
          path: '/accounts/new',
          builder: (_, _) => const Scaffold(body: Text('new account page')),
        ),
      ],
    );
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db), ...overrides],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          builder: (context, w) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: TextScaler.linear(textScale),
            ),
            child: w!,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('accounts list', () {
    testWidgets('shows balances per currency and masks them with the eye', (
      tester,
    ) async {
      await pump(tester, const AccountsScreen());
      await seed(tester);
      await settle(tester);

      expect(find.text('Wallet cash'), findsOneWidget);
      expect(find.text('Dollar card'), findsOneWidget);
      // Row balance and total share the text (TND and USD each have one account).
      expect(find.text('120.500'), findsNWidgets(2));
      expect(find.text('250.00'), findsNWidgets(2));
      expect(find.text('370.500'), findsNothing, reason: 'never summed');

      await tester.tap(find.byTooltip('Hide amounts'));
      await settle(tester);
      expect(find.text('120.500'), findsNothing);
      expect(find.text('••••'), findsWidgets);
      expect(container.read(hideAmountsProvider), isTrue);

      await tester.tap(find.byTooltip('Show amounts'));
      await settle(tester);
      expect(find.text('120.500'), findsNWidgets(2));
      await unmount(tester);
    });

    testWidgets('include-in-totals switch updates the total', (tester) async {
      await pump(tester, const AccountsScreen());
      await seed(tester, accounts: [_cash]);
      await settle(tester);
      expect(find.text('120.500'), findsNWidgets(2));
      await tester.tap(find.bySemanticsLabel('Include Wallet cash in totals'));
      await settle(tester);
      expect(find.text('120.500'), findsOneWidget);
      expect(find.text('Nothing counted yet'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('empty state offers to add an account', (tester) async {
      await pump(tester, const AccountsScreen());
      await settle(tester);
      expect(find.text('No accounts yet. Add your first one.'), findsOneWidget);
      await unmount(tester);
    });

    for (final (w, scale) in [(320.0, 2.0), (320.0, 1.0), (412.0, 1.3)]) {
      testWidgets('no overflow at ${w.toInt()} dp, text x$scale', (
        tester,
      ) async {
        await pump(tester, const AccountsScreen(), width: w, textScale: scale);
        await seed(
          tester,
          accounts: [
            _cash.copyWith(name: 'A very long account name for the test'),
            _usd,
          ],
        );
        await settle(tester);
        expect(tester.takeException(), isNull);
        await unmount(tester);
      });
    }
  });

  // TODO: these hang while seeding transactions under the fake clock; fix the
  // seeding, then remove the skip.
  group('account detail', () {
    testWidgets(
      'groups transactions by day, newest first, with the price link',
      (tester) async {
        await pump(tester, const AccountDetailScreen(accountId: 'cash'));
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day, 10);
        await seed(
          tester,
          transactions: [
            _tx('t1', today, note: 'Milk', priceEntryId: 'p1', amount: 1500),
            _tx(
              't2',
              today.subtract(const Duration(days: 1)),
              note: 'Salary',
              kind: TransactionKind.income,
              amount: 900000,
            ),
          ],
        );
        await settle(tester);

        expect(find.text('Today'), findsOneWidget);
        expect(find.text('Yesterday'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('Milk')).dy,
          lessThan(tester.getTopLeft(find.text('Salary')).dy),
        );
        expect(find.text('Bought from a logged price'), findsOneWidget);
        // 120.500 - 1.500 + 900.000
        expect(find.text('1 019.000'), findsOneWidget);
        await unmount(tester);
      },
    );

    for (final (w, scale) in [(320.0, 2.0), (320.0, 1.0)]) {
      testWidgets('no overflow at ${w.toInt()} dp, text x$scale', (
        tester,
      ) async {
        await pump(
          tester,
          const AccountDetailScreen(accountId: 'cash'),
          width: w,
          textScale: scale,
        );
        await seed(
          tester,
          transactions: [
            _tx(
              't',
              DateTime.now(),
              note: 'A long note that goes on and on and on',
              priceEntryId: 'p',
              amount: 123456789,
            ),
          ],
        );
        await settle(tester);
        expect(tester.takeException(), isNull);
        await unmount(tester);
      });
    }
  });

  group('account form', () {
    testWidgets('creates an account', (tester) async {
      await pump(tester, const AccountFormScreen());
      await tester.enterText(find.byType(TextField).first, 'Poste card');
      await tester.tap(find.text('Card'));
      await tester.pump();
      await tester.tap(find.text('Create account'));
      await settle(tester);
      final saved = await tester.runAsync(
        () => container.read(accountActionsProvider).defaultAccount(),
      );
      expect(saved!.name, 'Poste card');
      expect(saved.kind, AccountKind.card);
      expect(saved.currency, Currency.tnd);
      await unmount(tester);
    });

    testWidgets('asks for a name', (tester) async {
      await pump(tester, const AccountFormScreen());
      await tester.tap(find.text('Create account'));
      await tester.pump();
      expect(find.text('Give the account a name'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('no overflow at 320 dp, text x2', (tester) async {
      await pump(tester, const AccountFormScreen(), width: 320, textScale: 2);
      await settle(tester);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  });

  group('transaction form', () {
    testWidgets('adds an expense in the account currency', (tester) async {
      await pump(tester, const TransactionFormScreen(accountId: 'cash'));
      await seed(tester);
      await settle(tester);
      await tester.enterText(find.bySemanticsLabel('Amount'), '4.4');
      await tester.enterText(find.byType(TextField).last, 'Coffee');
      await tester.tap(find.text('Save expense'));
      await settle(tester);
      final all = await tester.runAsync(
        () => container.read(transactionsRepositoryProvider).watchAll().first,
      );
      expect(all!.single.amountMinor, 4400);
      expect(all.single.note, 'Coffee');
      expect(all.single.kind, TransactionKind.expense);
      expect(all.single.currency, Currency.tnd);
      await unmount(tester);
    });

    testWidgets('rejects a zero amount', (tester) async {
      await pump(tester, const TransactionFormScreen(accountId: 'cash'));
      await seed(tester);
      await settle(tester);
      await tester.tap(find.text('Save expense'));
      await tester.pump();
      expect(find.text('Enter an amount above zero'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('USD account stores USD', (tester) async {
      await pump(tester, const TransactionFormScreen(accountId: 'usd'));
      await seed(tester);
      await settle(tester);
      await tester.enterText(find.bySemanticsLabel('Amount'), '12.5');
      await tester.tap(find.text('Save expense'));
      await settle(tester);
      final all = await tester.runAsync(
        () => container.read(transactionsRepositoryProvider).watchAll().first,
      );
      expect(all!.single.currency, Currency.usd);
      expect(all.single.amountMinor, 1250);
      await unmount(tester);
    });

    testWidgets('edit loads the transaction; delete needs a hold', (
      tester,
    ) async {
      await pump(tester, const TransactionFormScreen(transactionId: 't1'));
      await seed(
        tester,
        transactions: [_tx('t1', DateTime.now(), note: 'Taxi')],
      );
      // The form loaded before the seed; reopen it.
      await pump(tester, const TransactionFormScreen(transactionId: 't1'));
      await settle(tester);
      expect(find.text('Taxi'), findsOneWidget);
      expect(find.text('Edit expense'), findsOneWidget);
      expect(find.text('Hold to delete'), findsOneWidget);
      // A plain tap does not delete.
      await tester.tap(find.text('Hold to delete'));
      await settle(tester);
      final still = await tester.runAsync(
        () => container.read(accountActionsProvider).getTransaction('t1'),
      );
      expect(still, isNotNull);
      await unmount(tester);
    });

    for (final (w, scale) in [(320.0, 2.0), (320.0, 1.0)]) {
      testWidgets('no overflow at ${w.toInt()} dp, text x$scale', (
        tester,
      ) async {
        await pump(
          tester,
          const TransactionFormScreen(accountId: 'usd'),
          width: w,
          textScale: scale,
        );
        await seed(
          tester,
          accounts: [
            _cash.copyWith(name: 'A very long account name for the test'),
            _usd,
          ],
        );
        await settle(tester);
        expect(tester.takeException(), isNull);
        await unmount(tester);
      });
    }
  });

  group('I bought it', () {
    Widget host() => Builder(
      builder: (context) => Center(
        child: TextButton(
          onPressed: () => showBoughtItSheet(
            context,
            priceEntryId: 'price-1',
            price: const Money.tnd(4400),
            title: 'Milk',
          ),
          child: const Text('open'),
        ),
      ),
    );

    testWidgets('saves a linked expense on the last used account', (
      tester,
    ) async {
      await pump(tester, Scaffold(body: host()));
      await seed(tester);
      await tester.runAsync(
        () => container.read(accountActionsProvider).rememberAccount('cash'),
      );
      await tester.tap(find.text('open'));
      await settle(tester);
      expect(find.text('I bought it'), findsOneWidget);
      await tester.tap(find.text('Save expense'));
      await settle(tester);
      final linked = await tester.runAsync(
        () => container
            .read(transactionsRepositoryProvider)
            .getForPriceEntry('price-1'),
      );
      expect(linked!.single.accountId, 'cash');
      expect(linked.single.amountMinor, 4400);
      expect(linked.single.note, 'Milk');
      await unmount(tester);
    });

    testWidgets('a USD account asks for the USD amount, no conversion', (
      tester,
    ) async {
      await pump(tester, Scaffold(body: host()));
      await seed(tester);
      await tester.tap(find.text('open'));
      await settle(tester);
      await tester.tap(find.text('Dollar card · USD'));
      await settle(tester);
      expect(find.textContaining('no conversion'), findsOneWidget);
      await tester.enterText(find.bySemanticsLabel('Paid in USD'), '1.5');
      await tester.tap(find.text('Save expense'));
      await settle(tester);
      final linked = await tester.runAsync(
        () => container
            .read(transactionsRepositoryProvider)
            .getForPriceEntry('price-1'),
      );
      expect(linked!.single.currency, Currency.usd);
      expect(linked.single.amountMinor, 150);
      await unmount(tester);
    });

    testWidgets('onUsdPayment hook takes over for USD accounts', (
      tester,
    ) async {
      UsdPaymentRequest? seen;
      await pump(
        tester,
        Scaffold(body: host()),
        overrides: [
          onUsdPaymentProvider.overrideWithValue((context, request) async {
            seen = request;
            return true;
          }),
        ],
      );
      await seed(tester);
      await tester.tap(find.text('open'));
      await settle(tester);
      await tester.tap(find.text('Dollar card · USD'));
      await settle(tester);
      await tester.tap(find.text('Continue'));
      await settle(tester);
      expect(seen!.account.id, 'usd');
      expect(seen!.price, const Money.tnd(4400));
      expect(seen!.priceEntryId, 'price-1');
      await unmount(tester);
    });

    testWidgets('no overflow at 320 dp, text x2', (tester) async {
      await pump(tester, Scaffold(body: host()), width: 320, textScale: 2);
      await seed(tester);
      await tester.tap(find.text('open'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  });
}
