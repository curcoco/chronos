import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/memory_item.dart';
import '../services/llm_service.dart';
import '../services/memory_service.dart';
import '../services/supabase_sync_service.dart';
import '../theme.dart';
import '../utils/dates.dart';
import '../widgets/frosted_snack.dart';

/// AI 长期记忆管理:查看 / 添加 / 删除 / 提炼 / 云端同步
class MemoryPage extends StatefulWidget {
  const MemoryPage({super.key});

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
  final MemoryService _service = MemoryService.instance;

  List<MemoryItem> _items = [];
  String _kind = 'all';
  bool _loading = true;
  bool _cloudAuto = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final auto = prefs.getBool('memory_cloud_auto') ?? false;
    final items = await _service.list();
    if (!mounted) return;
    setState(() {
      _cloudAuto = auto;
      _items = items;
      _loading = false;
    });
  }

  Future<void> _reload() async {
    final items = await _service.list();
    if (!mounted) return;
    setState(() => _items = items);
  }

  void _showSnack(String msg) => showFrostedSnack(context, msg);

  List<MemoryItem> get _display =>
      _kind == 'all' ? _items : _items.where((m) => m.kind == _kind).toList();

  Future<void> _add() async {
    final kindCtrl = ValueNotifier<String>('fact');
    final ctrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加记忆'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [
                for (final k in MemoryService.kinds)
                  ValueListenableBuilder<String>(
                    valueListenable: kindCtrl,
                    builder: (context, v, _) => ChoiceChip(
                      label: Text(MemoryService.kindLabels[k] ?? k,
                          style: const TextStyle(fontSize: 12)),
                      selected: v == k,
                      onSelected: (_) => kindCtrl.value = k,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(hintText: '记忆内容,如:喜欢晚上学习'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != true || !mounted) return;
    final content = ctrl.text.trim();
    if (content.isEmpty) {
      _showSnack('记忆内容不能为空');
      return;
    }
    await _service.add(kind: kindCtrl.value, content: content);
    await _reload();
    await _maybeSync();
    _showSnack('已保存记忆');
  }

  Future<void> _delete(MemoryItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这条记忆?'),
        content: Text(item.content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE53935)),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _service.delete(item.id!);
    await _reload();
    _showSnack('已删除');
  }

  /// 从今天(或最近)的对话提炼记忆
  Future<void> _extract() async {
    if (!await LlmService.instance.isConfigured()) {
      _showSnack('聊天服务未配置,请先到 系统设置 → API 配置 填写');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    List<({String role, String content})> history = [];
    if (prefs.getString('chat_date') == todayStr()) {
      final raw = prefs.getString('chat_messages');
      if (raw != null && raw.isNotEmpty) {
        try {
          final list = jsonDecode(raw) as List;
          history = [
            for (final m in list.cast<Map<String, dynamic>>())
              (role: m['role'] as String, content: m['content'] as String),
          ];
        } catch (_) {}
      }
    }
    if (history.isEmpty) {
      _showSnack('今天还没有对话,先去聊几句吧');
      return;
    }
    _showSnack('正在提炼记忆…');
    final prompt = '你是记忆提炼助手。根据下面的对话,提炼用户的长期记忆:\n'
        '1) profile:用户稳定身份/喜好/习惯(如有)\n'
        '2) fact:明确提到的重要事实(如有)\n'
        '3) summary:用一段话概括本次对话\n'
        '只输出 JSON:{"profile":["..."],"facts":["..."],"summary":"..."},不要多余文字。\n\n'
        '对话:\n${history.map((m) => '${m.role == 'user' ? '用户' : 'AI'}:${m.content}').join('\n')}';
    try {
      final reply = await LlmService.instance.chat(
        history: [(role: 'user', content: prompt)],
        persona: '你是记忆提炼助手。',
      );
      final cleaned = reply
          .replaceAll(RegExp(r'^```(json)?', multiLine: true), '')
          .replaceAll('```', '')
          .trim();
      final data = jsonDecode(cleaned) as Map<String, dynamic>;
      var added = 0;
      // add() 内部去重:重复内容返回 0,只统计真正新增的条数。
      for (final p in (data['profile'] as List? ?? []).cast<String>()) {
        if (p.trim().isNotEmpty) {
          final id =
              await _service.add(kind: 'profile', content: p.trim(), source: 'chat');
          if (id > 0) added++;
        }
      }
      for (final f in (data['facts'] as List? ?? []).cast<String>()) {
        if (f.trim().isNotEmpty) {
          final id =
              await _service.add(kind: 'fact', content: f.trim(), source: 'chat');
          if (id > 0) added++;
        }
      }
      final s = (data['summary'] as String?)?.trim();
      if (s != null && s.isNotEmpty) {
        final id = await _service.add(kind: 'summary', content: s, source: 'chat');
        if (id > 0) added++;
      }
      await _reload();
      await _maybeSync();
      if (!mounted) return;
      _showSnack(added > 0 ? '已提炼 $added 条记忆' : '本次没有提炼到新记忆');
    } catch (e) {
      _showSnack('提炼失败,请检查网络或配置');
    }
  }

  /// 云端同步:按用户开关决定是否自动上传
  Future<void> _maybeSync() async {
    if (!_cloudAuto) return;
    await _syncNow(silent: true);
  }

  Future<void> _syncNow({bool silent = false}) async {
    if (!await SupabaseSyncService.instance.isConfigured()) {
      if (!silent) _showSnack('云端未配置,请先到 系统设置 → API 配置 填写 Supabase');
      return;
    }
    final unsynced = await _service.unsynced();
    if (unsynced.isEmpty) {
      if (!silent) _showSnack('没有待同步的记忆');
      return;
    }
    var ok = 0;
    for (final m in unsynced) {
      try {
        await SupabaseSyncService.instance.push(m);
        await _service.markSynced(m.id!);
        ok++;
      } catch (_) {
        break; // 网络断开即停止
      }
    }
    await _reload();
    _showSnack(ok > 0 ? '已同步 $ok 条到云端' : '同步失败,请检查网络或配置');
  }

  Future<void> _toggleCloud(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('memory_cloud_auto', v);
    if (!mounted) return;
    setState(() => _cloudAuto = v);
    if (v) await _syncNow(silent: true);
    _showSnack(v ? '已开启自动上传云端' : '已关闭自动上传(记忆保留在本地)');
  }

  @override
  Widget build(BuildContext context) {
    final display = _display;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 长期记忆'),
        actions: [
          IconButton(
            onPressed: _extract,
            icon: const Icon(Icons.auto_awesome_rounded, size: 20),
            tooltip: '从对话提炼记忆',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                // 云同步说明与开关
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.cloud_outlined,
                              size: 18, color: AppColors.textSub),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text('自动上传云端(Supabase)',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600)),
                          ),
                          Switch(
                            value: _cloudAuto,
                            activeThumbColor: AppColors.primary,
                            onChanged: _toggleCloud,
                          ),
                        ],
                      ),
                      Text(
                        '默认存本地。开启后新记忆自动同步到云端,可跨设备。'
                        '未配置 Supabase 时同步会跳过。',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.textSub, height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.card,
                          foregroundColor: AppColors.primaryDark,
                          side: BorderSide(color: AppColors.primary),
                        ),
                        onPressed: _add,
                        icon: const Icon(Icons.add_rounded, size: 20),
                        label: const Text('添加记忆'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _syncNow,
                        icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                        label: const Text('同步到云端'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 类型筛选
                Wrap(
                  spacing: 8,
                  children: [
                    for (final k in ['all', ...MemoryService.kinds])
                      ChoiceChip(
                        label: Text(
                          k == 'all' ? '全部' : (MemoryService.kindLabels[k] ?? k),
                          style: const TextStyle(fontSize: 12),
                        ),
                        selected: _kind == k,
                        onSelected: (_) => setState(() => _kind = k),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (display.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 30),
                    child: Center(
                      child: Text('还没有记忆。可手动添加,或聊天后点右上角提炼',
                          style: TextStyle(color: AppColors.textSub)),
                    ),
                  )
                else
                  for (final m in display) _memoryTile(m),
              ],
            ),
    );
  }

  Widget _memoryTile(MemoryItem m) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _kindColor(m.kind).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              MemoryService.kindLabels[m.kind] ?? m.kind,
              style: TextStyle(
                  fontSize: 11,
                  color: _kindColor(m.kind),
                  fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.content,
                    style:
                        const TextStyle(fontSize: 14, height: 1.5)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (m.cloudSynced) ...[
                      const Icon(Icons.cloud_done_rounded,
                          size: 12, color: Color(0xFF2E9E5B)),
                      const SizedBox(width: 4),
                      const Text('已同步',
                          style: TextStyle(
                              fontSize: 10, color: Color(0xFF2E9E5B))),
                    ],
                    const SizedBox(width: 6),
                    Text(
                      fullDateTimeLabel(m.createdAt),
                      style: TextStyle(
                          fontSize: 10, color: AppColors.textSub),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _delete(m),
            icon: Icon(Icons.close_rounded,
                size: 18, color: AppColors.textSub),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Color _kindColor(String kind) => switch (kind) {
        'profile' => const Color(0xFF0288D1),
        'fact' => const Color(0xFF2E7D32),
        _ => const Color(0xFF7B1FA2),
      };
}
