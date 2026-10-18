import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../app/routes/accounts_routes.dart';
import '../../../core/brand/dal_mark.dart';
import '../../../core/motion/daftar_motion.dart';
import '../../../core/motion/squish.dart';
import '../../../core/motion/tilt.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../accounts/summary/views/accounts_summary_card.dart';
import '../../bills/views/bills_due_card.dart';
import '../../debts/views/debts_card.dart';
import '../view_models/card_order.dart';
import '../view_models/home_view_model.dart';
import 'recent_list.dart';
import 'wallet_stack.dart';

/// Home: the wallet card stack, search shortcut and the Recent list.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _editing = false;

  void _open(HomeCardId card) {
    switch (card) {
      case HomeCardId.prices:
        context.push(Routes.products);
      case HomeCardId.places:
      // DECISION(owner): menus live on place pages, so the Menus card opens the places list.
      case HomeCardId.menus:
        context.push(Routes.places);
      case HomeCardId.accounts:
        context.push(AccountsRoutes.list);
      case HomeCardId.calculator:
        context.go(Routes.calculator);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final summary = ref.watch(homeSummaryProvider);
    final order = ref.watch(homeCardOrderProvider);

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          Space.gutter,
          Space.lg,
          Space.gutter,
          Chrome.contentBottomPadding,
        ),
        children: [
          Row(
            children: [
              const DalWriteOn(size: 28),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  'daftar',
                  style: t.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.1,
                  ),
                ),
              ),
              _SettingsButton(onTap: () => context.push(Routes.settings)),
            ],
          ),
          const SizedBox(height: Space.lg),
          _SearchPill(
            onSearch: () => context.go(Routes.search),
            onScan: () => context.push(Routes.scan),
          ),
          const SizedBox(height: Space.xl),
          Row(
            children: [
              Expanded(child: Text('Your wallet', style: t.headlineSmall)),
              TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(Chrome.minTouch, Chrome.minTouch),
                ),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() => _editing = !_editing);
                },
                child: Text(
                  _editing ? 'Done' : 'Edit',
                  style: t.labelLarge?.copyWith(color: c.accentText),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          AnimatedSwitcher(
            duration: DaftarMotion.reduced(context)
                ? Duration.zero
                : DaftarMotion.base,
            child: _editing
                ? WalletReorderList(
                    key: const ValueKey('reorder'),
                    order: order,
                    onReorder: (a, b) =>
                        ref.read(homeCardOrderProvider.notifier).move(a, b),
                  )
                : Tilt(
                    key: const ValueKey('stack'),
                    child: WalletStack(
                      order: order,
                      summary: summary.value,
                      onOpen: _open,
                    ),
                  ),
          ),
          const SizedBox(height: Space.xl),
          // Money at a glance: this period's spending, bills due soon, debts.
          const AccountsSummaryCard(),
          const SizedBox(height: Space.md),
          const BillsDueCard(),
          const SizedBox(height: Space.md),
          const DebtsCard(),
          const SizedBox(height: Space.xl),
          RecentList(summary: summary),
        ],
      ),
    );
  }
}

class _SettingsButton extends StatelessWidget {
  const _SettingsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: 'Settings',
      child: Semantics(
        button: true,
        label: 'Settings',
        excludeSemantics: true,
        onTap: onTap,
        child: Squish(
          onTap: onTap,
          child: Container(
            width: Chrome.minTouch,
            height: Chrome.minTouch,
            decoration: BoxDecoration(
              borderRadius: Radii.inputR,
              border: Border.all(color: c.line),
            ),
            child: Icon(Icons.settings_outlined, size: 20, color: c.text),
          ),
        ),
      ),
    );
  }
}

class _SearchPill extends StatelessWidget {
  const _SearchPill({required this.onSearch, required this.onScan});

  final VoidCallback onSearch;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      label: 'Search products, places, menus',
      excludeSemantics: true,
      onTap: onSearch,
      child: Squish(
        onTap: onSearch,
        pressedScale: 0.98,
        child: Container(
          height: 52,
          padding: const EdgeInsets.only(left: Space.lg, right: Space.xs + 2),
          decoration: BoxDecoration(
            color: c.raised,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 20, color: c.muted),
              const SizedBox(width: Space.md - 2),
              Expanded(
                child: Text(
                  'Search products, places, menus',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.bodyMedium?.copyWith(color: c.muted),
                ),
              ),
              Tooltip(
                message: 'Scan barcode',
                child: Semantics(
                  button: true,
                  label: 'Scan barcode',
                  excludeSemantics: true,
                  onTap: onScan,
                  child: Squish(
                    onTap: onScan,
                    child: Container(
                      width: Chrome.minTouch - 4,
                      height: Chrome.minTouch - 4,
                      decoration: BoxDecoration(
                        color: c.line,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.qr_code_scanner_rounded,
                        size: 18,
                        color: c.text,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
