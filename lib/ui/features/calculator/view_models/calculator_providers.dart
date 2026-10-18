import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/calc/calc_expression.dart';
import '../../../../domain/calc/calc_keys.dart';
import '../../../../domain/models/basket.dart';
import '../../../../domain/models/ids.dart';
import '../../../../domain/models/money.dart';
import '../../../core/widgets/money_field.dart';

/// The four modes of the Calculator card, in chip order.
enum CalculatorMode {
  quick('Quick', Icons.dialpad_rounded),
  basket('Basket', Icons.shopping_basket_outlined),
  bestStore('Best store', Icons.storefront_outlined),
  split('Split', Icons.call_split_rounded);

  const CalculatorMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Which mode chip is selected. The best-store and split modes read this to know
/// when they are active.
class CalculatorModeNotifier extends Notifier<CalculatorMode> {
  @override
  CalculatorMode build() => CalculatorMode.quick;

  void select(CalculatorMode mode) => state = mode;
}

final calculatorModeProvider =
    NotifierProvider<CalculatorModeNotifier, CalculatorMode>(
      CalculatorModeNotifier.new,
    );

/// Quick mode: the typed expression and the last few results.
class QuickCalcState {
  const QuickCalcState({this.expression = '', this.history = const []});

  final String expression;

  /// Newest first, at most [QuickCalcNotifier.historyLimit].
  final List<Money> history;

  /// Live result of [expression] (null when blank).
  CalcResult? get result => CalcExpression.evaluate(expression);

  QuickCalcState copyWith({String? expression, List<Money>? history}) =>
      QuickCalcState(
        expression: expression ?? this.expression,
        history: history ?? this.history,
      );
}

class QuickCalcNotifier extends Notifier<QuickCalcState> {
  static const historyLimit = 5;

  @override
  QuickCalcState build() => const QuickCalcState();

  void press(CalcKey key) {
    state = state.copyWith(expression: CalcEditor.press(state.expression, key));
  }

  /// "=": the result becomes the expression and joins the history.
  void equals() {
    final value = state.result?.value;
    if (value == null) return;
    final history = [
      value,
      ...state.history.where((m) => m != value),
    ].take(historyLimit).toList();
    state = QuickCalcState(expression: _expressionFor(value), history: history);
  }

  /// Puts an earlier result back on the display.
  void recall(Money value) {
    state = state.copyWith(expression: _expressionFor(value));
  }

  void clearHistory() => state = state.copyWith(history: const []);

  /// "4.4" rather than "4.400": trailing zeros are noise on the keypad.
  static String _expressionFor(Money value) {
    var text = moneyInputText(value);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'\.?0+$'), '');
    }
    return text.startsWith('-') ? '−${text.substring(1)}' : text;
  }
}

final quickCalcProvider = NotifierProvider<QuickCalcNotifier, QuickCalcState>(
  QuickCalcNotifier.new,
);

/// The current basket, kept in memory only (saved lists are a later task).
/// Best store and Split read this provider.
class BasketNotifier extends Notifier<Basket> {
  @override
  Basket build() => const Basket();

  void add({
    required String name,
    required Money unitPrice,
    int quantity = 1,
    String? productId,
    String? variantId,
  }) {
    state = state.add(
      BasketItem(
        id: newId(),
        name: name.trim(),
        unitPrice: unitPrice,
        quantity: quantity,
        productId: productId,
        variantId: variantId,
      ),
    );
  }

  void setQuantity(String itemId, int quantity) =>
      state = state.setQuantity(itemId, quantity);

  void remove(String itemId) => state = state.remove(itemId);

  void setPlace({String? id, String? name}) =>
      state = state.withPlace(id: id, name: name);

  void clear() => state = state.cleared();
}

final basketProvider = NotifierProvider<BasketNotifier, Basket>(
  BasketNotifier.new,
);
