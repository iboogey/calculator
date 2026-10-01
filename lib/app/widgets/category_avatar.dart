import 'package:flutter/material.dart';

import '../core/theme/category_icons.dart';
import '../data/models/transaction_category.dart';

class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({super.key, required this.category, this.size = 40});

  final TransactionCategory category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Color(category.colorValue);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(CategoryIcons.of(category.iconKey),
          color: color, size: size * 0.5),
    );
  }
}
