import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../domain/models/bill.dart';
import '../../../../domain/models/money.dart';
import '../../../../domain/use_cases/bill_summary.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/widgets/collapsing_header.dart';
import '../../../core/widgets/daftar_action_bar.dart';
import '../../../core/widgets/money_field.dart';
import '../../products/views/select_chip.dart';
import '../view_models/bill_draft.dart';
import '../view_models/bills_providers.dart';
import 'bill_widgets.dart';

/// Add (`Routes.billNew`) or edit (`Routes.billEdit`) a bill.
class BillFormScreen extends ConsumerStatefulWidget {
  const BillFormScreen({super.key, this.billId});

  /// Null for a new bill.
  final String? billId;

  @override
  ConsumerState<BillFormScreen> createState() => _BillFormScreenState();
}

class _BillFormScreenState extends ConsumerState<BillFormScreen> {
  final _name = TextEditingController();
  final _days = TextEditingController();
  BillDraft? _draft;
  bool _submitted = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _days.dispose();
    super.dispose();
  }

  void _start(BillDraft draft) {
    _draft = draft;
    _name.text = draft.name;
    _days.text = draft.customDays?.toString() ?? '';
  }

  void _update(BillDraft Function(BillDraft d) change) =>
      setState(() => _draft = change(_draft!));

  Future<void> _pickDate() async {
    final current = _draft!.nextDueAt;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 1),
      lastDate: DateTime(current.year + 10),
    );
    if (picked != null) {
      _update(
        (d) => d.copyWith(
          nextDueAt: DateTime(picked.year, picked.month, picked.day),
        ),
      );
    }
  }

  Future<void> _save() async {
    final draft = _draft!;
    if (!draft.isValid) {
      setState(() => _submitted = true);
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    await ref.read(billActionsProvider).save(draft.toBill());
    if (!mounted) return;
    context.canPop() ? context.pop() : context.go(Routes.bills);
  }

  @override
  Widget build(BuildContext context) {
    final editingId = widget.billId;
    if (_draft == null) {
      if (editingId == null) {
        _start(BillDraft.fresh(ref.read(billsNowProvider)));
      } else {
        final bill = ref.watch(billProvider(editingId));
        if (bill != null) _start(BillDraft.fromBill(bill));
      }
    }
    final draft = _draft;

    return Scaffold(
      extendBody: true,
      bottomNavigationBar: DaftarActionBar(
        actions: const [],
        primary: ToolbarAction(
          icon: Icons.check_rounded,
          label: 'Save',
          onTap: draft == null || _saving ? null : _save,
        ),
      ),
      body: CustomScrollView(
        slivers: [
          CollapsingHeader(
            title: editingId == null ? 'New bill' : 'Edit bill',
            expandedHeight: 120,
            leading: HeaderIconButton(
              icon: Icons.arrow_back_rounded,
              label: 'Back',
              onTap: () =>
                  context.canPop() ? context.pop() : context.go(Routes.bills),
            ),
          ),
          if (draft != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                Space.gutter,
                Space.sm,
                Space.gutter,
                Chrome.contentBottomPadding,
              ),
              sliver: SliverList.list(children: _fields(draft)),
            ),
        ],
      ),
    );
  }

  List<Widget> _fields(BillDraft draft) {
    final t = Theme.of(context).textTheme;
    final c = context.colors;
    final show = _submitted;
    return [
      TextField(
        controller: _name,
        textDirection: null,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.next,
        onChanged: (v) => _update((d) => d.copyWith(name: v)),
        decoration: InputDecoration(
          labelText: 'Name',
          hintText: 'STEG, Netflix, rent...',
          errorText: show ? draft.nameError : null,
        ),
      ),
      const SizedBox(height: Space.xl),
      Text('Icon', style: t.bodySmall),
      const SizedBox(height: Space.sm),
      Wrap(
        spacing: Space.sm,
        runSpacing: Space.xs,
        children: [
          for (final p in billIconPresets)
            SelectChip(
              label: p.label,
              icon: p.icon,
              selected: draft.iconKey == p.key,
              onTap: () => _update((d) => d.copyWith(iconKey: p.key)),
            ),
        ],
      ),
      const SizedBox(height: Space.xl),
      Text('Currency', style: t.bodySmall),
      const SizedBox(height: Space.sm),
      Wrap(
        spacing: Space.sm,
        children: [
          for (final cur in Currency.values)
            SelectChip(
              label: cur.code,
              selected: draft.currency == cur,
              onTap: () => _update(
                (d) => d.currency == cur
                    ? d
                    : d.copyWith(currency: cur, clearAmount: true),
              ),
            ),
        ],
      ),
      const SizedBox(height: Space.md),
      MoneyField(
        key: ValueKey(draft.currency),
        label: 'Amount',
        currency: draft.currency,
        initialValue: draft.amount,
        fontSize: 32,
        errorText: show ? draft.amountError : null,
        onChanged: (m) => _update(
          (d) =>
              m == null ? d.copyWith(clearAmount: true) : d.copyWith(amount: m),
        ),
      ),
      const SizedBox(height: Space.xl),
      Text('Repeats', style: t.bodySmall),
      const SizedBox(height: Space.sm),
      Wrap(
        spacing: Space.sm,
        runSpacing: Space.xs,
        children: [
          for (final (cycle, label) in const [
            (BillCycle.monthly, 'Monthly'),
            (BillCycle.yearly, 'Yearly'),
            (BillCycle.weekly, 'Weekly'),
            (BillCycle.customDays, 'Every N days'),
          ])
            SelectChip(
              label: label,
              selected: draft.cycle == cycle,
              onTap: () => _update((d) => d.copyWith(cycle: cycle)),
            ),
        ],
      ),
      if (draft.cycle == BillCycle.customDays) ...[
        const SizedBox(height: Space.md),
        TextField(
          controller: _days,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: (v) => _update(
            (d) => v.isEmpty
                ? d.copyWith(clearCustomDays: true)
                : d.copyWith(customDays: int.tryParse(v)),
          ),
          decoration: InputDecoration(
            labelText: 'Number of days',
            errorText: show ? draft.customDaysError : null,
          ),
        ),
      ],
      const SizedBox(height: Space.xl),
      Text('Next due date', style: t.bodySmall),
      const SizedBox(height: Space.xs),
      Semantics(
        button: true,
        label: 'Next due date, ${shortDate(draft.nextDueAt)}',
        excludeSemantics: true,
        onTap: _pickDate,
        child: InkWell(
          borderRadius: Radii.inputR,
          onTap: _pickDate,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Chrome.minTouch),
            child: Row(
              children: [
                Icon(Icons.event_outlined, color: c.muted),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(shortDate(draft.nextDueAt), style: t.titleMedium),
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: Space.xl),
      Text('Remind me', style: t.bodySmall),
      const SizedBox(height: Space.xs),
      _ReminderStepper(
        days: draft.reminderDaysBefore,
        onChanged: (v) => _update((d) => d.copyWith(reminderDaysBefore: v)),
      ),
    ];
  }
}

/// "3 days before" with - and + buttons.
class _ReminderStepper extends StatelessWidget {
  const _ReminderStepper({required this.days, required this.onChanged});

  final int days;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final label = switch (days) {
      0 => 'On the day',
      1 => '1 day before',
      final n => '$n days before',
    };
    Widget button(IconData icon, String tip, int? to) => IconButton(
      tooltip: tip,
      constraints: const BoxConstraints.tightFor(
        width: Chrome.minTouch,
        height: Chrome.minTouch,
      ),
      onPressed: to == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onChanged(to);
            },
      icon: Icon(icon),
    );
    return Row(
      children: [
        button(
          Icons.remove_rounded,
          'Remind one day later',
          days > 0 ? days - 1 : null,
        ),
        Expanded(
          child: Text(label, style: t.titleMedium, textAlign: TextAlign.center),
        ),
        button(
          Icons.add_rounded,
          'Remind one day earlier',
          days < maxReminderDays ? days + 1 : null,
        ),
      ],
    );
  }
}
