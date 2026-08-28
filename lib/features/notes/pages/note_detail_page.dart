import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'package:chronos/features/notes/models/note.dart';
import 'package:chronos/features/notes/services/note_service.dart';
import 'package:chronos/core/services/app_log.dart';
import 'package:chronos/core/theme.dart';
import 'package:chronos/core/utils/dates.dart';
import 'package:chronos/core/widgets/confirm_dialog.dart';
import 'package:chronos/core/widgets/frosted_snack.dart';
import 'package:chronos/core/widgets/mood_badge.dart';

/// 灵感速记记录详情页:正文 + 完整时间;右上角三点菜单(分享 / 收藏 / 删除)
class NoteDetailPage extends StatefulWidget {
  final Note note;

  const NoteDetailPage({super.key, required this.note});

  @override
  State<NoteDetailPage> createState() => _NoteDetailPageState();
}

class _NoteDetailPageState extends State<NoteDetailPage> {
  final NoteService _service = NoteService();
  late bool _fav = widget.note.favorite;

  /// 菜单分发:各操作内部自带 try/catch(失败落日志 + 反馈),不再裸抛。
  void _onMenu(String v) {
    switch (v) {
      case 'share':
        _share();
      case 'fav':
        _toggleFavorite();
      case 'delete':
        _delete();
    }
  }

  Future<void> _share() async {
    try {
      await Share.share(widget.note.content, subject: '灵感速记');
    } catch (e) {
      AppLog.instance.e('分享失败:$e');
    }
  }

  Future<void> _toggleFavorite() async {
    try {
      final next = !_fav;
      await _service.setFavorite(widget.note.id!, next);
      if (!mounted) return;
      setState(() => _fav = next);
      showFrostedSnack(context, next ? '已收藏' : '已取消收藏');
    } catch (e) {
      AppLog.instance.e('收藏切换失败:$e');
      if (!mounted) return;
      showFrostedSnack(context, '操作失败,请重试');
    }
  }

  Future<void> _delete() async {
    final ok = await showConfirmDialog(
      context,
      title: '删除这条记录?',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await NoteService().deleteNote(widget.note.id!);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      AppLog.instance.e('删除记录失败:$e');
      if (!mounted) return;
      showFrostedSnack(context, '删除失败,请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('记录·Chronos'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: _onMenu,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share_outlined, size: 18),
                    SizedBox(width: 10),
                    Text('分享'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'fav',
                child: Row(
                  children: [
                    Icon(
                      _fav ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 18,
                      color:
                          _fav ? const Color(0xFFF9A825) : AppColors.textSub,
                    ),
                    const SizedBox(width: 10),
                    Text(_fav ? '取消收藏' : '收藏'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline_rounded,
                        size: 18, color: Color(0xFFE53935)),
                    SizedBox(width: 10),
                    Text('删除', style: TextStyle(color: Color(0xFFE53935))),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
          children: [
            Text(
              widget.note.content,
              style: const TextStyle(fontSize: 17, height: 1.7),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (_fav) ...[
                  const Icon(Icons.star_rounded,
                      size: 14, color: Color(0xFFF9A825)),
                  const SizedBox(width: 4),
                ],
                if (widget.note.mood != null) ...[
                  MoodBadge(mood: widget.note.mood),
                  const SizedBox(width: 6),
                ],
                Text(
                  fullDateTimeLabel(widget.note.createdAt),
                  style: TextStyle(fontSize: 12, color: AppColors.textSub),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
