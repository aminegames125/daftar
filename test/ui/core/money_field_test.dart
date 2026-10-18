import 'package:daftar/domain/models/money.dart';
import 'package:daftar/ui/core/theme/app_theme.dart';
import 'package:daftar/ui/core/widgets/money_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {ThemeData? theme}) => MaterialApp(
  theme: theme ?? AppTheme.dark(),
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(20), child: child),
  ),
);

void main() {
  group('helpers', () {
    test('moneyInputText has no grouping and keeps 3 decimals', () {
      expect(moneyInputText(const Money.tnd(1284650)), '1284.650');
      expect(moneyInputText(const Money.tnd(4400)), '4.400');
      expect(moneyInputText(const Money.tnd(50)), '0.050');
    });

    test('parseMoneyInput tolerates a trailing separator and commas', () {
      expect(parseMoneyInput('4,'), const Money.tnd(4000));
      expect(parseMoneyInput('4.4'), const Money.tnd(4400));
      expect(parseMoneyInput('4,400'), const Money.tnd(4400));
      expect(parseMoneyInput(''), isNull);
      expect(parseMoneyInput('.'), isNull);
    });
  });

  group('MoneyField', () {
    testWidgets('accepts a comma, reports Money and formats on blur', (
      tester,
    ) async {
      Money? last;
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        host(
          MoneyField(
            focusNode: focus,
            label: 'Price',
            onChanged: (m) => last = m,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '4,4');
      expect(last, const Money.tnd(4400));
      expect(find.text('4,4'), findsOneWidget);

      focus.requestFocus();
      await tester.pump();
      focus.unfocus();
      await tester.pump();
      expect(find.text('4.400'), findsOneWidget);
      expect(last, const Money.tnd(4400));
    });

    testWidgets('rejects letters, a second separator and a 4th decimal', (
      tester,
    ) async {
      await tester.pumpWidget(host(const MoneyField()));
      final field = find.byType(TextField);

      await tester.enterText(field, '4.4');
      await tester.enterText(field, '4.4x');
      expect(find.text('4.4'), findsOneWidget);
      await tester.enterText(field, '4.4.1');
      expect(find.text('4.4'), findsOneWidget);
      await tester.enterText(field, '4.4001');
      expect(find.text('4.4'), findsOneWidget);
    });

    testWidgets('converts Arabic-Indic digits', (tester) async {
      Money? last;
      await tester.pumpWidget(host(MoneyField(onChanged: (m) => last = m)));
      await tester.enterText(find.byType(TextField), '٤٫٤');
      expect(last, const Money.tnd(4400));
    });

    testWidgets('shows the initial value and the currency code', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const MoneyField(initialValue: Money.tnd(12500))),
      );
      expect(find.text('12.500'), findsOneWidget);
      expect(find.text('TND'), findsOneWidget);
    });

    testWidgets('empty input reports null', (tester) async {
      Money? last = const Money.tnd(1);
      await tester.pumpWidget(
        host(
          MoneyField(
            initialValue: const Money.tnd(1000),
            onChanged: (m) => last = m,
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '');
      expect(last, isNull);
    });

    testWidgets('calculator button only when a hook is given and calls it', (
      tester,
    ) async {
      await tester.pumpWidget(host(const MoneyField(label: 'Price')));
      expect(find.bySemanticsLabel('Open calculator'), findsNothing);

      var taps = 0;
      await tester.pumpWidget(
        host(MoneyField(label: 'Price', onCalculator: () => taps++)),
      );
      await tester.tap(find.bySemanticsLabel('Open calculator'));
      expect(taps, 1);
    });

    testWidgets('renders in the light theme and shows an error', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          const MoneyField(errorText: 'Enter a price'),
          theme: AppTheme.light(),
        ),
      );
      expect(find.text('Enter a price'), findsOneWidget);
    });
  });
}
