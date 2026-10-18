import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../../domain/models/account.dart';
import '../../../../../domain/models/money.dart';
import '../../../../core/motion/daftar_motion.dart';
import '../../../../core/motion/squish.dart';
import '../../../../core/theme/daftar_colors.dart';
import '../../../../core/theme/daftar_tokens.dart';
import '../../../../core/theme/daftar_typography.dart';

/// Padding and scrolling shared by the transfer and exchange sheets: keeps the
/// content above the keyboard and scrollable at any text size.
class TransferSheetFrame extends StatelessWidget {
  const TransferSheetFrame({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    return SafeArea(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
            Text(title, style: t.headlineSmall),
            if (subtitle != null) ...[
              const SizedBox(height: Space.xs),
              Text(subtitle!, style: t.bodySmall?.copyWith(color: c.muted)),
            ],
            const SizedBox(height: Space.lg),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// A labelled row of accounts to pick one from.
class AccountChoiceRow extends StatelessWidget {
  const AccountChoiceRow({
    super.key,
    required this.label,
    required this.accounts,
    required this.selectedId,
    required this.onSelected,
    this.emptyHint,
  });

  final String label;
  final List<Account> accounts;
  final String? selectedId;
  final ValueChanged<Account> onSelected;

  /// Shown instead of chips when [accounts] is empty.
  final String? emptyHint;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.bodySmall?.copyWith(color: c.muted)),
        const SizedBox(height: Space.sm),
        if (accounts.isEmpty)
          Text(emptyHint ?? 'No accounts.', style: t.bodyMedium)
        else
          LayoutBuilder(
            builder: (context, box) => Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final a in accounts)
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: box.maxWidth),
                    child: _AccountChip(
                      account: a,
                      selected: a.id == selectedId,
                      onTap: () => onSelected(a),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AccountChip extends StatelessWidget {
  const _AccountChip({
    required this.account,
    required this.selected,
    required this.onTap,
  });

  final Account account;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '${account.name}, ${account.currency.code}',
      excludeSemantics: true,
      child: Squish(
        onTap: onTap,
        child: AnimatedContainer(
          duration: DaftarMotion.fast,
          curve: DaftarMotion.standard,
          constraints: const BoxConstraints(minHeight: Chrome.minTouch),
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? c.raised : Colors.transparent,
            borderRadius: Radii.buttonR,
            border: Border.all(color: selected ? c.text : c.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  account.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.labelLarge?.copyWith(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: Space.sm),
              Text(
                account.currency.code,
                style: t.bodySmall?.copyWith(color: c.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Motion "Money moves": a lime amount chip lifts off the source account,
/// arcs across, and drops into the destination while the two balances count to
/// their new values. Plays once; [onDone] fires at the end (straight away with
/// "Remove animations" on, which shows the final frame).
class MoneyMoveAnimation extends StatefulWidget {
  const MoneyMoveAnimation({
    super.key,
    required this.fromName,
    required this.toName,
    required this.fromBefore,
    required this.fromAfter,
    required this.toBefore,
    required this.toAfter,
    required this.chipLabel,
    this.onDone,
  });

  final String fromName;
  final String toName;
  final Money fromBefore;
  final Money fromAfter;
  final Money toBefore;
  final Money toAfter;

  /// Text on the travelling chip, e.g. "200.000 TND".
  final String chipLabel;
  final VoidCallback? onDone;

  @override
  State<MoneyMoveAnimation> createState() => _MoneyMoveAnimationState();
}

class _MoneyMoveAnimationState extends State<MoneyMoveAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: DaftarMotion.slow * 3,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (DaftarMotion.reduced(context)) {
      _c.value = 1;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onDone?.call();
      });
    } else {
      _c.forward().whenComplete(() {
        if (mounted) widget.onDone?.call();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  // Timeline: 0-0.15 chip appears, 0.15-0.75 it travels, 0.75-1 it lands.
  static const _liftEnd = 0.15;
  static const _landStart = 0.75;

  Money _count(Money a, Money b, double t) =>
      Money(a.minor + ((b.minor - a.minor) * t).round(), a.currency);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final reduced = DaftarMotion.reduced(context);
    return Semantics(
      label:
          'Moved ${widget.chipLabel} from ${widget.fromName} to ${widget.toName}',
      child: ExcludeSemantics(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final v = _c.value;
            final travel = DaftarMotion.emphasized.transform(
              ((v - _liftEnd) / (_landStart - _liftEnd)).clamp(0.0, 1.0),
            );
            final appear = (v / _liftEnd).clamp(0.0, 1.0);
            final land = ((v - _landStart) / (1 - _landStart)).clamp(0.0, 1.0);
            final chipOpacity = reduced ? 0.0 : appear * (1 - land);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _MiniAccount(
                            name: widget.fromName,
                            balance: _count(
                              widget.fromBefore,
                              widget.fromAfter,
                              travel,
                            ),
                          ),
                        ),
                        const SizedBox(width: Space.xxxl * 2),
                        Expanded(
                          child: _MiniAccount(
                            name: widget.toName,
                            balance: _count(
                              widget.toBefore,
                              widget.toAfter,
                              travel,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment(-0.5 + travel, 0),
                        child: Opacity(
                          opacity: chipOpacity,
                          child: Transform.translate(
                            offset: Offset(
                              0,
                              -math.sin(math.pi * travel) * Space.xxxl,
                            ),
                            child: Transform.scale(
                              scale: 0.5 + 0.5 * appear - 0.4 * land,
                              child: _Chip(label: widget.chipLabel),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.lg),
                Opacity(
                  opacity: land,
                  child: Text(
                    'Done',
                    style: t.titleMedium?.copyWith(color: c.accentText),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.xs,
      ),
      decoration: BoxDecoration(color: c.lime, borderRadius: Radii.chipR),
      child: Text(label, maxLines: 1, style: DaftarType.price(14, c.onLime)),
    );
  }
}

class _MiniAccount extends StatelessWidget {
  const _MiniAccount({required this.name, required this.balance});

  final String name;
  final Money balance;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: Radii.cardR,
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: t.bodySmall?.copyWith(color: c.muted),
          ),
          const SizedBox(height: Space.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(balance.format(), style: DaftarType.price(20, c.text)),
          ),
          Text(
            balance.currency.code,
            style: t.bodySmall?.copyWith(color: c.muted),
          ),
        ],
      ),
    );
  }
}
