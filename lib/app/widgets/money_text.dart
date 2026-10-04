import 'package:flutter/material.dart';

import '../core/utils/currencies.dart';
import '../core/utils/money.dart';

/// An amount with its currency symbol. The number is wrapped in a
/// left-to-right isolate so "-12.500" keeps its minus sign on the left inside
/// Arabic text.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.amount, {
    super.key,
    required this.currency,
    this.style,
    this.showPlus = false,
    this.showSymbol = true,
  });

  final int amount;
  final Currency currency;
  final TextStyle? style;
  final bool showPlus;
  final bool showSymbol;

  @override
  Widget build(BuildContext context) {
    final number =
        Money.format(amount, decimals: currency.decimals, showPlus: showPlus);
    final text = '\u2066$number\u2069';
    return Text(showSymbol ? '$text ${currency.symbol}' : text, style: style);
  }
}
