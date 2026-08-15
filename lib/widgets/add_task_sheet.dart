import 'package:flutter/material.dart';

import '../theme.dart';

/// 添加任务弹层返回的数据
class AddTaskResult {
  final String title;
  final String category;
  final int priority;
  const AddTaskResult({
    required this.title,
    required this.category,
    required this.priority,
  });
}

/// 「添加今日任务」底部弹层:分类 / 优先级 / 文本(手写模式)
class AddTaskSheet extends StatefulWidget {
  const AddTaskSheet({super.key});

  @override
  State<AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends State<AddTaskSheet> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _categoryCtrl =
      TextEditingController(text: '学习');
  int _priority = 1; // 默认中

  static const List<String> _categories =
      ['学习', '英语', '阅读', '运动', '生活', '成长', '其他'];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _categoryCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    final category = _categoryCtrl.text.trim().isEmpty
        ? '学习'
        : _categoryCtrl.text.trim();
    Navigator.of(context).pop(
      AddTaskResult(title: title, category: category, priority: _priority),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Center(
            child: Text(
              '添加今日任务',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _titleCtrl,
            autofocus: true,
            maxLength: 30,
            decoration: const InputDecoration(
              labelText: '任务内容',
              hintText: '今天要做什么?',
              counterText: '',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _categoryCtrl,
            maxLength: 6,
            decoration: const InputDecoration(
              labelText: '分类',
              counterText: '',
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final c in _categories)
                ActionChip(
                  label: Text(c),
                  labelStyle: const TextStyle(fontSize: 13),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: _categoryCtrl.text == c
                      ? AppColors.primaryLight
                      : Colors.white,
                  side: BorderSide(
                    color: _categoryCtrl.text == c
                        ? AppColors.primary
                        : AppColors.line,
                  ),
                  onPressed: () {
                    setState(() => _categoryCtrl.text = c);
                  },
                ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            '优先级',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _priorityChip(0, '高', const Color(0xFFEF5350)),
              const SizedBox(width: 10),
              _priorityChip(1, '中', const Color(0xFFFFA726)),
              const SizedBox(width: 10),
              _priorityChip(2, '低', const Color(0xFF66BB6A)),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _submit,
            child: const Text('保存任务'),
          ),
        ],
      ),
    );
  }

  Widget _priorityChip(int value, String label, Color color) {
    final selected = _priority == value;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _priority = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.14) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : AppColors.line,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? color : AppColors.textSub,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
