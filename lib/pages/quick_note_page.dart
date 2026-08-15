import 'package:flutter/material.dart';

import '../models/note.dart';
import '../services/note_service.dart';
import '../theme.dart';
import '../utils/dates.dart';

/// 灵感速记页(底部 + 号一键直达)
class QuickNotePage extends StatefulWidget {
  const QuickNotePage({super.key});

  @override
  State<QuickNotePage> createState() => _QuickNotePageState();
}

class _QuickNotePageState extends State<QuickNotePage> {
  final NoteService _noteService = NoteService();
  final TextEditingController _ctrl = TextEditingController();

  List<Note> _notes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
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

  Future<void> _save() async {
    final text = _ctrl.text;
    if (text.trim().isEmpty) {
      _showSnack('写点什么再保存吧~');
      return;
    }
    await _noteService.addNote(text);
    _ctrl.clear();
    await _load();
    _showSnack('已保存到灵感专区 ✨');
  }

  Future<void> _delete(Note note) async {
    await _noteService.deleteNote(note.id!);
    await _load();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('灵感速记')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              maxLines: 3,
              maxLength: 200,
              decoration: const InputDecoration(
                hintText: '随时记录一句话灵感…\n它会自动同步到「灵感专区」',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '✨ 灵感专区',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMain),
                  ),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(110, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  onPressed: _save,
                  child: const Text('保存'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _notes.isEmpty
                    ? const Center(
                        child: Text('还没有灵感记录,快写一句吧~',
                            style: TextStyle(color: AppColors.textSub)),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                        itemCount: _notes.length,
                        itemBuilder: (context, i) {
                          final note = _notes[i];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 2),
                                    child: Icon(Icons.lightbulb_outline_rounded,
                                        size: 20, color: Color(0xFFFFB300)),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          note.content,
                                          style: const TextStyle(
                                              fontSize: 14, height: 1.4),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          dateTimeLabel(note.createdAt),
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textSub),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => _delete(note),
                                    icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        size: 20,
                                        color: AppColors.textSub),
                                    tooltip: '删除',
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
