import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/note.dart';
import '../services/note_service.dart';
import '../theme.dart';
import '../utils/dates.dart';
import '../widgets/frosted_snack.dart';
import '../widgets/mood_badge.dart';

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

  Future<void> _share() async {
    await Share.share(widget.note.content, subject: '灵感速记');
  }

  Future<void> _toggleFavorite() async {
    final next = !_fav;
    await _service.setFavorite(widget.note.id!, next);
    if (!mounted) return;
    setState(() => _fav = next);
    showFrostedSnack(context, next ? '已收藏' : '已取消收藏');
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条记录?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: const Color(0xFFE53935)),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await NoteService().deleteNote(widget.note.id!);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('记录·Chronos'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (v) {
              if (v == 'share') _share();
              if (v == 'fav') _toggleFavorite();
              if (v == 'delete') _delete();
            },
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
