import 'package:flutter/material.dart';

/// Maps a category's stored icon key to an icon.
abstract final class CategoryIcons {
  static const Map<String, IconData> _icons = {
    'food': Icons.restaurant,
    'transport': Icons.directions_car_outlined,
    'bills': Icons.bolt,
    'housing': Icons.home_outlined,
    'shopping': Icons.shopping_bag_outlined,
    'entertainment': Icons.movie_outlined,
    'health': Icons.medical_services_outlined,
    'other': Icons.more_horiz,
    'salary': Icons.payments_outlined,
    'income_other': Icons.attach_money,
  };

  static IconData of(String key) => _icons[key] ?? Icons.category_outlined;
}
