import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../domain/models/account.dart';
import '../../../../domain/models/money.dart';
import '../../../core/motion/squish.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/theme/daftar_typography.dart';
import '../../settings/views/list_icons.dart';
import '../view_models/accounts_providers.dart';

extension AccountKindLabel on AccountKind {
  String get label => switch (this) {
    AccountKind.cash => 'Cash',
    AccountKind.bank => 'Bank',
    AccountKind.card => 'Card',
    AccountKind.savings => 'Savings',
    AccountKind.wallet => 'Wallet',
  };

  String get defaultIconKey => switch (this) {
    AccountKind.cash => 'payments',
    AccountKind.bank => 'account_balance',
    AccountKind.card => 'credit_card',
    AccountKind.savings => 'account_balance',
    AccountKind.wallet => 'wallet',
  };
}

/// Icon keys an account can use (they all exist in `iconForKey`).
const accountIconKeys = [
  'wallet',
  'payments',
  'credit_card',
  'account_balance',
  'contactless',
  'payment',
];

IconData accountIcon(Account a) => iconForKey(a.iconKey);

/// What a masked amount looks like.
const maskedAmount = '••••';

/// A money amount that follows the global hide-amounts switch (and, when
/// [forceHide] is set, the account's own `hideAmount` flag).
class AmountText extends ConsumerWidget {
  const AmountText(
    this.money, {
    super.key,
    this.size = 20,
    this.color,
    this.forceHide = false,
    this.showCode = true,
    this.plus = false,
  });

  final Money money;
  final double size;
  final Color? color;
  final bool forceHide;
  final bool showCode;

  /// Prefix positive amounts with "+".
  final bool plus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final hidden = ref.watch(hideAmountsProvider) || forceHide;
    final fg = color ?? c.text;
    final text = hidden
        ? maskedAmount
        : '${plus && money.minor > 0 ? '+' : ''}${money.format()}';
    return Semantics(
      label: hidden ? 'Amount hidden' : money.formatWithCode(),
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(text, style: DaftarType.price(size, fg)),
            if (showCode) ...[
              const SizedBox(width: Space.xs),
              Text(
                money.currency.code,
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: c.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The eye that masks or reveals every balance.
class HideAmountsButton extends ConsumerWidget {
  const HideAmountsButton({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hidden = ref.watch(hideAmountsProvider);
    final label = hidden ? 'Show amounts' : 'Hide amounts';
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: () => ref.read(hideAmountsProvider.notifier).toggle(),
      child: Tooltip(
        message: label,
        child: InkResponse(
          radius: Chrome.minTouch / 2,
          onTap: () {
            HapticFeedback.selectionClick();
            ref.read(hideAmountsProvider.notifier).toggle();
          },
          child: SizedBox.square(
            dimension: Chrome.minTouch,
            child: Icon(
              hidden
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 22,
              color: color ?? context.colors.muted,
            ),
          ),
        ),
      ),
    );
  }
}

/// Back button + title row at the top of the accounts screens.
class AccountsHeader extends StatelessWidget {
  const AccountsHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.lg,
        Space.gutter,
        Space.sm,
      ),
      child: Row(
        children: [
          Semantics(
            container: true,
            button: true,
            label: 'Back',
            excludeSemantics: true,
            child: Squish(
              onTap: () =>
                  context.canPop() ? context.pop() : context.go(Routes.home),
              child: Container(
                width: Chrome.minTouch,
                height: Chrome.minTouch,
                decoration: BoxDecoration(
                  borderRadius: Radii.inputR,
                  border: Border.all(color: c.line),
                ),
                child: Icon(Icons.arrow_back_rounded, size: 20, color: c.text),
              ),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: t.headlineSmall,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
