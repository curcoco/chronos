import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import 'package:student_workbench/core/data/health_content.dart';
import 'package:student_workbench/core/theme.dart';
import 'package:student_workbench/core/utils/dates.dart';
import 'package:student_workbench/core/widgets/confirm_dialog.dart';
import 'package:student_workbench/core/widgets/frosted_snack.dart';
import 'package:student_workbench/features/coins/services/coin_service.dart';
import 'package:student_workbench/features/health/models/user_video.dart';
import 'package:student_workbench/features/health/services/health_service.dart';

/// 健康「视频跟练」Tab:内置计时器 + 打卡领金币 + 内置跟练列表 +
/// 用户自传视频(上传本地视频、播放、删除)。
/// 计时器状态在本组件内自持,切换 Tab 不重置(父级 TabBarView 缓存)。
class HealthVideoTab extends StatefulWidget {
  final HealthService service;
  final List<UserVideo> videos;
  final VoidCallback onChanged;

  const HealthVideoTab({
    super.key,
    required this.service,
    required this.videos,
    required this.onChanged,
  });

  @override
  State<HealthVideoTab> createState() => _HealthVideoTabState();
}

class _HealthVideoTabState extends State<HealthVideoTab> {
  Timer? _timer;
  int _sec = 0;
  bool _on = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() => setState(() => _sec++);

  void _toggle() {
    setState(() => _on = !_on);
    if (_on) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } else {
      _timer?.cancel();
    }
  }

  void _reset() {
    _timer?.cancel();
    setState(() {
      _on = false;
      _sec = 0;
    });
  }

  Future<void> _checkin() async {
    if (_sec <= 0) {
      showFrostedSnack(context, '先开始计时再打卡吧');
      return;
    }
    final coin = await CoinService.instance.rewardVideo(todayStr());
    if (!mounted) return;
    showFrostedSnack(
      context,
      coin > 0 ? '跟练完成,金币 +$coin(计时 ${_sec ~/ 60} 分钟)' : '今日已打过卡',
    );
    _reset();
  }

  /// 上传本地视频:选文件 → 复制到应用文档目录 → 存库。
  Future<void> _upload() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
    );
    final path = picked?.files.single.path;
    if (path == null || !mounted) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final ext = path.contains('.') ? path.split('.').last : 'mp4';
      final dest = File('${dir.path}/video_$stamp.$ext');
      await File(path).copy(dest.path);

      // 输入标题(可选备注)
      final titleCtrl = TextEditingController(
          text: File(path).uri.pathSegments.last);
      final noteCtrl = TextEditingController();
      if (!mounted) return;
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('添加跟练视频'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleCtrl,
                autofocus: true,
                maxLength: 30,
                decoration: const InputDecoration(labelText: '标题'),
              ),
              TextField(
                controller: noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: '备注(可选)'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              child: const Text('添加'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
      final title = titleCtrl.text.trim().isEmpty
          ? '我的视频'
          : titleCtrl.text.trim();
      await widget.service.addUserVideo(
        title: title,
        path: dest.path,
        note: noteCtrl.text.trim(),
      );
      widget.onChanged();
      if (!mounted) return;
      showFrostedSnack(context, '已添加跟练视频');
    } catch (_) {
      if (!mounted) return;
      showFrostedSnack(context, '添加失败,请重试');
    }
  }

  Future<void> _play(UserVideo v) async {
    if (!File(v.path).existsSync()) {
      showFrostedSnack(context, '视频文件不存在,可能已被移动');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _VideoPlayerPage(video: v)),
    );
  }

  Future<void> _delete(UserVideo v) async {
    final ok = await showConfirmDialog(
      context,
      title: '删除这个视频?',
      message: '「${v.title}」将从列表中移除(本地文件一并删除)。',
      confirmText: '删除',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await widget.service.deleteUserVideo(v.id!);
    // 顺带删除本地文件(尽力而为)。
    try {
      final f = File(v.path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    widget.onChanged();
    if (!mounted) return;
    showFrostedSnack(context, '已删除');
  }

  @override
  Widget build(BuildContext context) {
    final mm = (_sec ~/ 60).toString().padLeft(2, '0');
    final ss = (_sec % 60).toString().padLeft(2, '0');
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        // 计时器卡片
        Container(
          padding: const EdgeInsets.symmetric(vertical: 22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primaryLight, AppColors.primary],
            ),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Text(
                '$mm:$ss',
                style: const TextStyle(
                    fontSize: 46,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.card,
                      foregroundColor: AppColors.primaryDark,
                    ),
                    onPressed: _toggle,
                    child: Text(_on ? '暂停' : '开始'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white),
                    ),
                    onPressed: _reset,
                    child: const Text('重置'),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white),
                    ),
                    onPressed: _checkin,
                    child: const Text('打卡 +1'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text('我的视频',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('上传你自己的跟练视频,点击播放;添加按钮在下方。',
            style: TextStyle(fontSize: 11, color: AppColors.textSub)),
        const SizedBox(height: 8),
        // 我的视频列表
        if (widget.videos.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('还没有自传视频,点下方「添加视频」上传一个吧',
                style: TextStyle(fontSize: 12, color: AppColors.textSub)),
          )
        else
          for (final v in widget.videos)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                children: [
                  Icon(Icons.play_circle_outline_rounded,
                      size: 20, color: AppColors.primaryDark),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(v.title,
                            style: const TextStyle(fontSize: 14)),
                        if (v.note.isNotEmpty)
                          Text(v.note,
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.textSub)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _play(v),
                    icon: const Icon(Icons.play_arrow_rounded, size: 22),
                    tooltip: '播放',
                  ),
                  IconButton(
                    onPressed: () => _delete(v),
                    icon: Icon(Icons.close_rounded,
                        size: 18, color: AppColors.textSub),
                    tooltip: '删除',
                  ),
                ],
              ),
            ),
        const SizedBox(height: 12),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.card,
            foregroundColor: AppColors.primaryDark,
            side: BorderSide(color: AppColors.primary),
          ),
          onPressed: _upload,
          icon: const Icon(Icons.video_library_rounded, size: 20),
          label: const Text('添加视频'),
        ),
        const SizedBox(height: 16),
        const Text('内置跟练',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        for (final v in HealthContent.videos)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.line)),
            ),
            child: Row(
              children: [
                Icon(Icons.play_circle_outline_rounded,
                    size: 20, color: AppColors.primaryDark),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(v.title, style: const TextStyle(fontSize: 14)),
                ),
                Text('${v.min} 分钟',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.textSub)),
              ],
            ),
          ),
      ],
    );
  }
}

/// 视频播放页(全屏,黑底)。
class _VideoPlayerPage extends StatefulWidget {
  final UserVideo video;

  const _VideoPlayerPage({required this.video});

  @override
  State<_VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<_VideoPlayerPage> {
  late VideoPlayerController _controller;
  bool _initFailed = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.video.path));
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _controller.play();
    }).catchError((_) {
      if (!mounted) return;
      setState(() => _initFailed = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.video.title,
            style: const TextStyle(fontSize: 15)),
      ),
      body: Center(
        child: _initFailed
            ? const Text('无法播放此视频,格式可能不支持',
                style: TextStyle(color: Colors.white70))
            : _controller.value.isInitialized
                ? GestureDetector(
                    onTap: () => setState(() {
                      _controller.value.isPlaying
                          ? _controller.pause()
                          : _controller.play();
                    }),
                    child: AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    ),
                  )
                : const CircularProgressIndicator(),
      ),
    );
  }
}
