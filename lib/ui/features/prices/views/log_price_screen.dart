import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router.dart';
import '../../../../domain/models/product.dart';
import '../../../../domain/use_cases/relative_time.dart';
import '../../../../domain/use_cases/unit_price.dart';
import '../../../core/motion/daftar_motion.dart';
import '../../../core/motion/shake.dart';
import '../../../core/motion/squish.dart';
import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/theme/daftar_typography.dart';
import '../../../core/widgets/floating_toast.dart';
import '../../../core/widgets/money_field.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/success_check.dart';
import '../../accounts/views/bought_it_sheet.dart';
import '../../products/view_models/catalog_providers.dart';
import '../../products/views/category_chips.dart';
import '../../products/views/select_chip.dart';
import '../view_models/log_price_view_model.dart';
import '../view_models/photo_store.dart';
import 'widgets/form_bits.dart';
import 'widgets/place_picker_sheet.dart';

/// "Log a price": exactly the brand screen: product (autocomplete + scan)
/// with variant chips, optional size + unit, a big price, range toggle, where
/// (place or Global), promo, photo and note.
class LogPriceScreen extends ConsumerStatefulWidget {
  const LogPriceScreen({super.key, this.args = const LogPriceArgs()});

  final LogPriceArgs args;

  @override
  ConsumerState<LogPriceScreen> createState() => _LogPriceScreenState();
}

class _LogPriceScreenState extends ConsumerState<LogPriceScreen> {
  final _product = TextEditingController();
  final _size = TextEditingController();
  final _note = TextEditingController();
  final _variantName = TextEditingController();
  final _productFocus = FocusNode();
  final _amount = TextEditingController();

  final _productKey = GlobalKey();
  final _priceKey = GlobalKey();
  final _whereKey = GlobalKey();
  final _promoKey = GlobalKey();

  int _failures = 0;
  bool _done = false;

  /// "I bought it" is on: after saving, ask which account paid.
  bool _bought = false;

  @override
  void initState() {
    super.initState();
    _productFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _product.dispose();
    _size.dispose();
    _note.dispose();
    _variantName.dispose();
    _productFocus.dispose();
    _amount.dispose();
    super.dispose();
  }

  /// Opens the calculator and writes the amount it returns into the price field.
  Future<void> _useCalculator() async {
    final amount = await pickFromCalculator(context);
    if (amount == null || !mounted) return;
    _amount.text = moneyInputText(amount);
    _vm.setAmount(amount);
  }

  LogPriceViewModel get _vm =>
      ref.read(logPriceViewModelProvider(widget.args).notifier);

  /// Keeps a text controller in step with a value the view-model changed (scan, pick).
  void _sync(TextEditingController controller, String? text) {
    final value = text ?? '';
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _close() => context.canPop() ? context.pop() : context.go(Routes.home);

  Future<void> _scan() async {
    final code = await context.push<String>('${Routes.scan}?pick=1');
    if (code != null && mounted) await _vm.applyBarcode(code);
  }

  Future<void> _pickPlace() async {
    final place = await showPlacePicker(context);
    if (place != null && mounted) _vm.setPlace(place);
  }

  Future<void> _pickPromoEnd(DateTime? current) async {
    final now = ref.read(clockProvider)();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? today.add(const Duration(days: 7)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 365 * 2)),
      helpText: 'Promo ends',
    );
    if (picked != null && mounted) _vm.setPromoEnd(picked);
  }

  Future<void> _addGlobalType() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New price type'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textDirection: null,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Online price, Market price…',
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && mounted) await _vm.addGlobalType(name);
  }

  Future<void> _save() async {
    final provider = logPriceViewModelProvider(widget.args);
    FocusScope.of(context).unfocus();
    bool ok;
    try {
      ok = await _vm.save();
    } on Object {
      if (mounted) {
        FloatingToast.show(
          context,
          'Could not save. Try again.',
          kind: ToastKind.error,
        );
      }
      return;
    }
    if (!mounted) return;
    if (!ok) {
      setState(() => _failures++);
      unawaited(HapticFeedback.mediumImpact());
      _scrollToFirstError(ref.read(provider).errors);
      return;
    }
    unawaited(HapticFeedback.mediumImpact());
    final s = ref.read(provider);
    FloatingToast.show(
      context,
      'Price saved',
      subtitle: '${s.productText.trim()} · ${s.amount!.formatWithCode()}',
      kind: ToastKind.success,
    );
    if (_bought) {
      final entryId = ref.read(provider).savedEntryId;
      if (entryId != null) {
        await showBoughtItSheet(
          context,
          priceEntryId: entryId,
          price: s.amount!,
          title: s.productText.trim(),
          categoryId: s.categoryId,
        );
        if (!mounted) return;
      }
    }
    setState(() => _done = true);
  }

  void _scrollToFirstError(Map<LogPriceField, String> errors) {
    final keys = {
      LogPriceField.product: _productKey,
      LogPriceField.variant: _productKey,
      LogPriceField.amount: _priceKey,
      LogPriceField.amountMax: _priceKey,
      LogPriceField.where: _whereKey,
      LogPriceField.promoEnd: _promoKey,
    };
    for (final field in LogPriceField.values) {
      if (!errors.containsKey(field)) continue;
      final target = keys[field]!.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          duration: DaftarMotion.reduced(context)
              ? Duration.zero
              : DaftarMotion.base,
          curve: DaftarMotion.standard,
          alignment: 0.1,
        );
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = logPriceViewModelProvider(widget.args);
    final s = ref.watch(provider);
    ref.listen(
      provider.select((s) => s.productText),
      (_, v) => _sync(_product, v),
    );
    ref.listen(provider.select((s) => s.sizeText), (_, v) => _sync(_size, v));
    ref.listen(
      provider.select((s) => s.newVariantName),
      (_, v) => _sync(_variantName, v),
    );

    final c = context.colors;
    final t = Theme.of(context).textTheme;
    int shake(Iterable<LogPriceField> fields) =>
        fields.any(s.errors.containsKey) ? _failures : 0;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.gutter,
                    Space.lg,
                    Space.gutter,
                    0,
                  ),
                  child: Row(
                    children: [
                      Semantics(
                        container: true,
                        button: true,
                        label: 'Close',
                        excludeSemantics: true,
                        child: Squish(
                          onTap: _close,
                          child: Container(
                            width: Chrome.minTouch,
                            height: Chrome.minTouch,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: c.line),
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 20,
                              color: c.text,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.md),
                      Text('Log a price', style: t.headlineSmall),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(
                      Space.gutter,
                      18,
                      Space.gutter,
                      Space.xxl,
                    ),
                    children: [
                      Shake(
                        trigger: shake(const [
                          LogPriceField.product,
                          LogPriceField.variant,
                        ]),
                        child: KeyedSubtree(
                          key: _productKey,
                          child: _productSection(s),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _sizeSection(s),
                      const SizedBox(height: 18),
                      Shake(
                        trigger: shake(const [
                          LogPriceField.amount,
                          LogPriceField.amountMax,
                        ]),
                        child: KeyedSubtree(
                          key: _priceKey,
                          child: _priceCard(s),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Shake(
                        trigger: shake(const [LogPriceField.where]),
                        child: KeyedSubtree(
                          key: _whereKey,
                          child: _whereSection(s),
                        ),
                      ),
                      const SizedBox(height: 18),
                      KeyedSubtree(key: _promoKey, child: _promoSection(s)),
                      const SizedBox(height: 18),
                      _photoNoteSection(s),
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
                  child: _SaveButton(saving: s.saving, onTap: _save),
                ),
              ],
            ),
          ),
          if (_done)
            Positioned.fill(
              child: ColoredBox(
                color: c.background.withValues(alpha: 0.94),
                child: Center(child: SuccessCheck(size: 96, onDone: _close)),
              ),
            ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- product

  Widget _productSection(LogPriceState s) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final products = ref.watch(productsProvider).value ?? const <Product>[];
    final suggestions = s.product == null
        ? suggestProducts(products, s.productText)
        : const <Product>[];
    final showSuggestions =
        _productFocus.hasFocus &&
        s.product == null &&
        s.productText.trim().isNotEmpty;
    final product = s.product;
    final variants = product?.variants ?? const <Variant>[];
    final hideDefaultOnly =
        variants.length == 1 &&
        variants.single.name == null &&
        variants.single.sizeValue == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Product'),
        const SizedBox(height: Space.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _product,
                focusNode: _productFocus,
                textDirection: null,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                style: t.titleMedium,
                onChanged: _vm.setProductText,
                decoration: boardInput(
                  context,
                  hint: 'Milk, Milka, haircut…',
                  errorText: s.errors[LogPriceField.product],
                ),
              ),
            ),
            const SizedBox(width: Space.sm),
            Semantics(
              container: true,
              button: true,
              label: 'Scan barcode',
              excludeSemantics: true,
              child: Squish(
                onTap: _scan,
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: c.raised,
                    borderRadius: Radii.inputR,
                  ),
                  child: Icon(
                    Icons.qr_code_scanner_rounded,
                    size: 22,
                    color: c.text,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (showSuggestions) ...[
          const SizedBox(height: Space.sm),
          _Suggestions(
            suggestions: suggestions,
            typed: s.productText.trim(),
            onPick: (p) {
              _productFocus.unfocus();
              _vm.selectProduct(p);
            },
            onNew: _productFocus.unfocus,
          ),
        ],
        if (s.barcode != null) ...[
          const SizedBox(height: Space.sm),
          _BarcodeNote(state: s),
        ],
        if (s.productText.trim().isNotEmpty &&
            !(showSuggestions && suggestions.isNotEmpty)) ...[
          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.sm,
            children: [
              for (final v in variants)
                if (!hideDefaultOnly)
                  SelectChip(
                    label: _variantLabel(v),
                    selected: s.variantId == v.id,
                    onTap: () => _vm.selectVariant(v.id),
                  ),
              SelectChip(
                label: '+ Variant',
                isAdd: true,
                selected: s.newVariantName != null,
                onTap: s.newVariantName == null ? _vm.startNewVariant : null,
              ),
            ],
          ),
        ],
        if (s.newVariantName != null) ...[
          const SizedBox(height: Space.sm),
          TextField(
            controller: _variantName,
            autofocus: true,
            textDirection: null,
            textCapitalization: TextCapitalization.sentences,
            onChanged: _vm.setNewVariantName,
            style: t.titleMedium,
            decoration:
                boardInput(
                  context,
                  hint: 'Variant name (Oreo, Noisette…)',
                  errorText: s.errors[LogPriceField.variant],
                ).copyWith(
                  suffixIcon: IconButton(
                    tooltip: 'Remove variant',
                    icon: Icon(Icons.close_rounded, color: c.muted),
                    onPressed: _vm.cancelNewVariant,
                  ),
                ),
          ),
        ],
        if (s.isNewProduct) ...[
          const SizedBox(height: Space.md),
          const FieldLabel('Category', optional: true),
          const SizedBox(height: Space.xs),
          CategoryChips(selectedId: s.categoryId, onSelected: _vm.setCategory),
        ],
      ],
    );
  }

  String _variantLabel(Variant v) {
    final size = v.sizeValue != null && v.sizeUnit != null
        ? formatSize(v.sizeValue!, v.sizeUnit!)
        : null;
    return [?(v.name ?? (size == null ? 'Standard' : null)), ?size].join(' · ');
  }

  // -------------------------------------------------------------------- size

  Widget _sizeSection(LogPriceState s) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const FieldLabel('Size', optional: true),
      const SizedBox(height: Space.sm),
      Row(
        children: [
          SizedBox(
            width: 92,
            child: TextField(
              controller: _size,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              onChanged: _vm.setSizeText,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontFeatures: DaftarType.tabular),
              decoration: boardInput(context, hint: '100'),
            ),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: UnitSegmented(value: s.unit, onChanged: _vm.setUnit),
          ),
        ],
      ),
    ],
  );

  // ------------------------------------------------------------------- price

  Widget _priceCard(LogPriceState s) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final unitPrice = s.unitPrice;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MoneyField(
            controller: _amount,
            onCalculator: _useCalculator,
            label: s.isRange ? 'Lowest price' : 'Price',
            semanticLabel: 'Price',
            onChanged: _vm.setAmount,
            errorText: s.errors[LogPriceField.amount],
          ),
          if (s.isRange) ...[
            const SizedBox(height: Space.md),
            MoneyField(
              label: 'Highest price',
              semanticLabel: 'Highest price',
              fontSize: 28,
              onChanged: _vm.setAmountMax,
              errorText: s.errors[LogPriceField.amountMax],
            ),
          ],
          const SizedBox(height: Space.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  unitPrice?.label ?? '',
                  style: t.bodySmall?.copyWith(
                    fontFeatures: DaftarType.tabular,
                  ),
                ),
              ),
              Text('Range', style: t.bodySmall),
              DaftarSwitch(
                value: s.isRange,
                onChanged: (on) => _vm.setRange(on: on),
                label: 'Min–max range',
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------- where

  Widget _whereSection(LogPriceState s) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final types = ref.watch(globalPriceTypesProvider).value ?? const [];
    final place = s.place;
    final placeActive = !s.isGlobal;

    final placeButton = Squish(
      onTap: _pickPlace,
      child: Semantics(
        container: true,
        button: true,
        label: place == null ? 'Choose a place' : 'Place: ${place.name}',
        excludeSemantics: true,
        child: _whereButton(
          active: placeActive,
          dashed: !placeActive,
          child: Row(
            children: [
              Icon(
                Icons.place_outlined,
                size: 18,
                color: placeActive ? c.accentText : c.muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      place?.name ?? 'Choose a place',
                      style: t.titleMedium?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: place == null ? c.muted : c.text,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (placeActive && (s.placeHint ?? place?.address) != null)
                      Text(
                        s.placeHint ?? place!.address!,
                        style: t.bodySmall?.copyWith(fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final globalButton = Squish(
      onTap: _vm.useGlobal,
      child: Semantics(
        container: true,
        button: true,
        selected: s.isGlobal,
        label: 'Global price, not tied to a store',
        excludeSemantics: true,
        child: _whereButton(
          active: s.isGlobal,
          dashed: !s.isGlobal,
          limeBorder: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (s.isGlobal) ...[
                Icon(Icons.check_rounded, size: 18, color: c.accentText),
                const SizedBox(width: Space.xs + 2),
              ],
              Text(
                'Global',
                style: t.labelMedium?.copyWith(
                  color: s.isGlobal ? c.text : c.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Where'),
        const SizedBox(height: Space.sm),
        Row(
          children: [
            Expanded(child: placeButton),
            const SizedBox(width: Space.sm),
            globalButton,
          ],
        ),
        if (s.isGlobal) ...[
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.sm,
            children: [
              for (final type in types)
                SelectChip(
                  label: type.name,
                  selected: s.globalTypeId == type.id,
                  onTap: () => _vm.setGlobalType(type.id),
                ),
              SelectChip(
                label: '+ Type',
                isAdd: true,
                selected: false,
                onTap: _addGlobalType,
              ),
            ],
          ),
        ],
        if (s.errors[LogPriceField.where] != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Text(
              s.errors[LogPriceField.where]!,
              style: t.bodySmall?.copyWith(color: c.coral),
            ),
          ),
      ],
    );
  }

  Widget _whereButton({
    required bool active,
    required bool dashed,
    required Widget child,
    bool limeBorder = false,
  }) {
    final c = context.colors;
    final box = Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.centerLeft,
      decoration: dashed
          ? null
          : BoxDecoration(
              color: c.raised,
              borderRadius: Radii.inputR,
              border: Border.all(color: limeBorder ? c.lime : c.line),
            ),
      child: child,
    );
    return dashed ? DashedBorder(color: c.line, child: box) : box;
  }

  // ------------------------------------------------------------------- promo

  Widget _promoSection(LogPriceState s) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final ends = s.promoEndsAt;
    final now = ref.read(clockProvider)();
    return Column(
      children: [
        SwitchRow(
          title: 'Promo',
          value: s.isPromo,
          onChanged: (on) => _vm.setPromo(on: on),
        ),
        if (s.isPromo)
          DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.raised)),
            ),
            child: Semantics(
              container: true,
              button: true,
              label: ends == null
                  ? 'Set promo end date'
                  : 'Promo ends ${shortDate(ends, now)}',
              excludeSemantics: true,
              child: InkWell(
                onTap: () => _pickPromoEnd(ends),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 50),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Ends',
                          style: t.titleMedium?.copyWith(fontSize: 15),
                        ),
                      ),
                      Text(
                        ends == null ? 'No end date' : shortDate(ends, now),
                        style: t.bodyMedium?.copyWith(
                          color: s.errors[LogPriceField.promoEnd] != null
                              ? c.coral
                              : c.amber,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (ends != null)
                        IconButton(
                          tooltip: 'Clear end date',
                          icon: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: c.muted,
                          ),
                          onPressed: () => _vm.setPromoEnd(null),
                        )
                      else
                        const SizedBox(width: Space.sm),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (s.errors[LogPriceField.promoEnd] != null)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: Space.xs),
              child: Text(
                s.errors[LogPriceField.promoEnd]!,
                style: t.bodySmall?.copyWith(color: c.coral),
              ),
            ),
          ),
        // Turns the saved price into an expense on one of your accounts.
        SwitchRow(
          title: 'I bought it',
          hint: 'Pick the account after saving',
          value: _bought,
          bottomBorder: false,
          onChanged: (v) => setState(() => _bought = v),
        ),
      ],
    );
  }

  // ------------------------------------------------------------ photo + note

  Widget _photoNoteSection(LogPriceState s) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FieldLabel('Photo of the price tag', optional: true),
        const SizedBox(height: Space.sm),
        if (s.photoPath != null)
          Row(
            children: [
              ClipRRect(
                borderRadius: Radii.inputR,
                child: Image.file(
                  File(s.photoPath!),
                  width: 72,
                  height: 72,
                  fit: BoxFit.cover,
                  semanticLabel: 'Photo of the price tag',
                  errorBuilder: (_, _, _) => Container(
                    width: 72,
                    height: 72,
                    color: c.raised,
                    child: Icon(Icons.image_outlined, color: c.muted),
                  ),
                ),
              ),
              const SizedBox(width: Space.md),
              TextButton.icon(
                onPressed: _vm.removePhoto,
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                label: const Text('Remove'),
                style: TextButton.styleFrom(
                  foregroundColor: c.coral,
                  minimumSize: const Size(0, Chrome.minTouch),
                ),
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: _PhotoButton(
                  icon: Icons.photo_camera_outlined,
                  label: 'Take photo',
                  onTap: () => _vm.pickPhoto(PhotoSource.camera),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: _PhotoButton(
                  icon: Icons.photo_library_outlined,
                  label: 'Gallery',
                  onTap: () => _vm.pickPhoto(PhotoSource.gallery),
                ),
              ),
            ],
          ),
        const SizedBox(height: 18),
        const FieldLabel('Note', optional: true),
        const SizedBox(height: Space.sm),
        TextField(
          controller: _note,
          textDirection: null,
          textCapitalization: TextCapitalization.sentences,
          minLines: 1,
          maxLines: 3,
          onChanged: _vm.setNote,
          style: t.bodyMedium,
          decoration: boardInput(context, hint: 'Anything worth remembering'),
        ),
      ],
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({
    required this.suggestions,
    required this.typed,
    required this.onPick,
    required this.onNew,
  });

  final List<Product> suggestions;
  final String typed;
  final ValueChanged<Product> onPick;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: Radii.inputR,
        border: Border.all(color: c.line),
      ),
      child: Column(
        children: [
          for (final p in suggestions)
            Semantics(
              container: true,
              button: true,
              label: [p.name, ?p.brand].join(', '),
              excludeSemantics: true,
              child: InkWell(
                onTap: () => onPick(p),
                borderRadius: Radii.inputR,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: Chrome.minTouch),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.lg - 2,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            p.name,
                            style: t.titleMedium?.copyWith(fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (p.brand != null) Text(p.brand!, style: t.bodySmall),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Semantics(
            container: true,
            button: true,
            label: 'Add $typed as a new product',
            excludeSemantics: true,
            child: InkWell(
              onTap: onNew,
              borderRadius: Radii.inputR,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: Chrome.minTouch),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg - 2),
                  child: Row(
                    children: [
                      Icon(Icons.add_rounded, size: 18, color: c.muted),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Text(
                          'New product “$typed”',
                          style: t.bodyMedium?.copyWith(color: c.muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarcodeNote extends StatelessWidget {
  const _BarcodeNote({required this.state});

  final LogPriceState state;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final (text, icon) = switch (state.lookup) {
      LookupStatus.loading => (
        'Looking up ${state.barcode}…',
        Icons.search_rounded,
      ),
      LookupStatus.foundLocal => (
        'Already in your notebook · ${state.barcode}',
        Icons.qr_code_2_rounded,
      ),
      LookupStatus.foundOff => (
        'Filled in from Open Food Facts · ${state.barcode}',
        Icons.cloud_done_outlined,
      ),
      LookupStatus.notFound => (
        'Not found online. Type it in · ${state.barcode}',
        Icons.edit_outlined,
      ),
      LookupStatus.offline => (
        'Offline. Type it in · ${state.barcode}',
        Icons.cloud_off_outlined,
      ),
      LookupStatus.idle => (
        'Barcode ${state.barcode}',
        Icons.qr_code_2_rounded,
      ),
    };
    return Row(
      children: [
        Icon(icon, size: 16, color: c.muted),
        const SizedBox(width: Space.sm),
        Expanded(
          child: state.lookup == LookupStatus.loading
              ? const Skeleton(height: 14)
              : Text(
                  text,
                  style: t.bodySmall?.copyWith(fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
      ],
    );
  }
}

class _PhotoButton extends StatelessWidget {
  const _PhotoButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      button: true,
      label: label,
      excludeSemantics: true,
      child: Squish(
        onTap: onTap,
        child: Container(
          height: Chrome.minTouch,
          decoration: BoxDecoration(
            color: c.raised,
            borderRadius: Radii.inputR,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: c.text),
              const SizedBox(width: Space.sm),
              Text(
                label,
                style: t.labelMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The one lime action: a floating-looking pill (brand board: 60 px, radius 30).
class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.saving, required this.onTap});

  final bool saving;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      button: true,
      label: 'Save price',
      enabled: !saving,
      excludeSemantics: true,
      child: Squish(
        onTap: saving ? null : onTap,
        child: Container(
          height: 60,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.lime,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: c.lime.withValues(alpha: 0.22),
                blurRadius: 36,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: saving
              ? SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: c.onLime,
                  ),
                )
              : Text(
                  'Save price',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: c.onLime,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
        ),
      ),
    );
  }
}
