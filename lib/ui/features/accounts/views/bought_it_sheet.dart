import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/routes/accounts_routes.dart';
import '../../../../domain/models/account.dart';
import '../../../../domain/models/money.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/money_field.dart';
import '../../products/view_models/catalog_providers.dart';
import '../../products/views/select_chip.dart';
import '../view_models/accounts_providers.dart';
import 'account_widgets.dart';

/// What a USD account is asked to pay for a TND price.
class UsdPaymentRequest {
  const UsdPaymentRequest({
    required this.account,
    required this.price,
    required this.priceEntryId,
    required this.at,
    this.note,
    this.categoryId,
  });

  /// The chosen USD account.
  final Account account;

  /// The TND price that was logged.
  final Money price;
  final String priceEntryId;
  final DateTime at;
  final String? note;
  final String? categoryId;
}

/// Hook for the foreign-currency flow: asks for the rate and fee, then
/// saves the USD expense. Returns true when it saved the expense.
typedef UsdPaymentHandler = Future<bool> Function(
  BuildContext context,
  UsdPaymentRequest request,
);

/// `onUsdPayment`: null until the foreign-currency flow overrides it. While it
/// is null, paying from a USD account just asks for the USD amount that was paid
/// and stores the expense in USD, with no conversion.
final onUsdPaymentProvider = Provider<UsdPaymentHandler?>((ref) => null);

/// The optional follow-up after saving a price: "I bought it" creates an
/// expense linked to the price entry. Resolves to true when an expense was saved.
Future<bool> showBoughtItSheet(
  BuildContext context, {
  required String priceEntryId,
  required Money price,
  required String title,
  String? categoryId,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => BoughtItSheet(
      priceEntryId: priceEntryId,
      price: price,
      title: title,
      categoryId: categoryId,
    ),
  );
  return saved ?? false;
}

class BoughtItSheet extends ConsumerStatefulWidget {
  const BoughtItSheet({
    super.key,
    required this.priceEntryId,
    required this.price,
    required this.title,
    this.categoryId,
  });

  final String priceEntryId;
  final Money price;
  final String title;
  final String? categoryId;

  @override
  ConsumerState<BoughtItSheet> createState() => _BoughtItSheetState();
}

class _BoughtItSheetState extends ConsumerState<BoughtItSheet> {
  final _amount = TextEditingController();
  String? _accountId;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _chooseDefault();
  }

  Future<void> _chooseDefault() async {
    final a = await ref.read(accountActionsProvider).defaultAccount();
    if (mounted && a != null) _select(a);
  }

  void _select(Account a) {
    setState(() {
      _accountId = a.id;
      _error = null;
      _amount.text = a.currency == widget.price.currency
          ? moneyInputText(widget.price)
          : '';
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save(Account account) async {
    final now = ref.read(clockProvider)();
    final hook = ref.read(onUsdPaymentProvider);
    if (account.currency == Currency.usd && hook != null) {
      final done = await hook(
        context,
        UsdPaymentRequest(
          account: account,
          price: widget.price,
          priceEntryId: widget.priceEntryId,
          at: now,
          note: widget.title,
          categoryId: widget.categoryId,
        ),
      );
      if (done && mounted) Navigator.of(context).pop(true);
      return;
    }
    final money = parseMoneyInput(_amount.text, currency: account.currency);
    if (money == null || money.minor <= 0) {
      setState(() => _error = 'Enter an amount above zero');
      return;
    }
    setState(() => _saving = true);
    final actions = ref.read(accountActionsProvider);
    try {
      await actions.recordPurchase(
        account: account,
        amountMinor: money.minor,
        at: now,
        priceEntryId: widget.priceEntryId,
        note: widget.title,
        categoryId: widget.categoryId,
      );
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save. Try again.';
        });
      }
      return;
    }
    unawaited(HapticFeedback.mediumImpact());
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    Account? account;
    for (final a in accounts) {
      if (a.id == _accountId) account = a;
    }
    final usd = account?.currency == Currency.usd;
    final hasHook = ref.watch(onUsdPaymentProvider) != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('I bought it', style: t.headlineSmall),
              const SizedBox(height: Space.xs),
              Text(
                'Pay for ${widget.title} from one of your accounts.',
                style: t.bodyMedium,
              ),
              const SizedBox(height: Space.lg),
              if (accounts.isEmpty) ...[
                Text('You have no accounts yet.', style: t.bodyMedium),
                const SizedBox(height: Space.md),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(Chrome.minTouch),
                  ),
                  onPressed: () {
                    Navigator.of(context).pop(false);
                    context.push(AccountsRoutes.newAccount);
                  },
                  child: const Text('Add an account'),
                ),
              ] else ...[
                Wrap(
                  spacing: Space.sm,
                  children: [
                    for (final a in accounts)
                      SelectChip(
                        label: '${a.name} · ${a.currency.code}',
                        icon: accountIcon(a),
                        selected: a.id == _accountId,
                        onTap: () => _select(a),
                      ),
                  ],
                ),
                const SizedBox(height: Space.md),
                if (account != null && !(usd && hasHook)) ...[
                  MoneyField(
                    key: ValueKey(account.currency),
                    controller: _amount,
                    currency: account.currency,
                    label: usd ? 'Paid in USD' : 'Amount',
                    fontSize: 40,
                    errorText: _error,
                  ),
                  if (usd)
                    Text(
                      'Price was ${widget.price.formatWithCode()}. Type what '
                      'you paid in USD; no conversion happens here.',
                      style: t.bodySmall,
                    ),
                ] else if (usd && hasHook)
                  Text(
                    'Next you will enter the rate and any fee.',
                    style: t.bodySmall,
                  ),
                const SizedBox(height: Space.lg),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: c.lime,
                    foregroundColor: c.onLime,
                    minimumSize: const Size.fromHeight(56),
                    shape: const RoundedRectangleBorder(
                      borderRadius: Radii.buttonR,
                    ),
                  ),
                  onPressed: _saving || account == null
                      ? null
                      : () => _save(account!),
                  child: Text(usd && hasHook ? 'Continue' : 'Save expense'),
                ),
              ],
              const SizedBox(height: Space.sm),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(Chrome.minTouch),
                ),
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Not now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
