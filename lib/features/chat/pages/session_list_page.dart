import 'package:flutter/material.dart';

import 'package:student_workbench/core/theme.dart';
import 'package:student_workbench/core/widgets/confirm_dialog.dart';
import 'package:student_workbench/core/widgets/frosted_snack.dart';
import 'package:student_workbench/features/chat/models/chat_session.dart';
import 'package:student_workbench/features/chat/services/chat_service.dart';

/// 会话列表页:新建 / 切换 / 改名 / 删除聊天会话。
class SessionListPage extends StatefulWidget {
  const SessionListPage({super.key});

  @override
  State<SessionListPage> createState() => _SessionListPageState();
}

class _SessionListPageState extends State<SessionListPage> {
  final ChatService _service = ChatService.instance;
  List<ChatSession> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _service.sessions();
    if (!mounted) return;
    setState(() {
      _sessions = list;
      _loading = false;
    });
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    showFrostedSnack(context, msg);
  }

  /// 新建会话并直接进入聊天页
  Future<void> _create() async {
    final id = await _service.createSession();
    if (!mounted) return;
    Navigator.of(context).pop(id);
  }

  Future<void> _rename(ChatSession s) async {
    final controller = TextEditingController(text: s.title);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重命名会话'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 20,
          decoration: const InputDecoration(hintText: '会话标题'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    await _service.renameSession(s.id!, result);
    await _load();
    _showSnack('已重命名');
  }

  Future<void> _delete(ChatSession s) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除这个会话?',
      message: '「${s.title}」及其全部聊天记录将被删除,不可恢复。',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _service.deleteSession(s.id!);
    await _load();
    _showSnack('已删除会话');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('会话记录')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.forum_outlined,
                          size: 46, color: AppColors.primaryLight),
                      const SizedBox(height: 12),
                      Text('还没有会话,点右下角新建一个吧',
                          style:
                              TextStyle(color: AppColors.textSub)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: _sessions.length,
                  itemBuilder: (context, i) {
                    final s = _sessions[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(Icons.chat_bubble_outline_rounded,
                            color: AppColors.primaryDark),
                        title: Text(
                          s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () => _rename(s),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              tooltip: '重命名',
                            ),
                            IconButton(
                              onPressed: () => _delete(s),
                              icon: const Icon(Icons.delete_outline_rounded,
                                  size: 18),
                              tooltip: '删除',
                            ),
                          ],
                        ),
                        onTap: () => Navigator.of(context).pop(s.id),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        onPressed: _create,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}
