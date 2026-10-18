import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../domain/models/debt.dart';
import '../../../../domain/models/ids.dart';
import '../../../../domain/models/money.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/daftar_action_bar.dart';
import '../../../core/widgets/money_field.dart';
import '../view_models/debt_actions.dart';
import '../view_models/debt_items.dart';

/// Add or edit a debt: person, direction, amount, currency, note, due date and
/// an optional source account.
class DebtFormScreen extends ConsumerStatefulWidget {
  const DebtFormScreen({super.key, this.debtId});

  /// Null = add a new debt.
  final String? debtId;

  @override
  ConsumerState<DebtFormScreen> createState() => _DebtFormScreenState();
}

class _DebtFormScreenState extends ConsumerState<DebtFormScreen> {
  final _name = TextEditingController();
  final _note = TextEditingController();
  final _amountText = TextEditingController();
  DebtDirection _direction = DebtDirection.owedToMe;
  Currency _currency = Currency.tnd;
  DateTime? _due;
  String? _accountId;
  bool _filled = false;
  bool _saving = false;
  bool _showErrors = false;

  bool get _editing => widget.debtId != null;

  @override
  void initState() {
    super.initState();
    if (_editing) {
      ref.listenManual(debtItemProvider(widget.debtId!), (_, next) {
        final item = next.value;
        if (item == null || _filled) return;
        _filled = true;
        final d = item.debt;
        setState(() {
          _name.text = d.name;
          _note.text = d.note ?? '';
          _direction = d.direction;
          _currency = d.currency;
          _due = d.dueAt;
          _accountId = d.sourceAccountId;
          _amountText.text = moneyInputText(d.amount);
        });
      }, fireImmediately: true);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    _amountText.dispose();
    super.dispose();
  }

  Money? get _amount => parseMoneyInput(_amountText.text, currency: _currency);

  bool get _valid => _name.text.trim().isNotEmpty && (_amount?.minor ?? 0) > 0;

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _due ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 20),
    );
    if (picked != null && mounted) setState(() => _due = picked);
  }

  Future<void> _save() async {
    setState(() => _showErrors = true);
    if (!_valid || _saving) return;
    _saving = true;
    final note = _note.text.trim();
    await ref
        .read(debtActionsProvider)
        .save(
          Debt(
            id: widget.debtId ?? newId(),
            name: _name.text.trim(),
            direction: _direction,
            amountMinor: _amount!.minor,
            currency: _currency,
            note: note.isEmpty ? null : note,
            dueAt: _due,
            sourceAccountId: _accountId,
          ),
        );
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final accounts = (ref.watch(debtAccountsProvider).value ?? const [])
        .where((a) => a.currency == _currency)
        .toList();
    return Scaffold(
      extendBody: true,
      appBar: AppBar(title: Text(_editing ? 'Edit debt' : 'Add debt')),
      bottomNavigationBar: DaftarActionBar(
        actions: const [],
        primary: ToolbarAction(
          icon: Icons.check_rounded,
          label: 'Save',
          onTap: _save,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.sm,
          Space.gutter,
          Chrome.contentBottomPadding,
        ),
        children: [
          Text('Direction', style: t.bodySmall),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final d in DebtDirection.values)
                ChoiceChip(
                  label: Text(d.label),
                  selected: _direction == d,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    setState(() => _direction = d);
                  },
                ),
            ],
          ),
          const SizedBox(height: Space.xl),
          TextField(
            controller: _name,
            textDirection: null,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: _direction.personLabel,
              errorText: _showErrors && _name.text.trim().isEmpty
                  ? 'Enter a name'
                  : null,
            ),
          ),
          const SizedBox(height: Space.xl),
          Text('Currency', style: t.bodySmall),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.sm,
            children: [
              for (final cur in Currency.values)
                ChoiceChip(
                  label: Text(cur.code),
                  selected: _currency == cur,
                  onSelected: (_) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _currency = cur;
                      _accountId = null;
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: Space.md),
          MoneyField(
            key: ValueKey(_currency),
            controller: _amountText,
            currency: _currency,
            label: 'Amount',
            fontSize: 40,
            onChanged: (_) => setState(() {}),
            errorText: _showErrors && (_amount?.minor ?? 0) <= 0
                ? 'Enter an amount'
                : null,
          ),
          const SizedBox(height: Space.xl),
          TextField(
            controller: _note,
            textDirection: null,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          const SizedBox(height: Space.lg),
          Text('Due date', style: t.bodySmall),
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              ActionChip(
                avatar: const Icon(Icons.event_outlined, size: 18),
                label: Text(
                  _due == null
                      ? 'Pick a date'
                      : MaterialLocalizations.of(context)
                            .formatMediumDate(_due!),
                ),
                onPressed: _pickDue,
              ),
              if (_due != null)
                ActionChip(
                  avatar: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('No due date'),
                  onPressed: () => setState(() => _due = null),
                ),
            ],
          ),
          const SizedBox(height: Space.xl),
          Text(
            _direction == DebtDirection.iOweMyself
                ? 'Savings account (optional)'
                : 'Account (optional)',
            style: t.bodySmall,
          ),
          const SizedBox(height: Space.sm),
          if (accounts.isEmpty)
            Text(
              'No ${_currency.code} accounts yet.',
              style: t.bodySmall?.copyWith(color: c.muted),
            )
          else
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                ChoiceChip(
                  label: const Text('None'),
                  selected: _accountId == null,
                  onSelected: (_) => setState(() => _accountId = null),
                ),
                for (final a in accounts)
                  ChoiceChip(
                    label: Text(a.name),
                    selected: _accountId == a.id,
                    onSelected: (_) => setState(() => _accountId = a.id),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
