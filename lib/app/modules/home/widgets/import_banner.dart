import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// "You have N new transactions to review" — opens the review screen.
class ImportBanner extends StatelessWidget {
  const ImportBanner({super.key, required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primarySoft,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.inbox_outlined, color: AppColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text('لديك $count حركات جديدة للمراجعة',
                    style: const TextStyle(
                        color: AppColors.primaryDark, fontSize: 13)),
              ),
              const Icon(Icons.chevron_left, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
