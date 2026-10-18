import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/daftar_colors.dart';
import '../../../core/theme/daftar_tokens.dart';
import '../../../core/theme/daftar_typography.dart';

/// Big input for a TND-per-USD rate such as "3.1250" (up to four decimals).
/// The caller parses the text with `RateMath.tryParseRate`.
class RateField extends StatelessWidget {
  const RateField({
    super.key,
    required this.controller,
    this.onChanged,
    this.label = 'TND per 1 USD',
    this.autofocus = false,
    this.errorText,
    this.fontSize = 40,
  });

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String label;
  final bool autofocus;
  final String? errorText;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = Theme.of(context).textTheme;
    final style = DaftarType.price(fontSize, c.text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: t.bodySmall),
        const SizedBox(height: Space.xs),
        Semantics(
          textField: true,
          label: label,
          child: TextField(
            controller: controller,
            autofocus: autofocus,
            textDirection: null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [_RateFormatter()],
            style: style,
            cursorColor: c.lime,
            onChanged: onChanged,
            decoration: InputDecoration(
              isCollapsed: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: '0.0000',
              hintStyle: style.copyWith(color: c.line),
              contentPadding: const EdgeInsets.symmetric(vertical: Space.xs),
            ),
          ),
        ),
        if (errorText != null)
          Text(errorText!, style: t.bodySmall?.copyWith(color: c.coral)),
      ],
    );
  }
}

class _RateFormatter extends TextInputFormatter {
  static final _pattern = RegExp(r'^\d{0,6}([.,]\d{0,4})?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => _pattern.hasMatch(newValue.text) ? newValue : oldValue;
}
