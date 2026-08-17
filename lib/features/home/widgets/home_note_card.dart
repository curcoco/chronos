import 'package:flutter/material.dart';

import 'package:student_workbench/core/theme.dart';
import 'package:student_workbench/core/widgets/app_text_field.dart';
import 'package:student_workbench/core/widgets/section_card.dart';

/// 首页灵感速记卡:单行输入 + 提交按钮 + 写日记入口。
class HomeNoteCard extends StatelessWidget {
  final TextEditingController controller;
  final bool saving;
  final VoidCallback onSubmit;
  final VoidCallback onOpenDiary;

  const HomeNoteCard({
    super.key,
    required this.controller,
    required this.saving,
    required this.onSubmit,
    required this.onOpenDiary,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: '灵感速记',
      trailing: TextButton.icon(
        onPressed: onOpenDiary,
        icon: Icon(Icons.menu_book_rounded,
            size: 16, color: AppColors.primaryDark),
        label: Text('写日记',
            style: TextStyle(fontSize: 13, color: AppColors.primaryDark)),
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '碎片灵感随手记;想写成篇的心情日记点右上角',
            style: TextStyle(fontSize: 11, color: AppColors.textSub),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AppTextField(
                  controller: controller,
                  maxLength: 80,
                  hintText: '记下一句话灵感…',
                  onSubmit: onSubmit,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 52,
                height: 46,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(52, 46),
                    shape: const CircleBorder(),
                  ),
                  onPressed: saving ? null : onSubmit,
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.send_rounded, size: 20),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
