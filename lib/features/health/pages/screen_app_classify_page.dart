import 'package:flutter/material.dart';

import 'package:chronos/core/theme.dart';
import 'package:chronos/features/health/services/screen_time_service.dart';

/// 「app 分类」管理页:把已装 app 标成 娱乐 / 学习 / 工具。
/// 内置预设(常见娱乐 app)自动生效,用户手动分类优先于预设;
/// 清单外 app 默认按工具计(不影响娱乐统计)。
class ScreenAppClassifyPage extends StatefulWidget {
  const ScreenAppClassifyPage({super.key});

  @override
  State<ScreenAppClassifyPage> createState() => _ScreenAppClassifyPageState();
}

class _ScreenAppClassifyPageState extends State<ScreenAppClassifyPage> {
  final ScreenTimeService _service = ScreenTimeService.instance;

  Map<String, String> _labels = {}; // 包名 → 显示名
  Map<String, String> _overrides = {}; // 包名 → 用户自定义分类
  final Map<String, String> _searchIndex = {}; // 小写检索缓存
  String _query = '';
  String _filter = 'all'; // all / entertainment / study / tool / none
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final labels = await _service.appLabels(refresh: true);
    final overrides = await _service.categories();
    if (!mounted) return;
    setState(() {
      _labels = labels;
      _searchIndex
        ..clear()
        ..addAll({
          for (final e in labels.entries)
            e.key: '${e.value} ${e.key}'.toLowerCase(),
        });
      _overrides = overrides;
      _loading = false;
    });
  }

  /// 生效分类(null = 未分类:无自定义且不在预设里,按工具计)。
  String? _effectiveCategory(String pkg) {
    final o = _overrides[pkg];
    if (o == ScreenTimeService.catEntertainment ||
        o == ScreenTimeService.catStudy ||
        o == ScreenTimeService.catTool) {
      return o;
    }
    if (ScreenTimeService.builtinEntertainment.containsKey(pkg)) {
      return ScreenTimeService.catEntertainment;
    }
    return null;
  }

  List<String> get _filtered {
    final q = _query.trim().toLowerCase();
    return _labels.keys.where((pkg) {
      final cat = _effectiveCategory(pkg);
      if (_filter == 'entertainment' && cat != ScreenTimeService.catEntertainment) {
        return false;
      }
      if (_filter == 'study' && cat != ScreenTimeService.catStudy) return false;
      if (_filter == 'tool' && cat != ScreenTimeService.catTool) return false;
      if (_filter == 'none' && cat != null) return false;
      if (q.isNotEmpty) {
        final idx = _searchIndex[pkg] ?? pkg.toLowerCase();
        if (!idx.contains(q)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) =>
          (_labels[a] ?? a).compareTo(_labels[b] ?? b));
  }

  Future<void> _pickCategory(String pkg) async {
    final current = _overrides[pkg];
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                _labels[pkg] ?? pkg,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
            for (final c in [
              (ScreenTimeService.catEntertainment, '娱乐', Icons.videogame_asset_outlined),
              (ScreenTimeService.catStudy, '学习', Icons.menu_book_outlined),
              (ScreenTimeService.catTool, '工具', Icons.construction_outlined),
            ])
              ListTile(
                leading: Icon(c.$3,
                    size: 20,
                    color: current == c.$1
                        ? AppColors.primary
                        : AppColors.textSub),
                title: Text(c.$2),
                trailing: current == c.$1
                    ? Icon(Icons.check_rounded,
                        size: 20, color: AppColors.primary)
                    : null,
                onTap: () => Navigator.pop(context, c.$1),
              ),
            if (current != null)
              ListTile(
                leading: Icon(Icons.undo_rounded,
                    size: 20, color: AppColors.textSub),
                title: const Text('恢复默认'),
                subtitle: Text('清除自定义,回到内置预设/按工具计',
                    style:
                        TextStyle(fontSize: 11, color: AppColors.textSub)),
                onTap: () => Navigator.pop(context, '__reset__'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null) return;
    await _service.setCategory(
        pkg, choice == '__reset__' ? null : choice);
    _load();
  }

  Widget _categoryChip(String? category) {
    final (label, fg, bg) = switch (category) {
      ScreenTimeService.catEntertainment => ('娱乐', Colors.white, AppColors.primary),
      ScreenTimeService.catStudy =>
        ('学习', Colors.white, const Color(0xFF43A047)),
      ScreenTimeService.catTool => ('工具', AppColors.textSub, AppColors.card),
      _ => ('未分类', AppColors.textSub, AppColors.card),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: category == null || category == ScreenTimeService.catTool
                ? AppColors.line
                : Colors.transparent),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11,
              color: fg,
              fontWeight: FontWeight.w600)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final apps = _filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('app 分类')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                  child: TextField(
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      hintText: '搜索名称或包名',
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.line),
                      ),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      for (final c in [
                        ('all', '全部'),
                        ('entertainment', '娱乐'),
                        ('study', '学习'),
                        ('tool', '工具'),
                        ('none', '未分类'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(c.$2),
                            selected: _filter == c.$1,
                            onSelected: (_) =>
                                setState(() => _filter = c.$1),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: apps.isEmpty
                      ? Center(
                          child: Text('没有匹配的 app',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.textSub)),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                          itemCount: apps.length,
                          itemBuilder: (context, i) {
                            final pkg = apps[i];
                            final label = _labels[pkg] ?? pkg;
                            final isBuiltin = ScreenTimeService
                                .builtinEntertainment
                                .containsKey(pkg);
                            final overridden =
                                _overrides.containsKey(pkg);
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: AppColors.primarySoft,
                                child: Text(
                                  label.characters.first.toUpperCase(),
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primaryDark),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Flexible(
                                    child: Text(label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600)),
                                  ),
                                  if (isBuiltin && !overridden) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: AppColors.primarySoft,
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: Text('预设',
                                          style: TextStyle(
                                              fontSize: 9,
                                              color: AppColors
                                                  .onPrimarySoft)),
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Text(pkg,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: AppColors.textSub)),
                              trailing: _categoryChip(
                                  _effectiveCategory(pkg)),
                              onTap: () => _pickCategory(pkg),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
