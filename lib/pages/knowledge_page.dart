import 'package:flutter/material.dart';

import '../theme.dart';
import 'placeholder_page.dart';

/// 知识 Tab(本批为占位页)
class KnowledgePage extends StatelessWidget {
  const KnowledgePage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(
              '知识',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textMain,
              ),
            ),
          ),
          const Expanded(
            child: PlaceholderPage(
              icon: Icons.school_rounded,
              title: '知识星球',
              description: '学习资料与知识库正在筹备中,敬请期待',
            ),
          ),
        ],
      ),
    );
  }
}
