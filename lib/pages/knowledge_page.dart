import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/module_card.dart';
import 'english_page.dart';

/// 知识 Tab:第二批模块入口(英文积累等)
class KnowledgePage extends StatelessWidget {
  const KnowledgePage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text(
              '知识',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.textMain,
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              '每日学习与积累',
              style: TextStyle(fontSize: 13, color: AppColors.textSub),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                ModuleCard(
                  icon: Icons.translate_rounded,
                  title: '英文积累',
                  desc: '每日一句 / 单词 / 阅读 / 写作,可收藏,打卡领金币',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const EnglishPage()),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
