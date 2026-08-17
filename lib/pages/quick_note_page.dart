import 'package:flutter/material.dart';

import '../models/note.dart';
import '../services/note_service.dart';
import '../theme.dart';
import '../utils/dates.dart';
import '../widgets/app_text_field.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/frosted_snack.dart';
import '../widgets/mood_badge.dart';
import 'diary_page.dart';
import 'note_detail_page.dart';
import 'note_history_page.dart';

/// 灵感速记页(底部 + 号 / 启动页快速记一笔 / 侧边栏直达)。
/// 聊天式布局:灵感专区在记录框上方;保存按钮在输入框右侧。
/// 收藏内容置顶;左滑删除(带确认);点行进详情。
class QuickNotePage extends StatefulWidget {
  const QuickNotePage({super.key});

  @override
  State<QuickNotePage> createState() => _QuickNotePageState();
}

class _QuickNotePageState extends State<QuickNotePage> {
  final NoteService _noteService = NoteService();
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<Note> _notes = [];
  bool _loading = true;
  bool _favOnly = false;
  bool _saving = false; // 防止「完成」键与发送按钮/换行回调重复触发保存
  String? _mood; // 本次记录的心情(null=无)

  static const List<(String, String)> _moodOptions = [
    ('happy', '开心'),
    ('calm', '平静'),
    ('sad', '难过'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final notes = await _noteService.notes();
    if (!mounted) return;
    setState(() {
      _notes = notes;
      _loading = false;
    });
  }

  /// 收藏置顶,其余按时间倒序
  List<Note> get _display {
    final list = _favOnly ? _notes.where((n) => n.favorite).toList() : _notes;
    list.sort((a, b) {
      if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return list;
  }

  Future<void> _save() async {
    if (_saving) return; // 去抖:避免「完成」键 + 换行回调重复保存
    final text = _ctrl.text;
    if (text.trim().isEmpty) {
      _showSnack('写点什么再保存吧~');
      return;
    }
    setState(() => _saving = true);
    try {
      await _noteService.addNote(text, mood: _mood);
      _ctrl.clear();
      setState(() => _mood = null); // 心情仅记一次,写完复位
      // 保持聚焦,方便连写多条
      _focusNode.requestFocus();
      await _load();
      _showSnack('已保存到灵感专区');
    } catch (e) {
      // 之前保存失败是静默的(如 DB 缺列),这里显式反馈,避免"点了没反应"。
      _showSnack('保存失败:$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openDetail(Note note) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NoteDetailPage(note: note)),
    );
    await _load(); // 详情页删除/收藏后刷新
  }

  /// 左滑删除前确认
  Future<bool> _confirmDelete(Note note) {
    return showConfirmDialog(
      context,
      title: '删除这条记录?',
      message: '「${note.content}」',
      confirmText: '删除',
      destructive: true,
    );
  }

  Future<void> _delete(Note note) async {
    final removed = note; // 记住被删记录用于撤销
    await _noteService.deleteNote(note.id!);
    await _load();
    if (!mounted) return;
    showUndoSnack(
      context,
      '已删除',
      onUndo: () async {
        await _noteService.restore(removed);
        await _load();
      },
    );
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    showFrostedSnack(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    final display = _display;
    return Scaffold(
      appBar: AppBar(
        title: const Text('灵感速记'),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DiaryPage()),
              );
            },
            icon: const Icon(Icons.menu_book_rounded, size: 20),
            tooltip: '日记',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 灵感专区标题行
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '灵感专区',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSub,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _favOnly = !_favOnly),
                    icon: Icon(
                      _favOnly ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 20,
                      color: _favOnly
                          ? const Color(0xFFF9A825)
                          : AppColors.textSub,
                    ),
                    tooltip: _favOnly ? '只看收藏(点击恢复全部)' : '只看收藏',
                    visualDensity: VisualDensity.compact,
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const NoteHistoryPage()),
                      );
                    },
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: const Text('查看全部 ›',
                        style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 灵感专区列表(在记录框上方)
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : display.isEmpty
                      ? Center(
                          child: _favOnly
                              ? Text(
                                  '还没有收藏的灵感',
                                  style: TextStyle(color: AppColors.textSub),
                                )
                              : Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 40),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 72,
                                        height: 72,
                                        decoration: BoxDecoration(
                                          color: AppColors.primaryLight
                                              .withValues(alpha: 0.4),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                            Icons.lightbulb_outline_rounded,
                                            size: 36,
                                            color: AppColors.primaryDark),
                                      ),
                                      const SizedBox(height: 16),
                                      Text('还没有灵感记录',
                                          style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.textMain)),
                                      const SizedBox(height: 6),
                                      Text(
                                        '在下方输入框写一句,\n比如「明天要早起背单词」',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontSize: 13,
                                            height: 1.6,
                                            color: AppColors.textSub),
                                      ),
                                    ],
                                  ),
                                ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                          itemCount: display.length,
                          itemBuilder: (context, i) =>
                              _noteTile(display[i]),
                        ),
            ),
            // 心情标记(可选,随笔已合并进灵感速记)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Row(
                children: [
                  Text('心情',
                      style:
                          TextStyle(fontSize: 12, color: AppColors.textSub)),
                  const SizedBox(width: 8),
                  _moodChip(null, '无'),
                  for (final m in _moodOptions) _moodChip(m.$1, m.$2),
                ],
              ),
            ),
            // 聊天式输入区:输入框 + 右侧保存按钮
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              decoration: BoxDecoration(
                color: AppColors.card,
                border: Border(
                  top: BorderSide(color: AppColors.line),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: _ctrl,
                      focusNode: _focusNode,
                      autofocus: true,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 200,
                      hintText: '记录灵感,可换行;写完点右侧保存',
                      // 灵感速记为换行框:回车正常换行,保存只走右侧发送按钮。
                      submitOnEnter: false,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 发送按钮:用 IconButton(自带稳定的点击热区)包一层圆形底色,
                  // 避免此前 FilledButton 受全局主题 minimumSize 影响导致点击无响应。
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: _saving ? null : _save,
                      padding: EdgeInsets.zero,
                      tooltip: '保存灵感',
                      icon: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white),
                              ),
                            )
                          : const Icon(Icons.send_rounded,
                              size: 22, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _moodChip(String? value, String label) {
    final selected = _mood == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: () => setState(() => _mood = value),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected ? AppColors.primary : AppColors.line),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: selected ? Colors.white : AppColors.textSub,
            ),
          ),
        ),
      ),
    );
  }

  Widget _noteTile(Note note) {
    return Dismissible(
      key: ValueKey(note.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(note),
      onDismissed: (_) => _delete(note),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 1),
        decoration: BoxDecoration(
          color: const Color(0xFFFDE8E8),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.delete_outline_rounded,
            color: Color(0xFFE53935), size: 20),
      ),
      child: InkWell(
        onTap: () => _openDetail(note),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          note.content,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15, height: 1.5),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (note.favorite) ...[
                              const Icon(Icons.star_rounded,
                                  size: 13, color: Color(0xFFF9A825)),
                              const SizedBox(width: 4),
                            ],
                            if (note.mood != null) ...[
                              MoodBadge(mood: note.mood),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              dateTimeLabel(note.createdAt),
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSub
                                    .withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
        ),
      ),
    );
  }
}
