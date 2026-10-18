import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/data_providers.dart';
import '../../../../domain/models/account.dart';
import '../../../../domain/models/ids.dart';
import '../../../../domain/models/money.dart';
import '../../../../domain/rates/rate_math.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import 'rate_field.dart';

/// Asks "what rate?" whenever a USD amount needs converting. The field is
/// prefilled with the latest saved rate and editable. A rate that differs from
/// the latest one is saved as a new `rate_entries` row; an unchanged rate is
/// reused without adding a duplicate row.
///
/// Resolves to the chosen rate (TND per USD x 10 000), or null when dismissed.
/// When [usdAmount] is given the sheet shows what it is worth in TND.
Future<int?> showRatePrompt(
  BuildContext context,
  WidgetRef ref, {
  Money? usdAmount,
}) async {
  final latest = await ref.read(rateEntriesRepositoryProvider).latest();
  if (!context.mounted) return null;
  final result = await showModalBottomSheet<RateEntry>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => RateSheet(usdAmount: usdAmount, latest: latest),
  );
  return result?.tndPerUsdTenThousandths;
}

/// Add a rate (or edit [existing]) from the Rates screen. Resolves to the saved
/// entry or null.
Future<RateEntry?> showRateEditor(
  BuildContext context, {
  RateEntry? existing,
  RateEntry? latest,
  int? initialRate,
}) => showModalBottomSheet<RateEntry>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) =>
      RateSheet(existing: existing, latest: latest, initialRate: initialRate),
);

/// The body of the rate sheets. Prefer [showRatePrompt] / [showRateEditor].
class RateSheet extends ConsumerStatefulWidget {
  const RateSheet({
    super.key,
    this.usdAmount,
    this.existing,
    this.latest,
    this.initialRate,
  });

  final Money? usdAmount;
  final RateEntry? existing;
  final RateEntry? latest;

  /// Overrides the prefilled rate (the reverse calculator passes its own).
  final int? initialRate;

  @override
  ConsumerState<RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends ConsumerState<RateSheet> {
  late final TextEditingController _rate;
  late final TextEditingController _note;
  late DateTime _date;
  int? _parsed;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _parsed =
        widget.existing?.tndPerUsdTenThousandths ??
        widget.initialRate ??
        widget.latest?.tndPerUsdTenThousandths;
    _rate = TextEditingController(
      text: _parsed == null ? '' : RateMath.formatRate(_parsed!),
    );
    _note = TextEditingController(text: widget.existing?.sourceNote ?? '');
    _date = widget.existing?.date ?? DateTime.now();
  }

  @override
  void dispose() {
    _rate.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() {
        _date = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _date.hour,
          _date.minute,
        );
      });
    }
  }

  Future<void> _save() async {
    final rate = _parsed;
    if (rate == null || _saving) return;
    setState(() => _saving = true);
    unawaited(HapticFeedback.mediumImpact());
    final latest = widget.latest;
    final existing = widget.existing;
    final note = _note.text.trim();
    // A prompt that keeps the latest rate unchanged reuses it.
    if (existing == null &&
        widget.usdAmount != null &&
        latest != null &&
        latest.tndPerUsdTenThousandths == rate &&
        note.isEmpty) {
      Navigator.of(context).pop(latest);
      return;
    }
    final entry = RateEntry(
      id: existing?.id ?? newId(),
      date: _date,
      tndPerUsdTenThousandths: rate,
      sourceNote: note.isEmpty ? null : note,
    );
    await ref.read(rateEntriesRepositoryProvider).save(entry);
    if (mounted) Navigator.of(context).pop(entry);
  }

  String _dateLabel(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final usd = widget.usdAmount;
    final rate = _parsed;
    final editing = widget.existing != null;
    final title = editing
        ? 'Edit rate'
        : usd != null
        ? 'What rate today?'
        : 'Add a rate';
    final actionLabel = editing
        ? 'Save'
        : usd != null
        ? 'Use this rate'
        : 'Save rate';

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          Space.xl,
          0,
          Space.xl,
          Space.xl + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: t.headlineSmall),
            const SizedBox(height: Space.lg),
            RateField(
              controller: _rate,
              autofocus: true,
              onChanged: (s) =>
                  setState(() => _parsed = RateMath.tryParseRate(s)),
            ),
            if (usd != null && rate != null) ...[
              const SizedBox(height: Space.sm),
              Text(
                '${usd.formatWithCode()} = '
                '${RateMath.tndForUsd(usd, rate).formatWithCode()}',
                key: const Key('rate-conversion'),
                style: t.bodyMedium?.copyWith(color: c.accentText),
              ),
            ],
            const SizedBox(height: Space.lg),
            TextField(
              controller: _note,
              textDirection: null,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Where from (optional)',
                hintText: 'Bank, exchange office, black market…',
              ),
            ),
            const SizedBox(height: Space.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  minimumSize: const Size(Chrome.minTouch, Chrome.minTouch),
                ),
                onPressed: _pickDate,
                icon: const Icon(Icons.event_outlined),
                label: Text(_dateLabel(_date)),
              ),
            ),
            const SizedBox(height: Space.lg),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: c.lime,
                foregroundColor: c.onLime,
                minimumSize: const Size.fromHeight(Chrome.minTouch),
                shape: const StadiumBorder(),
              ),
              onPressed: rate == null || _saving ? null : _save,
              child: Text(
                actionLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
