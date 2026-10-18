import 'package:daftar/domain/models/account.dart';
import 'package:daftar/domain/models/money.dart';
import 'package:daftar/domain/use_cases/transaction_days.dart';
import 'package:flutter_test/flutter_test.dart';

AccountTransaction _tx(String id, DateTime at) => AccountTransaction(
  id: id,
  accountId: 'a',
  kind: TransactionKind.expense,
  amountMinor: 1000,
  currency: Currency.tnd,
  occurredAt: at,
);

void main() {
  test('groups by local day, newest day and newest transaction first', () {
    final days = groupTransactionsByDay([
      _tx('old', DateTime(2026, 10, 1, 9)),
      _tx('a', DateTime(2026, 10, 3, 8)),
      _tx('b', DateTime(2026, 10, 3, 20)),
      _tx('c', DateTime(2026, 10, 2, 12)),
    ]);
    expect(days.map((d) => d.day), [
      DateTime(2026, 10, 3),
      DateTime(2026, 10, 2),
      DateTime(2026, 10, 1),
    ]);
    expect(days.first.transactions.map((t) => t.id), ['b', 'a']);
  });

  test('empty list gives no groups', () {
    expect(groupTransactionsByDay(const []), isEmpty);
  });

  test('day headings', () {
    final now = DateTime(2026, 10, 17, 15);
    expect(dayHeading(DateTime(2026, 10, 17), now), 'Today');
    expect(dayHeading(DateTime(2026, 10, 16), now), 'Yesterday');
    expect(dayHeading(DateTime(2026, 10, 3), now), '3 Oct');
    expect(dayHeading(DateTime(2025, 12, 31), now), '31 Dec 2025');
  });
}
