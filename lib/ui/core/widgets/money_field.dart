import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../domain/models/money.dart';
import '../theme/daftar_colors.dart';
import '../theme/daftar_tokens.dart';
import '../theme/daftar_typography.dart';

/// Plain text for a money input: "4.400" (no thousands grouping, so the text can
/// be parsed back by [Money.tryParse]).
String moneyInputText(Money money) =>
    '${money.minor < 0 ? '-' : ''}${(money.minor.abs() ~/ money.currency.unit)}.'
    '${(money.minor.abs() % money.currency.unit).toString().padLeft(money.currency.decimals, '0')}';

/// Parses what the user typed, tolerating a trailing separator ("4." or "4,").
Money? parseMoneyInput(String text, {Currency currency = Currency.tnd}) {
  var t = text.trim();
  if (t.endsWith('.') || t.endsWith(',')) t = t.substring(0, t.length - 1);
  if (t.isEmpty) return null;
  return Money.tryParse(t, currency: currency);
}

/// Big, tabular price input (TND by default).
///
/// * numeric keyboard with a decimal key; `,` and `.` are both accepted
///   (Arabic-Indic digits are converted), at most [Currency.decimals] decimals;
/// * formats to `4.400` when it loses focus;
/// * reports a parsed [Money] (or null) through [onChanged];
/// * an optional calculator button ([onCalculator]) sits at the end of the label row.
class MoneyField extends StatefulWidget {
  const MoneyField({
    super.key,
    this.controller,
    this.focusNode,
    this.initialValue,
    this.onChanged,
    this.label,
    this.onCalculator,
    this.currency = Currency.tnd,
    this.fontSize = 48,
    this.errorText,
    this.enabled = true,
    this.autofocus = false,
    this.semanticLabel,
  });

  /// Optional; the field creates its own when null.
  final TextEditingController? controller;
  final FocusNode? focusNode;

  /// Used only when no [controller] is given.
  final Money? initialValue;
  final ValueChanged<Money?>? onChanged;
  final String? label;

  /// Shows the calculator button when set.
  final VoidCallback? onCalculator;
  final Currency currency;

  /// Size of the number; the big "Log a price" input uses the default 48.
  final double fontSize;
  final String? errorText;
  final bool enabled;
  final bool autofocus;
  final String? semanticLabel;

  @override
  State<MoneyField> createState() => _MoneyFieldState();
}

class _MoneyFieldState extends State<MoneyField> {
  late final TextEditingController _controller;
  late final FocusNode _focus;
  late final bool _ownsController;
  late final bool _ownsFocus;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _ownsFocus = widget.focusNode == null;
    _controller =
        widget.controller ??
        TextEditingController(
          text: widget.initialValue == null
              ? ''
              : moneyInputText(widget.initialValue!),
        );
    _focus = widget.focusNode ?? FocusNode();
    _focus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    if (_ownsFocus) _focus.dispose();
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focus.hasFocus) return;
    final money = parseMoneyInput(_controller.text, currency: widget.currency);
    if (money == null) return;
    final formatted = moneyInputText(money);
    if (formatted != _controller.text) {
      _controller.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final showHeader = widget.label != null || widget.onCalculator != null;
    final priceStyle = DaftarType.price(widget.fontSize, c.text);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showHeader)
          SizedBox(
            height: Chrome.minTouch,
            child: Row(
              children: [
                Expanded(child: Text(widget.label ?? '', style: t.bodySmall)),
                if (widget.onCalculator != null)
                  Semantics(
                    container: true,
                    button: true,
                    label: 'Open calculator',
                    excludeSemantics: true,
                    child: InkResponse(
                      onTap: widget.onCalculator,
                      radius: 24,
                      child: SizedBox.square(
                        dimension: Chrome.minTouch,
                        child: Center(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: c.raised,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: SizedBox.square(
                              dimension: 36,
                              child: Icon(
                                Icons.calculate_outlined,
                                size: 18,
                                color: c.text,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Semantics(
                label: widget.semanticLabel ?? widget.label ?? 'Price',
                textField: true,
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  autofocus: widget.autofocus,
                  textDirection: null,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  inputFormatters: [
                    _MoneyInputFormatter(widget.currency.decimals),
                  ],
                  style: priceStyle,
                  cursorColor: c.lime,
                  onChanged: (text) => widget.onChanged?.call(
                    parseMoneyInput(text, currency: widget.currency),
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    hintText: moneyInputText(Money(0, widget.currency)),
                    hintStyle: priceStyle.copyWith(color: c.line),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ),
            const SizedBox(width: Space.sm),
            Text(
              widget.currency.code,
              style: DaftarType.price(
                widget.fontSize * 0.375,
                c.muted,
              ).copyWith(letterSpacing: 0),
            ),
          ],
        ),
        if (widget.errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Text(
              widget.errorText!,
              style: t.bodySmall?.copyWith(color: c.coral),
            ),
          ),
      ],
    );
  }
}

/// Allows digits with one `.` or `,` and a limited number of decimals. Arabic-Indic
/// digits and the Arabic decimal mark are converted to ASCII first.
class _MoneyInputFormatter extends TextInputFormatter {
  _MoneyInputFormatter(int decimals)
    : _pattern = RegExp('^\\d{0,9}([.,]\\d{0,$decimals})?\$');

  final RegExp _pattern;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = _ascii(newValue.text);
    if (!_pattern.hasMatch(text)) return oldValue;
    return text == newValue.text ? newValue : newValue.copyWith(text: text);
  }

  static String _ascii(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune >= 0x0660 && rune <= 0x0669) {
        buffer.write(rune - 0x0660);
      } else if (rune >= 0x06F0 && rune <= 0x06F9) {
        buffer.write(rune - 0x06F0);
      } else if (rune == 0x066B) {
        buffer.write('.');
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }
}
