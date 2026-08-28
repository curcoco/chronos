import 'package:flutter/material.dart';

import 'package:chronos/features/notes/models/note.dart';
import 'package:chronos/routes.dart';
import 'package:chronos/features/notes/services/note_service.dart';
import 'package:chronos/core/services/app_log.dart';
import 'package:chronos/core/theme.dart';
import 'package:chronos/core/utils/dates.dart';
import 'package:chronos/core/widgets/app_text_field.dart';
import 'package:chronos/core/widgets/confirm_dialog.dart';
import 'package:chronos/core/widgets/frosted_snack.dart';
import 'package:chronos/core/widgets/mood_badge.dart';
import 'package:chronos/core/widgets/status_views.dart';
import 'package:chronos/features/diary/pages/diary_page.dart';
import 'package:chronos/features/notes/pages/note_detail_page.dart';
import 'package:chronos/features/notes/pages/note_history_page.dart';

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
  String? _loadError; // 灵感专区加载失败(渲染 ErrorView + 重试)
  bool _favOnly = false;
  bool _saving = false; // 防止「完成」键与发送按钮/换行回调重复触发保存

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
    try {
      final notes = await _noteService.notes();
      if (!mounted) return;
      setState(() {
        _notes = notes;
        _loading = false;
        _loadError = null;
      });
    } catch (e) {
      AppLog.instance.e('灵感专区加载失败:$e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '灵感专区加载失败,请重试';
      });
    }
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
      await _noteService.addNote(text);
      _ctrl.clear();
      // 保持聚焦,方便连写多条
      _focusNode.requestFocus();
      await _load();
      _showSnack('已保存到灵感专区');
    } catch (e) {
      // 之前保存失败是静默的(如 DB 缺列),这里显式反馈 + 落日志。
      AppLog.instance.e('灵感保存失败:$e');
      _showSnack('保存失败,请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openDetail(Note note) async {
    await AppRoutes.push(context, NoteDetailPage(note: note));
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
    try {
      await _noteService.deleteNote(note.id!);
      await _load();
      if (!mounted) return;
      showUndoSnack(
        context,
        '已删除',
        onUndo: () async {
          try {
            await _noteService.restore(removed);
            await _load();
          } catch (e) {
            AppLog.instance.e('撤销删除灵感失败:$e');
          }
        },
      );
    } catch (e) {
      // 行已从 UI 消失但 DB 未删:重载恢复真实数据,并给出反馈。
      AppLog.instance.e('删除灵感失败:$e');
      await _load();
      if (!mounted) return;
      _showSnack('删除失败,请重试');
    }
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
              AppRoutes.push(context, const DiaryPage());
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
                      AppRoutes.push(context, const NoteHistoryPage());
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
                      // 不自动弹键盘:底部导航切过来是浏览场景,
                      // 想写时点输入框再弹,避免「一看功能就被键盘打断」。
                      autofocus: false,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 200,
                      hintText: '记录灵感…',
                      // 灵感速记为换行框:回车正常换行,保存只走右侧发送按钮。
                      submitOnEnter: false,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 发送按钮:圆形底色与输入区一致(不抢眼),纸飞机用主题蓝。
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.card,
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
                                    Colors.grey),
                              ),
                            )
                          : Icon(Icons.send_rounded,
                              size: 22, color: AppColors.primaryDark),
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
