import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/debt.dart';
import '../../../../domain/models/money.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/money_field.dart';
import '../view_models/debt_actions.dart';
import '../view_models/debt_items.dart';

/// Opens the add-payment sheet. Resolves to true when the payment settled the
/// debt, false when it was a partial payment, null when dismissed.
Future<bool?> showAddPaymentSheet(BuildContext context, DebtItem item) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => AddPaymentSheet(item: item),
  );
}

class AddPaymentSheet extends ConsumerStatefulWidget {
  const AddPaymentSheet({super.key, required this.item});

  final DebtItem item;

  @override
  ConsumerState<AddPaymentSheet> createState() => _AddPaymentSheetState();
}

class _AddPaymentSheetState extends ConsumerState<AddPaymentSheet> {
  final _text = TextEditingController();
  bool _mirror = false;
  bool _canMirror = false;
  bool _showError = false;
  bool _busy = false;

  Debt get _debt => widget.item.debt;
  Money get _remaining => widget.item.remaining;

  @override
  void initState() {
    super.initState();
    ref.read(debtActionsProvider).canMirror(_debt).then((ok) {
      if (mounted) setState(() => _canMirror = ok);
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Money? get _amount => parseMoneyInput(_text.text, currency: _debt.currency);

  String? get _error {
    if (!_showError) return null;
    final a = _amount;
    if (a == null || a.minor <= 0) return 'Enter an amount';
    if (a.minor > _remaining.minor) {
      return 'More than the ${_remaining.formatWithCode()} left';
    }
    return null;
  }

  Future<void> _save() async {
    setState(() => _showError = true);
    if (_error != null || _busy) return;
    _busy = true;
    final settled = await ref
        .read(debtActionsProvider)
        .addPayment(widget.item, _amount!.minor, mirrorToAccount: _mirror);
    if (mounted) Navigator.of(context).pop(settled);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final income = _debt.direction != DebtDirection.iOwe;
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          Space.gutter,
          0,
          Space.gutter,
          Space.xl + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_debt.direction.paymentVerb, style: t.titleLarge),
            const SizedBox(height: Space.xs),
            Text('${_remaining.formatWithCode()} left', style: t.bodySmall),
            const SizedBox(height: Space.lg),
            MoneyField(
              controller: _text,
              currency: _debt.currency,
              label: 'Amount',
              fontSize: 40,
              autofocus: true,
              errorText: _error,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Space.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                label: const Text('Pay all'),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() => _text.text = moneyInputText(_remaining));
                },
              ),
            ),
            if (_debt.sourceAccountId != null) ...[
              const SizedBox(height: Space.md),
              MergeSemantics(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Also log in my account', style: t.titleSmall),
                          Text(
                            _canMirror
                                ? (income
                                      ? 'Adds an income to the source account.'
                                      : 'Adds an expense to the source account.')
                                : 'Needs a source account in ${_debt.currency.code}.',
                            style: t.bodySmall?.copyWith(color: c.muted),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _mirror && _canMirror,
                      onChanged: _canMirror
                          ? (v) => setState(() => _mirror = v)
                          : null,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: Space.xl),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: c.lime,
                foregroundColor: c.onLime,
                minimumSize: const Size.fromHeight(Chrome.minTouch),
                shape: const StadiumBorder(),
              ),
              onPressed: () {
                HapticFeedback.mediumImpact();
                _save();
              },
              child: const Text('Add payment'),
            ),
          ],
        ),
      ),
    );
  }
}
