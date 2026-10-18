import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../domain/models/account.dart';
import '../../../../../domain/models/money.dart';
import '../../../../../domain/use_cases/transfer_math.dart';
import '../../../../core/theme/daftar_colors.dart';
import '../../../../core/theme/daftar_tokens.dart';
import '../../../../core/theme/daftar_typography.dart';
import '../../../../core/widgets/money_field.dart';
import '../view_models/transfer_providers.dart';
import 'transfer_widgets.dart';

/// Opens the "Exchange" sheet: TND <-> USD with a rate (prefilled from the latest
/// saved one), an optional fee, and the effective rate shown live. [accountId]
/// pre-selects the account the money leaves. Resolves to true when saved.
Future<bool?> showExchangeSheet(BuildContext context, {String? accountId}) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ExchangeSheet(accountId: accountId),
    );

class ExchangeSheet extends ConsumerStatefulWidget {
  const ExchangeSheet({super.key, this.accountId});

  final String? accountId;

  @override
  ConsumerState<ExchangeSheet> createState() => _ExchangeSheetState();
}

class _ExchangeSheetState extends ConsumerState<ExchangeSheet> {
  final _rateController = TextEditingController();
  String? _fromId;
  String? _toId;
  Money? _amount;
  Money? _fee;
  String _note = '';
  bool _rateTouched = false;
  bool _saving = false;
  bool _initialised = false;
  int? _latestRate;
  _Exchanged? _done;

  @override
  void initState() {
    super.initState();
    ref.listenManual(latestRateProvider, (_, next) {
      final rate = next.value?.tndPerUsdTenThousandths;
      _latestRate = rate;
      if (rate != null && !_rateTouched && _rateController.text.isEmpty) {
        setState(() => _rateController.text = formatRate(rate));
      }
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }

  Account? _find(List<Account> all, String? id) {
    for (final a in all) {
      if (a.id == id) return a;
    }
    return null;
  }

  List<Account> _candidates(List<Account> all, Account? from) => from == null
      ? const []
      : [
          for (final a in all)
            if (a.currency != from.currency) a,
        ];

  void _autoPickTo(List<Account> all) {
    final candidates = _candidates(all, _find(all, _fromId));
    final current = _find(candidates, _toId);
    _toId =
        current?.id ?? (candidates.length == 1 ? candidates.first.id : null);
  }

  Future<void> _save(Account from, Account to, int rate) async {
    final send = _amount!.minor;
    final fee = _fee?.minor ?? 0;
    setState(() => _saving = true);
    unawaited(HapticFeedback.mediumImpact());
    final fromBefore = await ref.read(transferActionsProvider).balanceOf(from);
    final toBefore = await ref.read(transferActionsProvider).balanceOf(to);
    await ref
        .read(transferActionsProvider)
        .saveExchange(
          from: from,
          to: to,
          sendMinor: send,
          rateTenThousandths: rate,
          feeMinor: fee,
          note: _note.trim().isEmpty ? null : _note.trim(),
        );
    if (!mounted) return;
    final received = convertMinor(
      sendMinor: send,
      from: from.currency,
      rateTenThousandths: rate,
    );
    setState(() {
      _done = _Exchanged(
        fromName: from.name,
        toName: to.name,
        fromBefore: fromBefore,
        fromAfter: Money(fromBefore.minor - send - fee, from.currency),
        toBefore: toBefore,
        toAfter: Money(toBefore.minor + received, to.currency),
        chip: Money(send, from.currency).formatWithCode(),
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
        title: 'Exchange',
        children: [Text('Could not load your accounts.')],
      ),
      data: (all) {
        if (!_initialised) {
          _initialised = true;
          _fromId = _find(all, widget.accountId)?.id;
          _autoPickTo(all);
        }
        final done = _done;
        if (done != null) {
          return TransferSheetFrame(
            title: 'Exchange',
            children: [
              MoneyMoveAnimation(
                fromName: done.fromName,
                toName: done.toName,
                fromBefore: done.fromBefore,
                fromAfter: done.fromAfter,
                toBefore: done.toBefore,
                toAfter: done.toAfter,
                chipLabel: done.chip,
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
    final rate = parseRate(_rateController.text) ?? 0;
    final issue = validateExchange(
      from: from,
      to: to,
      amountMinor: amountMinor,
      rateTenThousandths: rate,
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
    final received = from != null && amountMinor > 0 && rate > 0
        ? convertMinor(
            sendMinor: amountMinor,
            from: from.currency,
            rateTenThousandths: rate,
          )
        : 0;
    final effective = from == null
        ? null
        : effectiveRateTenThousandths(
            from: from.currency,
            sendMinor: amountMinor,
            feeMinor: feeMinor,
            receivedMinor: received,
          );
    final rateIsNew = rate > 0 && rate != _latestRate;

    return TransferSheetFrame(
      title: 'Exchange',
      subtitle: 'Change money between a TND and a USD account.',
      children: [
        AccountChoiceRow(
          label: 'From',
          accounts: all,
          selectedId: _fromId,
          emptyHint: 'Add a TND and a USD account first.',
          onSelected: (a) => setState(() {
            if (from?.currency != a.currency) {
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
              : 'No ${from.currency == Currency.tnd ? 'USD' : 'TND'} account to receive it.',
          onSelected: (a) => setState(() => _toId = a.id),
        ),
        const SizedBox(height: Space.lg),
        MoneyField(
          key: ValueKey('amount-${currency.code}'),
          label: 'You send',
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
        Text('Rate (TND per 1 USD)', style: t.bodySmall),
        const SizedBox(height: Space.xs),
        TextField(
          controller: _rateController,
          textDirection: null,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [_RateFormatter()],
          style: DaftarType.price(24, c.text),
          onChanged: (_) => setState(() => _rateTouched = true),
          decoration: const InputDecoration(hintText: '3.1250'),
        ),
        if (rateIsNew)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: Text(
              _latestRate == null
                  ? 'This rate will be saved.'
                  : 'New rate. It will be saved with the exchange.',
              style: t.bodySmall,
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
        const SizedBox(height: Space.lg),
        _Preview(
          received: from != null && received > 0
              ? Money(
                  received,
                  from.currency == Currency.tnd ? Currency.usd : Currency.tnd,
                )
              : null,
          effectiveRate: effective,
          hasFee: feeMinor > 0,
        ),
        const SizedBox(height: Space.md),
        TextField(
          textDirection: null,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (v) => _note = v,
          decoration: const InputDecoration(
            hintText: 'Who or where (optional)',
          ),
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
          onPressed: issue != null || _saving
              ? null
              : () => _save(from!, to!, rate),
          child: const Text('Exchange'),
        ),
      ],
    );
  }
}

/// Digits with one `.` or `,` and at most four decimals.
class _RateFormatter extends TextInputFormatter {
  static final _pattern = RegExp(r'^\d{0,4}([.,]\d{0,4})?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => _pattern.hasMatch(newValue.text) ? newValue : oldValue;
}

/// "You get ..." and the effective rate, live.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.received,
    required this.effectiveRate,
    required this.hasFee,
  });

  final Money? received;
  final int? effectiveRate;
  final bool hasFee;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final r = received;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: c.raised,
        borderRadius: Radii.cardR,
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('You get', style: t.bodySmall),
          const SizedBox(height: Space.xs),
          Semantics(
            label: r == null
                ? 'You get nothing yet'
                : 'You get ${r.formatWithCode()}',
            excludeSemantics: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                r == null ? '-' : r.formatWithCode(),
                style: DaftarType.price(28, c.text),
              ),
            ),
          ),
          const SizedBox(height: Space.sm),
          Text(
            effectiveRate == null
                ? 'Effective rate appears once you enter an amount.'
                : '${hasFee ? 'Effective rate (with fee)' : 'Effective rate'}: '
                      '${formatRate(effectiveRate!)} TND per USD',
            style: t.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Exchanged {
  const _Exchanged({
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
