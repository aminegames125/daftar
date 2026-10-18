import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../domain/models/account.dart';
import '../../../../../domain/models/money.dart';
import '../../../../../domain/use_cases/transfer_math.dart';
import '../../../../core/theme/daftar_colors.dart';
import '../../../../core/theme/daftar_tokens.dart';
import '../../../../core/widgets/money_field.dart';
import '../view_models/transfer_providers.dart';
import 'transfer_widgets.dart';

/// Opens the "Transfer" sheet: move money between two accounts of the same
/// currency, with an optional fee.
/// [accountId] pre-selects the account the money leaves. Resolves to true when saved.
Future<bool?> showTransferSheet(BuildContext context, {String? accountId}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => TransferSheet(accountId: accountId),
    );

class TransferSheet extends ConsumerStatefulWidget {
  const TransferSheet({super.key, this.accountId});

  final String? accountId;

  @override
  ConsumerState<TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends ConsumerState<TransferSheet> {
  String? _fromId;
  String? _toId;
  Money? _amount;
  Money? _fee;
  String _note = '';
  bool _saving = false;
  _Moved? _moved;
  bool _initialised = false;

  Account? _find(List<Account> all, String? id) {
    for (final a in all) {
      if (a.id == id) return a;
    }
    return null;
  }

  void _init(List<Account> all) {
    if (_initialised) return;
    _initialised = true;
    _fromId = _find(all, widget.accountId)?.id;
    _autoPickTo(all);
  }

  /// Keeps "to" valid: same currency, not the source. Picks it when it is the only choice.
  void _autoPickTo(List<Account> all) {
    final from = _find(all, _fromId);
    final candidates = _candidates(all, from);
    final current = _find(candidates, _toId);
    _toId =
        current?.id ?? (candidates.length == 1 ? candidates.first.id : null);
  }

  List<Account> _candidates(List<Account> all, Account? from) => from == null
      ? const []
      : [
          for (final a in all)
            if (a.id != from.id && a.currency == from.currency) a,
        ];

  Future<void> _save(Account from, Account to) async {
    final amount = _amount!.minor;
    final fee = _fee?.minor ?? 0;
    setState(() => _saving = true);
    unawaited(HapticFeedback.mediumImpact());
    final fromBefore = await ref.read(transferActionsProvider).balanceOf(from);
    final toBefore = await ref.read(transferActionsProvider).balanceOf(to);
    await ref
        .read(transferActionsProvider)
        .saveTransfer(
          from: from,
          to: to,
          amountMinor: amount,
          feeMinor: fee,
          note: _note.trim().isEmpty ? null : _note.trim(),
        );
    if (!mounted) return;
    setState(() {
      _moved = _Moved(
        fromName: from.name,
        toName: to.name,
        fromBefore: fromBefore,
        fromAfter: Money(fromBefore.minor - amount - fee, from.currency),
        toBefore: toBefore,
        toAfter: Money(toBefore.minor + amount, to.currency),
        chip: Money(amount, from.currency).formatWithCode(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(transferAccountsProvider);
    return accounts.when(
      loading: () => const SizedBox(
        height: Chrome.barHeight * 2,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const TransferSheetFrame(
        title: 'Transfer',
        children: [Text('Could not load your accounts.')],
      ),
      data: (all) {
        _init(all);
        final moved = _moved;
        if (moved != null) {
          return TransferSheetFrame(
            title: 'Transfer',
            children: [
              MoneyMoveAnimation(
                fromName: moved.fromName,
                toName: moved.toName,
                fromBefore: moved.fromBefore,
                fromAfter: moved.fromAfter,
                toBefore: moved.toBefore,
                toAfter: moved.toAfter,
                chipLabel: moved.chip,
                onDone: () => Navigator.of(context).maybePop(true),
              ),
            ],
          );
        }
        return _form(context, all);
      },
    );
  }

  Widget _form(BuildContext context, List<Account> all) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final from = _find(all, _fromId);
    final to = _find(all, _toId);
    final candidates = _candidates(all, from);
    final currency = from?.currency ?? Currency.tnd;
    final amountMinor = _amount?.minor ?? 0;
    final feeMinor = _fee?.minor ?? 0;
    final issue = validateTransfer(
      from: from,
      to: to,
      amountMinor: amountMinor,
      feeMinor: feeMinor,
    );
    final balance = from == null
        ? null
        : ref.watch(transferBalanceProvider(from.id)).value;
    final short =
        balance != null &&
        amountMinor > 0 &&
        isShort(
          balanceMinor: balance.minor,
          amountMinor: amountMinor,
          feeMinor: feeMinor,
        );

    return TransferSheetFrame(
      title: 'Transfer',
      subtitle: 'Move money between two accounts of the same currency.',
      children: [
        AccountChoiceRow(
          label: 'From',
          accounts: all,
          selectedId: _fromId,
          emptyHint: 'Add an account first.',
          onSelected: (a) => setState(() {
            if (from?.currency != a.currency) {
              // The amount fields are rebuilt for the new currency.
              _amount = null;
              _fee = null;
            }
            _fromId = a.id;
            _autoPickTo(all);
          }),
        ),
        const SizedBox(height: Space.lg),
        AccountChoiceRow(
          label: 'To',
          accounts: candidates,
          selectedId: _toId,
          emptyHint: from == null
              ? 'Pick the source first.'
              : 'No other ${from.currency.code} account to move money to.',
          onSelected: (a) => setState(() => _toId = a.id),
        ),
        const SizedBox(height: Space.lg),
        MoneyField(
          key: ValueKey('amount-${currency.code}'),
          label: 'Amount',
          currency: currency,
          fontSize: 40,
          onChanged: (m) => setState(() => _amount = m),
        ),
        if (balance != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(
              'Balance ${balance.formatWithCode()}',
              style: t.bodySmall,
            ),
          ),
        if (short)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Text(
              'This is more than the balance of ${from!.name}. You can still save it.',
              style: t.bodySmall?.copyWith(color: c.coral),
            ),
          ),
        const SizedBox(height: Space.lg),
        MoneyField(
          key: ValueKey('fee-${currency.code}'),
          label: 'Fee (optional)',
          currency: currency,
          fontSize: 24,
          onChanged: (m) => setState(() => _fee = m),
        ),
        const SizedBox(height: Space.md),
        TextField(
          textDirection: null,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (v) => _note = v,
          decoration: const InputDecoration(hintText: 'Note (optional)'),
        ),
        const SizedBox(height: Space.xl),
        if (issue != null && amountMinor > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Text(issue.message, style: t.bodySmall),
          ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: c.lime,
            foregroundColor: c.onLime,
            minimumSize: const Size.fromHeight(56),
            shape: const RoundedRectangleBorder(borderRadius: Radii.buttonR),
          ),
          onPressed: issue != null || _saving ? null : () => _save(from!, to!),
          child: const Text('Move money'),
        ),
      ],
    );
  }
}

class _Moved {
  const _Moved({
    required this.fromName,
    required this.toName,
    required this.fromBefore,
    required this.fromAfter,
    required this.toBefore,
    required this.toAfter,
    required this.chip,
  });
  final String fromName;
  final String toName;
  final Money fromBefore;
  final Money fromAfter;
  final Money toBefore;
  final Money toAfter;
  final String chip;
}
