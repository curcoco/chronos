import 'package:flutter/material.dart';

import 'package:chronos/core/services/app_log.dart';
import 'package:chronos/core/theme.dart';
import 'package:chronos/core/widgets/confirm_dialog.dart';
import 'package:chronos/core/widgets/frosted_snack.dart';
import 'package:chronos/core/widgets/status_views.dart';
import 'package:chronos/features/chat/models/chat_session.dart';
import 'package:chronos/features/chat/services/chat_service.dart';

/// 会话列表页:新建 / 切换 / 改名 / 删除聊天会话。
class SessionListPage extends StatefulWidget {
  const SessionListPage({super.key});

  @override
  State<SessionListPage> createState() => _SessionListPageState();
}

class _SessionListPageState extends State<SessionListPage> {
  final ChatService _service = ChatService.instance;
  List<ChatSession> _sessions = [];
  List<SessionFolder> _folders = [];
  String _filter = 'all'; // 'all' | 'ungrouped' | 文件夹 id 字符串
  bool _loading = true;
  String? _loadError; // 会话列表加载失败(渲染 ErrorView + 重试)

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _service.sessions();
      final folders = await _service.folders();
      if (!mounted) return;
      setState(() {
        _sessions = list;
        _folders = folders;
        _loading = false;
        _loadError = null;
      });
    } catch (e) {
      AppLog.instance.e('会话列表加载失败:$e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '会话列表加载失败,请重试';
      });
    }
  }

  Future<void> _loadFolders() async {
    try {
      final folders = await _service.folders();
      if (!mounted) return;
      setState(() => _folders = folders);
    } catch (e) {
      AppLog.instance.e('文件夹列表加载失败:$e');
    }
  }

  /// 当前筛选下的会话。
  List<ChatSession> get _display {
    if (_filter == 'all') return _sessions;
    if (_filter == 'ungrouped') {
      return _sessions.where((s) => s.folderId == null).toList();
    }
    final fid = int.tryParse(_filter);
    if (fid == null) return _sessions;
    return _sessions.where((s) => s.folderId == fid).toList();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    showFrostedSnack(context, msg);
  }

  /// 文件夹筛选 chip。
  Widget _folderChip(String label, String key) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: _filter == key,
        onSelected: (_) => setState(() => _filter = key),
      ),
    );
  }

  /// 新建会话并直接进入聊天页
  Future<void> _create() async {
    try {
      final id = await _service.createSession();
      if (!mounted) return;
      Navigator.of(context).pop(id);
    } catch (e) {
      AppLog.instance.e('新建会话失败:$e');
      _showSnack('新建失败,请重试');
    }
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
    try {
      await _service.renameSession(s.id!, result);
      await _load();
      _showSnack('已重命名');
    } catch (e) {
      AppLog.instance.e('重命名会话失败:$e');
      _showSnack('重命名失败,请重试');
    }
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
    try {
      await _service.deleteSession(s.id!);
      await _load();
      _showSnack('已删除会话');
    } catch (e) {
      AppLog.instance.e('删除会话失败:$e');
      _showSnack('删除失败,请重试');
    }
  }

  /// 清空某会话的消息(会话本身保留);可撤销。
  Future<void> _clear(ChatSession s) async {
    final ok = await showConfirmDialog(
      context,
      title: '清空这个会话的记录?',
      message: '「${s.title}」的全部聊天消息将被清空,会话本身保留。\n'
          '清空后可通过提示条撤销。',
      confirmText: '清空',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      final removed = await _service.clearMessages(s.id!);
      if (!mounted) return;
      showUndoSnack(
        context,
        '已清空 ${removed.length} 条记录',
        onUndo: () async {
          try {
            await _service.restoreMessages(removed);
            if (!mounted) return;
            _showSnack('已恢复');
          } catch (e) {
            AppLog.instance.e('恢复清空消息失败:$e');
          }
        },
      );
    } catch (e) {
      AppLog.instance.e('清空会话记录失败:$e');
      _showSnack('清空失败,请重试');
    }
  }

  /// 新建会话文件夹。
  Future<void> _createFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(hintText: '文件夹名称,如:工作'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      await _service.createFolder(name);
      await _loadFolders();
      _showSnack('已创建文件夹');
    } catch (e) {
      AppLog.instance.e('新建文件夹失败:$e');
      _showSnack('新建失败,请重试');
    }
  }

  /// 把会话移动到某个文件夹(未归档 = 移出)。
  Future<void> _moveToFolder(ChatSession s) async {
    final choice = await showDialog<int?>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('移动到文件夹'),
        children: [
          for (final f in _folders)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(f.id),
              child: Row(
                children: [
                  Icon(Icons.folder_rounded,
                      size: 18, color: AppColors.textSub),
                  const SizedBox(width: 8),
                  Text(f.name),
                ],
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(-1),
            child: Row(
              children: [
                Icon(Icons.folder_off_outlined,
                    size: 18, color: AppColors.textSub),
                SizedBox(width: 8),
                Text('未归档'),
              ],
            ),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final target = choice == -1 ? null : choice;
    try {
      await _service.moveSession(s.id!, target);
      await _load();
      await _loadFolders();
      if (!mounted) return;
      showFrostedSnack(context, target == null ? '已移出归档' : '已移动到文件夹');
    } catch (e) {
      AppLog.instance.e('移动会话失败:$e');
      _showSnack('移动失败,请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('会话记录')),
      body: _loadError != null
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
              ? const LoadingView()
              : _sessions.isEmpty
              ? const EmptyView(
                  icon: Icons.forum_outlined,
                  message: '还没有会话,点右下角新建一个吧',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 文件夹筛选 chips + 新建文件夹
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _folderChip('全部', 'all'),
                            _folderChip('未归档', 'ungrouped'),
                            for (final f in _folders)
                              _folderChip(f.name, '${f.id}'),
                            // 新建文件夹按钮(伪 chip)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: ActionChip(
                                avatar: Icon(Icons.create_new_folder_rounded,
                                    size: 16, color: AppColors.primaryDark),
                                label: const Text('新建', style: TextStyle(fontSize: 12)),
                                onPressed: _createFolder,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: _display.isEmpty
                          ? const EmptyView(
                              icon: Icons.folder_off_outlined,
                              message: '该文件夹下没有会话',
                            )
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 0, 12, 24),
                              itemCount: _display.length,
                              itemBuilder: (context, i) {
                                final s = _display[i];
                                return Card(
                                  margin:
                                      const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    leading: Icon(
                                        Icons.chat_bubble_outline_rounded,
                                        color: AppColors.primaryDark),
                                    title: Text(
                                      s.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          onPressed: () => _moveToFolder(s),
                                          icon: const Icon(
                                              Icons.drive_file_move_outline,
                                              size: 18),
                                          tooltip: '移动到文件夹',
                                        ),
                                        IconButton(
                                          onPressed: () => _clear(s),
                                          icon: const Icon(
                                              Icons.delete_sweep_outlined,
                                              size: 18),
                                          tooltip: '清空记录',
                                        ),
                                        IconButton(
                                          onPressed: () => _rename(s),
                                          icon: const Icon(
                                              Icons.edit_outlined,
                                              size: 18),
                                          tooltip: '重命名',
                                        ),
                                        IconButton(
                                          onPressed: () => _delete(s),
                                          icon: const Icon(
                                              Icons.delete_outline_rounded,
                                              size: 18),
                                          tooltip: '删除',
                                        ),
                                      ],
                                    ),
                                    onTap: () =>
                                        Navigator.of(context).pop(s.id),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
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
