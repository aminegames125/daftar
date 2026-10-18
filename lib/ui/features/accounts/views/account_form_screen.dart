import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../domain/models/account.dart';
import '../../../../domain/models/ids.dart';
import '../../../../domain/models/money.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/floating_toast.dart';
import '../../../core/widgets/hold_to_confirm.dart';
import '../../../core/widgets/money_field.dart';
import '../../prices/views/widgets/form_bits.dart';
import '../../products/views/select_chip.dart';
import '../../settings/views/list_icons.dart';
import '../view_models/accounts_providers.dart';
import 'account_widgets.dart';

/// Create (no [accountId]) or edit an account: name, kind, currency, opening
/// balance, icon and include-in-totals. The currency is locked once the account
/// exists, because its transactions are stored in it.
class AccountFormScreen extends ConsumerStatefulWidget {
  const AccountFormScreen({super.key, this.accountId});

  final String? accountId;

  @override
  ConsumerState<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends ConsumerState<AccountFormScreen> {
  final _name = TextEditingController();
  final _opening = TextEditingController();

  Account? _existing;
  bool _loading = false;
  bool _saving = false;
  AccountKind _kind = AccountKind.cash;
  Currency _currency = Currency.tnd;
  String? _iconKey;
  bool _includeInTotals = true;
  String? _nameError;

  bool get _isEdit => widget.accountId != null;
  String get _icon => _iconKey ?? _kind.defaultIconKey;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    final a = await ref
        .read(accountActionsProvider)
        .getAccount(widget.accountId!);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _existing = a;
      if (a != null) {
        _name.text = a.name;
        _kind = a.kind;
        _currency = a.currency;
        _iconKey = a.iconKey;
        _includeInTotals = a.includeInTotals;
        _opening.text = a.openingBalanceMinor == 0
            ? ''
            : moneyInputText(a.openingBalance);
      }
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    super.dispose();
  }

  void _close() => context.canPop() ? context.pop() : context.go(Routes.home);

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Give the account a name');
      return;
    }
    setState(() {
      _nameError = null;
      _saving = true;
    });
    final opening =
        parseMoneyInput(_opening.text, currency: _currency)?.minor ?? 0;
    final base = _existing;
    final account = Account(
      id: base?.id ?? newId(),
      name: name,
      kind: _kind,
      currency: _currency,
      openingBalanceMinor: opening,
      includeInTotals: _includeInTotals,
      hideAmount: base?.hideAmount ?? false,
      sortOrder: base?.sortOrder ?? await _nextSortOrder(),
      iconKey: _icon,
    );
    try {
      await ref.read(accountActionsProvider).saveAccount(account);
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
    _close();
  }

  Future<int> _nextSortOrder() async {
    final accounts = ref.read(accountsProvider).value ?? const <Account>[];
    return accounts.isEmpty
        ? 0
        : accounts.map((a) => a.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
  }

  Future<void> _delete() async {
    final ok = await showHoldToConfirm(
      context,
      title: 'Delete ${_existing!.name}?',
      message:
          'The account and its transactions disappear from your lists. '
          'This cannot be undone here.',
      label: 'Hold to delete',
    );
    if (!ok || !mounted) return;
    await ref.read(accountActionsProvider).deleteAccount(_existing!.id);
    if (!mounted) return;
    // The detail page underneath notices the account is gone and closes itself.
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            AccountsHeader(title: _isEdit ? 'Edit account' : 'New account'),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(
                        Space.gutter,
                        Space.lg,
                        Space.gutter,
                        Space.xxl,
                      ),
                      children: [
                        const FieldLabel('Name'),
                        const SizedBox(height: Space.sm),
                        TextField(
                          controller: _name,
                          textDirection: null,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.next,
                          style: t.titleMedium,
                          onChanged: (_) {
                            if (_nameError != null) {
                              setState(() => _nameError = null);
                            }
                          },
                          decoration: boardInput(
                            context,
                            hint: 'Cash, Poste card, Flouci…',
                            errorText: _nameError,
                          ),
                        ),
                        const SizedBox(height: Space.xl),
                        const FieldLabel('Type'),
                        Wrap(
                          spacing: Space.sm,
                          children: [
                            for (final k in AccountKind.values)
                              SelectChip(
                                label: k.label,
                                selected: _kind == k,
                                onTap: () => setState(() => _kind = k),
                              ),
                          ],
                        ),
                        const SizedBox(height: Space.lg),
                        const FieldLabel('Currency'),
                        Wrap(
                          spacing: Space.sm,
                          children: [
                            for (final cur in Currency.values)
                              SelectChip(
                                label: cur.code,
                                selected: _currency == cur,
                                onTap: _isEdit
                                    ? null
                                    : () => setState(() {
                                        _currency = cur;
                                        _opening.clear();
                                      }),
                              ),
                          ],
                        ),
                        if (_isEdit)
                          Text(
                            'The currency cannot change after creation.',
                            style: t.bodySmall,
                          ),
                        const SizedBox(height: Space.xl),
                        MoneyField(
                          key: ValueKey(_currency),
                          controller: _opening,
                          currency: _currency,
                          label: 'Opening balance',
                          fontSize: 40,
                        ),
                        const SizedBox(height: Space.xl),
                        const FieldLabel('Icon'),
                        Wrap(
                          spacing: Space.sm,
                          children: [
                            for (final key in accountIconKeys)
                              SelectChip(
                                label: '',
                                semanticLabel: 'Icon $key',
                                icon: iconForKey(key),
                                selected: _icon == key,
                                onTap: () => setState(() => _iconKey = key),
                              ),
                          ],
                        ),
                        const SizedBox(height: Space.lg),
                        SwitchRow(
                          title: 'Include in totals',
                          hint: 'Leave savings out of what you can spend',
                          value: _includeInTotals,
                          bottomBorder: false,
                          onChanged: (v) =>
                              setState(() => _includeInTotals = v),
                        ),
                        if (_isEdit && _existing != null) ...[
                          const SizedBox(height: Space.xl),
                          HoldToConfirm(
                            label: 'Hold to delete account',
                            onConfirmed: _delete,
                          ),
                        ],
                      ],
                    ),
            ),
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
                  onPressed: _saving || _loading ? null : _save,
                  child: Text(_isEdit ? 'Save changes' : 'Create account'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
