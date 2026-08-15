import 'package:flutter/material.dart';

import '../theme.dart';
import 'placeholder_page.dart';

/// 生活 Tab(本批为占位页)
class LifePage extends StatelessWidget {
  const LifePage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              '生活',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textMain,
              ),
            ),
          ),
          const Expanded(
            child: PlaceholderPage(
              icon: Icons.emoji_emotions_rounded,
              title: '生活广场',
              description: '记录生活的点滴,敬请期待',
            ),
          ),
        ],
      ),
    );
  }
}
