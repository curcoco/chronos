import 'package:flutter/material.dart';

import 'package:chronos/core/theme.dart';

/// 模型选择弹窗(参考 RikkaHub 的 ModelPicker):展示服务商拉取的全部模型,
/// 搜索 + 勾选加入。「确定」返回选中的模型集合(含调用方已存在的)。
class ModelPickerSheet extends StatefulWidget {
  final List<String> allModels;
  final Set<String> existing;

  const ModelPickerSheet({
    super.key,
    required this.allModels,
    required this.existing,
  });

  @override
  State<ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<ModelPickerSheet> {
  late final Set<String> _selected = {...widget.existing};
  String _query = '';

  List<String> get _filtered {
    if (_query.trim().isEmpty) return widget.allModels;
    final q = _query.trim().toLowerCase();
    return [
      for (final m in widget.allModels)
        if (m.toLowerCase().contains(q)) m,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('从服务商获取模型',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      if (_selected.length < widget.allModels.length) {
                        _selected.addAll(widget.allModels);
                      } else {
                        _selected
                          ..clear()
                          ..addAll(widget.existing);
                      }
                    });
                  },
                  child: Text(
                    _selected.length < widget.allModels.length
                        ? '全选'
                        : '取消全选',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: '搜索模型…',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() => _query = ''),
                      ),
                isDense: true,
                filled: true,
                fillColor: AppColors.card,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                      color: AppColors.textSub.withValues(alpha: 0.55),
                      width: 1.4),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 320,
              child: _filtered.isEmpty
                  ? Center(
                      child: Text('没有匹配的模型',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textSub)),
                    )
                  : ListView.builder(
                      itemCount: _filtered.length,
                      itemBuilder: (context, i) {
                        final m = _filtered[i];
                        final checked = _selected.contains(m);
                        return ListTile(
                          dense: true,
                          leading: Icon(
                            checked
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 20,
                            color: checked
                                ? AppColors.primaryDark
                                : AppColors.textSub,
                          ),
                          title: Text(m,
                              style: const TextStyle(fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          trailing: widget.existing.contains(m)
                              ? Text('已添加',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSub))
                              : null,
                          onTap: () => setState(() {
                            if (checked) {
                              // 取消时保留"已添加"的(它们已在提供商里)。
                              if (!widget.existing.contains(m)) {
                                _selected.remove(m);
                              }
                            } else {
                              _selected.add(m);
                            }
                          }),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                ),
                onPressed: () => Navigator.of(context).pop(_selected),
                child: const Text('确定'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
