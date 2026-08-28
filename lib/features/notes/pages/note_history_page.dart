import 'package:flutter/material.dart';

import 'package:chronos/features/notes/models/note.dart';
import 'package:chronos/routes.dart';
import 'package:chronos/features/notes/services/note_service.dart';
import 'package:chronos/core/services/app_log.dart';
import 'package:chronos/core/theme.dart';
import 'package:chronos/core/utils/dates.dart';
import 'package:chronos/core/widgets/confirm_dialog.dart';
import 'package:chronos/core/widgets/frosted_snack.dart';
import 'package:chronos/core/widgets/mood_badge.dart';
import 'package:chronos/core/widgets/status_views.dart';
import 'package:chronos/features/notes/pages/note_detail_page.dart';

enum _Range { all, today, yesterday, week7, month30 }

/// 灵感速记历史记录页:关键字搜索 + 日期筛选(快捷 + 自定义「更多」),纯文本时间线
class NoteHistoryPage extends StatefulWidget {
  const NoteHistoryPage({super.key});

  @override
  State<NoteHistoryPage> createState() => _NoteHistoryPageState();
}

class _NoteHistoryPageState extends State<NoteHistoryPage> {
  final NoteService _noteService = NoteService();
  final TextEditingController _kwCtrl = TextEditingController();

  List<Note> _all = [];
  bool _loading = true;
  String? _loadError; // 记录加载失败(渲染 ErrorView + 重试)
  String _kw = '';
  _Range _range = _Range.all;
  String _from = '';
  String _to = '';
  bool _customOpen = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _kwCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final notes = await _noteService.notes();
      if (!mounted) return;
      setState(() {
        _all = notes;
        _loading = false;
        _loadError = null;
      });
    } catch (e) {
      AppLog.instance.e('速记记录加载失败:$e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '记录加载失败,请重试';
      });
    }
  }

  bool get _hasFilter =>
      _kw.trim().isNotEmpty ||
      _range != _Range.all ||
      _from.isNotEmpty ||
      _to.isNotEmpty;

  List<Note> get _filtered {
    final q = _kw.trim().toLowerCase();
    final now = DateTime.now();
    final today = dateKey(now);
    final yesterday = dateKey(now.subtract(const Duration(days: 1)));
    final weekStart = now.subtract(const Duration(days: 6));
    final monthStart = now.subtract(const Duration(days: 29));
    final list = _all.where((n) {
      if (q.isNotEmpty && !n.content.toLowerCase().contains(q)) return false;
      final key = dateKey(DateTime.fromMillisecondsSinceEpoch(n.createdAt));
      switch (_range) {
        case _Range.today:
          if (key != today) return false;
          break;
        case _Range.yesterday:
          if (key != yesterday) return false;
          break;
        case _Range.week7:
          if (n.createdAt < weekStart.millisecondsSinceEpoch) return false;
          break;
        case _Range.month30:
          if (n.createdAt < monthStart.millisecondsSinceEpoch) return false;
          break;
        case _Range.all:
          break;
      }
      if (_from.isNotEmpty && key.compareTo(_from) < 0) return false;
      if (_to.isNotEmpty && key.compareTo(_to) > 0) return false;
      return true;
    }).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<void> _openDetail(Note note) async {
    if (_selecting) {
      _toggleSelect(note);
      return;
    }
    await AppRoutes.push(context, NoteDetailPage(note: note));
    await _load(); // 详情页删除后刷新
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    showFrostedSnack(context, msg);
  }

  Future<void> _pickDate(bool isFrom) async {
    final now = DateTime.now();
    final initial = DateTime.tryParse(isFrom ? _from : _to) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: isFrom ? '选择起始日期' : '选择结束日期',
    );
    if (picked == null) return;
    final key = dateKey(picked);
    if (isFrom) {
      if (_to.isNotEmpty && key.compareTo(_to) > 0) {
        _showSnack('起始日期不能晚于结束日期');
        return;
      }
      setState(() => _from = key);
    } else {
      if (_from.isNotEmpty && key.compareTo(_from) < 0) {
        _showSnack('结束日期不能早于起始日期');
        return;
      }
      setState(() => _to = key);
    }
  }

  void _resetFilters() {
    _kwCtrl.clear();
    setState(() {
      _kw = '';
      _range = _Range.all;
      _from = '';
      _to = '';
    });
  }

  // ---------- 编辑模式(多选 / 批量删除) ----------
  bool _selecting = false;
  final Set<int> _selected = {};

  void _enterSelect(Note note) {
    setState(() {
      _selecting = true;
      _selected.add(note.id!);
    });
  }

  void _toggleSelect(Note note) {
    setState(() {
      if (!_selected.remove(note.id!)) {
        _selected.add(note.id!);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _selected.clear();
      _selected.addAll(_filtered.map((n) => n.id!));
    });
  }

  void _cancelSelect() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final ok = await showConfirmDialog(
      context,
      title: '删除选中的记录?',
      message: '将删除 ${_selected.length} 条记录,不可恢复。',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final count = _selected.length;
    // 记住被删记录用于撤销
    final removed =
        _all.where((n) => _selected.contains(n.id)).toList();
    try {
      await _noteService.deleteNotes(_selected.toList());
      _cancelSelect();
      await _load();
      if (!mounted) return;
      showUndoSnack(
        context,
        '已删除 $count 条',
        onUndo: () async {
          try {
            for (final n in removed) {
              await _noteService.restore(n);
            }
            await _load();
          } catch (e) {
            AppLog.instance.e('撤销批量删除失败:$e');
          }
        },
      );
    } catch (e) {
      AppLog.instance.e('批量删除失败:$e');
      await _load();
      if (!mounted) return;
      _showSnack('删除失败,请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      appBar: AppBar(
        leading: _selecting
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: _cancelSelect,
                tooltip: '取消编辑',
              )
            : null,
        title: Text(_selecting ? '已选 ${_selected.length} 条' : '灵感速记记录'),
        actions: _selecting
            ? [
                TextButton(
                  onPressed: _selectAll,
                  child: const Text('全选',
                      style: TextStyle(fontSize: 14)),
                ),
                IconButton(
                  icon: Icon(
                    Icons.delete_outline_rounded,
                    color: _selected.isEmpty
                        ? AppColors.textSub
                        : const Color(0xFFE53935),
                  ),
                  onPressed: _selected.isEmpty ? null : _deleteSelected,
                  tooltip: '删除选中',
                ),
              ]
            : [
                TextButton(
                  onPressed: () => setState(() => _selecting = true),
                  child: const Text('编辑',
                      style: TextStyle(fontSize: 14)),
                ),
                const SizedBox(width: 6),
              ],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 关键字搜索
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: TextField(
                controller: _kwCtrl,
                onChanged: (v) => setState(() => _kw = v),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '搜索关键字…',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _kw.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _kwCtrl.clear();
                            setState(() => _kw = '');
                          },
                        ),
                ),
              ),
            ),
            // 快捷日期 + 更多
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _chip('全部', _Range.all),
                          _chip('今天', _Range.today),
                          _chip('昨天', _Range.yesterday),
                          _chip('近7天', _Range.week7),
                          _chip('近30天', _Range.month30),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => setState(() => _customOpen = !_customOpen),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      foregroundColor: AppColors.primaryDark,
                      side: BorderSide(
                          color: AppColors.primary.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                    ),
                    child: Text(_customOpen ? '收起' : '更多',
                        style: const TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
            // 自定义起止日期(默认收起)
            if (_customOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Row(
                  children: [
                    _dateField('起始', _from, () => _pickDate(true)),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('至',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSub)),
                    ),
                    _dateField('结束', _to, () => _pickDate(false)),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            // 记录列表(时间轴:由新到旧,色点 + 竖线,时间在上、内容在下)
            Expanded(
              child: _loadError != null
                  ? ErrorView(
                      message: _loadError!,
                      onRetry: () {
                        setState(() {
                          _loadError = null;
                          _loading = true;
                        });
                        _load();
                      },
                    )
                  : _loading
                      ? const Center(child: CircularProgressIndicator())
                      : filtered.isEmpty
                          ? _buildEmpty()
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 4, 20, 24),
                              itemCount: filtered.length,
                              itemBuilder: (context, i) => _noteTile(filtered[i],
                                  isLast: i == filtered.length - 1),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, _Range r) {
    final selected = _range == r;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: () => setState(() {
          _range = r;
          _from = '';
          _to = '';
        }),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: selected ? AppColors.primary : AppColors.line),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: selected ? Colors.white : AppColors.textSub,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateField(String label, String value, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.calendar_today_rounded,
                  size: 13, color: AppColors.textSub),
              const SizedBox(width: 6),
              Text(
                value.isEmpty ? label : value,
                style: TextStyle(
                  fontSize: 13,
                  color: value.isEmpty ? AppColors.textSub : AppColors.textMain,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 时间轴色点池:浅色为主,按记录 id 稳定取色(同一记录颜色不变)。
  static const List<Color> _dotColors = [
    Color(0xFFB3E5FC), // 浅蓝
    Color(0xFFF8BBD0), // 浅粉
    Color(0xFFC8E6C9), // 浅绿
    Color(0xFFFFF9C4), // 浅黄
    Color(0xFFE1BEE7), // 浅紫
    Color(0xFFFFE0B2), // 浅橙
    Color(0xFFB2DFDB), // 浅青
    Color(0xFFD7CCC8), // 浅灰
  ];

  Color _dotColor(Note note) =>
      _dotColors[(note.id ?? note.createdAt) % _dotColors.length];

  /// 时间轴节点:左侧色点 + 竖向连接线;右侧时间(上)+ 内容卡片(下)。
  /// 选择(编辑)模式下,色点位置变成勾选框。
  Widget _noteTile(Note note, {required bool isLast}) {
    final selected = _selected.contains(note.id);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左轨:色点(或选择勾选框)+ 竖向连接线
          SizedBox(
            width: 26,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _selecting
                      ? InkWell(
                          onTap: () => _toggleSelect(note),
                          borderRadius: BorderRadius.circular(12),
                          child: Icon(
                            selected
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 20,
                            color: selected
                                ? AppColors.primary
                                : const Color(0xFFB9CBD9),
                          ),
                        )
                      : Container(
                          width: 11,
                          height: 11,
                          decoration: BoxDecoration(
                            color: _dotColor(note),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Color.lerp(
                                  _dotColor(note), Colors.black, 0.25)!,
                              width: 1,
                            ),
                          ),
                        ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: AppColors.line,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // 右侧:时间在上,文本框在下
          Expanded(
            child: InkWell(
              onTap: () => _openDetail(note),
              onLongPress: () {
                if (_selecting) {
                  _toggleSelect(note);
                } else {
                  _enterSelect(note);
                }
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 6 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      timelineLabel(note.createdAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSub.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primaryLight.withValues(alpha: 0.35)
                            : AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? AppColors.primary.withValues(alpha: 0.5)
                              : AppColors.line,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            note.content,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, height: 1.55),
                          ),
                          if (note.favorite || note.mood != null) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                if (note.favorite) ...[
                                  const Icon(Icons.star_rounded,
                                      size: 14, color: Color(0xFFF9A825)),
                                  const SizedBox(width: 5),
                                ],
                                if (note.mood != null)
                                  MoodBadge(mood: note.mood),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _hasFilter
                  ? Icons.search_off_rounded
                  : Icons.lightbulb_outline_rounded,
              size: 40,
              color: const Color(0xFFA9BCCD),
            ),
            const SizedBox(height: 12),
            Text(
              _hasFilter ? '没有找到匹配的记录' : '还没有灵感记录,快写一句吧~',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textSub),
            ),
            if (_hasFilter) ...[
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _resetFilters,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primaryDark,
                  side: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.5)),
                ),
                child: const Text('清除筛选', style: TextStyle(fontSize: 13)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
