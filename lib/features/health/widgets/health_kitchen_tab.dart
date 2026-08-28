import 'package:flutter/material.dart';

import 'package:chronos/core/data/health_content.dart';
import 'package:chronos/features/health/models/kitchen_item.dart';
import 'package:chronos/features/health/services/health_service.dart';
import 'package:chronos/core/services/app_log.dart';
import 'package:chronos/core/theme.dart';
import 'package:chronos/core/widgets/confirm_dialog.dart';
import 'package:chronos/core/widgets/frosted_snack.dart';
import 'package:chronos/features/health/widgets/health_common.dart';

/// 健康「厨房秘籍」Tab:按分类浏览 / 添加 / 删除菜品。
class HealthKitchenTab extends StatefulWidget {
  final HealthService service;
  final List<KitchenItem> items;

  /// 增删后由父级刷新数据。
  final VoidCallback onChanged;

  const HealthKitchenTab({
    super.key,
    required this.service,
    required this.items,
    required this.onChanged,
  });

  @override
  State<HealthKitchenTab> createState() => _HealthKitchenTabState();
}

class _HealthKitchenTabState extends State<HealthKitchenTab> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _cal = TextEditingController();
  final TextEditingController _price = TextEditingController();
  final TextEditingController _link = TextEditingController();
  String _cat = '菜品';
  String _newCat = '菜品';

  @override
  void dispose() {
    _name.dispose();
    _cal.dispose();
    _price.dispose();
    _link.dispose();
    super.dispose();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    showFrostedSnack(context, msg);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _showSnack('请输入名称');
      return;
    }
    // 输入校验:填了但格式不对要明确提示,不再静默存 0。
    final calRaw = _cal.text.trim();
    final priceRaw = _price.text.trim();
    if (calRaw.isNotEmpty && int.tryParse(calRaw) == null) {
      _showSnack('卡路里请输入整数');
      return;
    }
    if (priceRaw.isNotEmpty && double.tryParse(priceRaw) == null) {
      _showSnack('价格请输入数字');
      return;
    }
    final cal = int.tryParse(calRaw) ?? 0;
    final price = double.tryParse(priceRaw) ?? 0;
    if (cal < 0 || price < 0) {
      _showSnack('数值不能为负');
      return;
    }
    try {
      await widget.service.addKitchenItem(
        cat: _newCat,
        name: name,
        cal: cal,
        price: price,
        link: _link.text.trim(),
      );
      _name.clear();
      _cal.clear();
      _price.clear();
      _link.clear();
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onChanged();
      _showSnack('已添加');
    } catch (e) {
      AppLog.instance.e('添加厨房条目失败:$e');
      if (!mounted) return;
      _showSnack('添加失败,请重试');
    }
  }

  Future<void> _delete(KitchenItem item) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除这条记录?',
      message: '「${item.name}」',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await widget.service.deleteKitchenItem(item.id!);
      widget.onChanged();
    } catch (e) {
      AppLog.instance.e('删除厨房条目失败:$e');
      _showSnack('删除失败,请重试');
    }
  }

  void _openSheet() {
    _newCat = _cat;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
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
              child: Text('添加条目',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '名称'),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                for (final c in HealthContent.kitchenCats)
                  CatChip(
                    label: c,
                    selected: c == _newCat,
                    onTap: () => setState(() => _newCat = c),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cal,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: '卡路里(kcal/份)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: '价格(元)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _link,
              decoration: const InputDecoration(
                  labelText: '教程视频链接(选填)'),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _save, child: const Text('保存')),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = widget.items.where((k) => k.cat == _cat).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final c in HealthContent.kitchenCats)
              CatChip(
                label: c,
                selected: c == _cat,
                onTap: () => setState(() => _cat = c),
              ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.card,
            foregroundColor: AppColors.primaryDark,
            side: BorderSide(color: AppColors.primary),
          ),
          onPressed: _openSheet,
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('添加条目'),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(
              child: Text('这个分类还没有内容',
                  style: TextStyle(color: AppColors.textSub)),
            ),
          )
        else
          for (final k in list) _tile(k),
      ],
    );
  }

  Widget _tile(KitchenItem k) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(k.name, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  '${k.cal > 0 ? '约 ${k.cal} kcal' : '无卡路里'}'
                  '${k.link.isNotEmpty ? ' · 视频链接' : ''}',
                  style: TextStyle(fontSize: 11, color: AppColors.textSub),
                ),
              ],
            ),
          ),
          Text(money(k.price),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSub)),
          IconButton(
            onPressed: () => _delete(k),
            icon: Icon(Icons.close_rounded,
                size: 18, color: AppColors.textSub),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
