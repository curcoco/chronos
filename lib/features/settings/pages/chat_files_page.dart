import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:chronos/core/services/app_log.dart';
import 'package:chronos/core/theme.dart';
import 'package:chronos/core/widgets/confirm_dialog.dart';
import 'package:chronos/core/widgets/frosted_snack.dart';
import 'package:chronos/core/widgets/status_views.dart';

/// 聊天图片存储管理(数据设置):列出闲话铺发图时保存到 chat_imgs/ 的图片,
/// 支持单张删除与一键清空,避免占用过多存储。
class ChatFilesPage extends StatefulWidget {
  const ChatFilesPage({super.key});

  @override
  State<ChatFilesPage> createState() => _ChatFilesPageState();
}

class _ChatFilesPageState extends State<ChatFilesPage> {
  List<File> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Directory> _imgDir() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'chat_imgs'));
  }

  Future<void> _load() async {
    try {
      final dir = await _imgDir();
      List<File> files = [];
      if (await dir.exists()) {
        files = dir
            .listSync()
            .whereType<File>()
            .toList()
          ..sort((a, b) => b.path.compareTo(a.path));
      }
      if (!mounted) return;
      setState(() {
        _files = files;
        _loading = false;
      });
    } catch (e) {
      AppLog.instance.e('聊天图片列表加载失败:$e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  int get _totalBytes => _files.fold(0, (sum, f) {
        try {
          return sum + f.lengthSync();
        } catch (_) {
          return sum;
        }
      });

  String _sizeText(int bytes) {
    if (bytes >= 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  Future<void> _deleteOne(File f) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除这张图片?',
      message: p.basename(f.path),
      confirmText: '删除',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    try {
      await f.delete();
      if (!mounted) return;
      setState(() => _files.remove(f));
      showFrostedSnack(context, '已删除');
    } catch (e) {
      AppLog.instance.e('删除聊天图片失败:$e');
      if (!mounted) return;
      showFrostedSnack(context, '删除失败,请重试');
    }
  }

  Future<void> _clearAll() async {
    if (_files.isEmpty) return;
    final ok = await showConfirmDialog(
      context,
      title: '清空全部聊天图片?',
      message: '共 ${_files.length} 张(${_sizeText(_totalBytes)}),删除后不可恢复。\n图片删除不影响聊天记录文本。',
      confirmText: '清空',
      destructive: true,
    );
    if (ok != true || !mounted) return;
    try {
      for (final f in _files) {
        await f.delete(recursive: false);
      }
      if (!mounted) return;
      setState(() => _files = []);
      showFrostedSnack(context, '已清空');
    } catch (e) {
      AppLog.instance.e('清空聊天图片失败:$e');
      if (!mounted) return;
      showFrostedSnack(context, '清空失败,请重试');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('聊天图片'),
        actions: [
          IconButton(
            onPressed: _files.isEmpty ? null : _clearAll,
            icon: const Icon(Icons.delete_sweep_outlined, size: 22),
            tooltip: '清空全部',
          ),
        ],
      ),
      body: _loading
          ? const LoadingView(hint: '加载中…')
          : _files.isEmpty
              ? const EmptyView(
                  icon: Icons.photo_library_outlined,
                  message: '还没有聊天图片\n闲话铺发过图后会保存在这里',
                )
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                      child: Row(
                        children: [
                          Text('${_files.length} 张',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 6),
                          Text('共 ${_sizeText(_totalBytes)}',
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.textSub)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                        itemCount: _files.length,
                        itemBuilder: (context, i) {
                          final f = _files[i];
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(f,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Container(
                                        color: AppColors.line,
                                        child: const Icon(
                                            Icons.broken_image_outlined,
                                            color: Colors.grey))),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: GestureDetector(
                                  onTap: () => _deleteOne(f),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.close_rounded,
                                        size: 14, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
