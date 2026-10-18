import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/routes/accounts_routes.dart';
import '../../../../domain/models/account.dart';
import '../../../../domain/models/ids.dart';
import '../../../../domain/models/lookups.dart';
import '../../../../domain/models/money.dart';
import '../../../../domain/use_cases/relative_time.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/floating_toast.dart';
import '../../../core/widgets/hold_to_confirm.dart';
import '../../../core/widgets/money_field.dart';
import '../../prices/views/widgets/form_bits.dart';
import '../../products/view_models/catalog_providers.dart';
import '../../products/views/select_chip.dart';
import '../view_models/accounts_providers.dart';
import 'account_widgets.dart';

/// Add (no [transactionId]) or edit an expense / income on an account. The
/// amount is typed in the chosen account's currency, which the transaction keeps.
/// Deleting needs a hold-to-confirm and is a soft delete.
class TransactionFormScreen extends ConsumerStatefulWidget {
  const TransactionFormScreen({
    super.key,
    this.transactionId,
    this.accountId,
    this.initialKind = TransactionKind.expense,
  });

  final String? transactionId;

  /// Pre-selects an account when adding.
  final String? accountId;
  final TransactionKind initialKind;

  @override
  ConsumerState<TransactionFormScreen> createState() =>
      _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();

  AccountTransaction? _existing;
  bool _loading = false;
  bool _saving = false;
  late TransactionKind _kind;
  String? _accountId;
  String? _categoryId;
  late DateTime _date;
  String? _amountError;

  bool get _isEdit => widget.transactionId != null;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind.isEditableKind
        ? widget.initialKind
        : TransactionKind.expense;
    _date = DateTime.now();
    _accountId = widget.accountId;
    if (_isEdit) {
      _loading = true;
      _loadExisting();
    } else if (_accountId == null) {
      _pickDefaultAccount();
    }
  }

  Future<void> _loadExisting() async {
    final tx = await ref
        .read(accountActionsProvider)
        .getTransaction(widget.transactionId!);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _existing = tx;
      if (tx != null) {
        _kind = tx.kind;
        _accountId = tx.accountId;
        _categoryId = tx.categoryId;
        _date = tx.occurredAt;
        _note.text = tx.note ?? '';
        _amount.text = moneyInputText(tx.amount);
      }
    });
  }

  Future<void> _pickDefaultAccount() async {
    final a = await ref.read(accountActionsProvider).defaultAccount();
    if (mounted && a != null && _accountId == null) {
      setState(() => _accountId = a.id);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _close() => context.canPop() ? context.pop() : context.go(Routes.home);

  Account? _account(List<Account> accounts) {
    for (final a in accounts) {
      if (a.id == _accountId) return a;
    }
    return null;
  }

  Future<void> _pickDate() async {
    final now = ref.read(clockProvider)();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(now) ? now : _date,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      helpText: 'Date',
    );
    if (picked == null || !mounted) return;
    setState(
      () => _date = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _date.hour,
        _date.minute,
      ),
    );
  }

  Future<void> _save(Account account) async {
    final money = parseMoneyInput(_amount.text, currency: account.currency);
    if (money == null || money.minor <= 0) {
      setState(() => _amountError = 'Enter an amount above zero');
      return;
    }
    setState(() {
      _amountError = null;
      _saving = true;
    });
    final base = _existing;
    final note = _note.text.trim();
    final tx = AccountTransaction(
      id: base?.id ?? newId(),
      accountId: account.id,
      kind: _kind,
      amountMinor: money.minor,
      currency: account.currency,
      occurredAt: _date,
      categoryId: _categoryId,
      note: note.isEmpty ? null : note,
      priceEntryId: base?.priceEntryId,
    );
    try {
      await ref.read(accountActionsProvider).saveTransaction(tx);
    } on Object {
      if (mounted) {
        setState(() => _saving = false);
        FloatingToast.show(
          context,
          'Could not save. Try again.',
          kind: ToastKind.error,
        );
      }
      return;
    }
    if (!mounted) return;
    unawaited(HapticFeedback.mediumImpact());
    FloatingToast.show(
      context,
      _kind == TransactionKind.income ? 'Income saved' : 'Expense saved',
      subtitle: money.formatWithCode(),
      kind: ToastKind.success,
    );
    _close();
  }

  Future<void> _delete() async {
    final ok = await showHoldToConfirm(
      context,
      title:
          'Delete this ${_kind == TransactionKind.income ? 'income' : 'expense'}?',
      message: 'It disappears from the account and its balance changes.',
      label: 'Hold to delete',
    );
    if (!ok || !mounted) return;
    await ref.read(accountActionsProvider).deleteTransaction(_existing!.id);
    if (mounted) _close();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider);
    final list = accounts.value ?? const <Account>[];
    final account = _account(list);
    final c = context.colors;
    final isIncome = _kind == TransactionKind.income;

    Widget body;
    if (_loading || (!accounts.hasValue && !accounts.hasError)) {
      body = const Center(child: CircularProgressIndicator());
    } else if (list.isEmpty) {
      body = Center(
        child: EmptyState(
          message: 'Add an account first, then log what you spend.',
          actionLabel: 'Add account',
          onAction: () => context.push(AccountsRoutes.newAccount),
        ),
      );
    } else if (_isEdit && _existing == null) {
      body = const Center(
        child: EmptyState(message: 'This transaction is gone.'),
      );
    } else {
      body = _form(context, list, account);
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            AccountsHeader(
              title: _isEdit
                  ? (isIncome ? 'Edit income' : 'Edit expense')
                  : 'New transaction',
            ),
            Expanded(child: body),
            if (list.isNotEmpty && !_loading)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.gutter,
                  Space.sm,
                  Space.gutter,
                  Chrome.barBottom,
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.lime,
                      foregroundColor: c.onLime,
                      shape: const RoundedRectangleBorder(
                        borderRadius: Radii.buttonR,
                      ),
                    ),
                    onPressed: _saving || account == null
                        ? null
                        : () => _save(account),
                    child: Text(isIncome ? 'Save income' : 'Save expense'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _form(BuildContext context, List<Account> accounts, Account? account) {
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];
    final currency = account?.currency ?? Currency.tnd;
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.sm,
        Space.gutter,
        Space.xxl,
      ),
      children: [
        Wrap(
          spacing: Space.sm,
          children: [
            SelectChip(
              label: 'Expense',
              selected: _kind == TransactionKind.expense,
              onTap: () => setState(() => _kind = TransactionKind.expense),
            ),
            SelectChip(
              label: 'Income',
              selected: _kind == TransactionKind.income,
              onTap: () => setState(() => _kind = TransactionKind.income),
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        MoneyField(
          key: ValueKey(currency),
          controller: _amount,
          currency: currency,
          label: 'Amount',
          autofocus: !_isEdit,
          errorText: _amountError,
          onChanged: (_) {
            if (_amountError != null) setState(() => _amountError = null);
          },
        ),
        const SizedBox(height: Space.xl),
        const FieldLabel('Account'),
        Wrap(
          spacing: Space.sm,
          children: [
            for (final a in accounts)
              SelectChip(
                label: '${a.name} · ${a.currency.code}',
                icon: accountIcon(a),
                selected: a.id == _accountId,
                onTap: () => setState(() => _accountId = a.id),
              ),
          ],
        ),
        if (currency == Currency.usd)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(
              'Paid in USD. It is stored in USD, with no conversion.',
              style: t.bodySmall,
            ),
          ),
        const SizedBox(height: Space.lg),
        const FieldLabel('Category', optional: true),
        Wrap(
          spacing: Space.sm,
          children: [
            for (final cat in categories)
              SelectChip(
                label: cat.name,
                selected: cat.id == _categoryId,
                onTap: () => setState(
                  () => _categoryId = cat.id == _categoryId ? null : cat.id,
                ),
              ),
          ],
        ),
        const SizedBox(height: Space.lg),
        const FieldLabel('Date'),
        const SizedBox(height: Space.xs),
        Semantics(
          button: true,
          label: 'Change date',
          excludeSemantics: true,
          child: InkWell(
            borderRadius: Radii.inputR,
            onTap: _pickDate,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Chrome.minTouch),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      shortDate(_date, ref.read(clockProvider)()),
                      style: t.titleMedium,
                    ),
                  ),
                  Icon(Icons.calendar_today_outlined, size: 18, color: c.muted),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.lg),
        const FieldLabel('Note', optional: true),
        const SizedBox(height: Space.sm),
        TextField(
          controller: _note,
          textDirection: null,
          textCapitalization: TextCapitalization.sentences,
          maxLines: 2,
          minLines: 1,
          style: t.bodyLarge,
          decoration: boardInput(context, hint: 'Lunch, taxi, salary…'),
        ),
        if (_isEdit && _existing != null) ...[
          const SizedBox(height: Space.xl),
          HoldToConfirm(label: 'Hold to delete', onConfirmed: _delete),
        ],
      ],
    );
  }
}

extension on TransactionKind {
  bool get isEditableKind =>
      this == TransactionKind.expense || this == TransactionKind.income;
}
