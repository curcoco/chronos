import 'package:flutter/material.dart';

import 'package:chronos/core/theme.dart';
import 'package:chronos/core/widgets/section_card.dart';

/// 首页每日英语一句卡。
class HomeEnglishCard extends StatelessWidget {
  final String en;
  final String zh;

  const HomeEnglishCard({super.key, required this.en, required this.zh});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '每日英语一句',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            en,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            zh,
            style: TextStyle(fontSize: 13, color: AppColors.textSub),
          ),
        ],
      ),
    );
  }
}
