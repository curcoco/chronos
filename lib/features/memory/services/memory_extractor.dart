import 'dart:convert';

import 'package:student_workbench/core/services/key_store.dart';
import 'package:student_workbench/features/chat/services/llm_service.dart';
import 'package:student_workbench/features/memory/services/memory_service.dart';

/// 记忆提炼器(RikkaHub 式自动记忆):
/// 用「快速模型」(API 配置里单独配置的低成本模型,留空则复用对话模型)
/// 从对话中提取用户画像/事实/摘要,存入本地记忆表。可手动触发或对话后自动调用。
class MemoryExtractor {
  MemoryExtractor._();
  static final MemoryExtractor instance = MemoryExtractor._();

  /// 从最近对话提炼记忆,返回新增条数(重复内容不计)。
  /// [history] 为用户与 AI 的对话(按时间正序)。
  Future<int> extractFrom(
      List<({String role, String content})> history) async {
    if (history.isEmpty) return 0;
    if (!await LlmService.instance.isConfigured()) return 0;
    final fastModel = await KeyStore.instance.get(KeyStore.llmFastModel);
    final prompt = '你是记忆提炼助手。根据下面的对话,提炼用户的长期记忆:\n'
        '1) profile:用户稳定身份/喜好/习惯(如有)\n'
        '2) fact:明确提到的重要事实(如有)\n'
        '3) summary:用一段话概括本次对话\n'
        '只输出 JSON:{"profile":["..."],"facts":["..."],"summary":"..."},不要多余文字。\n\n'
        '对话:\n'
        '${history.map((m) => '${m.role == 'user' ? '用户' : 'AI'}:${m.content}').join('\n')}';
    final reply = await LlmService.instance.chat(
      history: [(role: 'user', content: prompt)],
      persona: '你是记忆提炼助手。',
      // 快速模型:留空则复用对话模型
      model: fastModel.isEmpty ? null : fastModel,
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
            await MemoryService.instance.add(kind: 'profile', content: p.trim(), source: 'chat');
        if (id > 0) added++;
      }
    }
    for (final f in (data['facts'] as List? ?? []).cast<String>()) {
      if (f.trim().isNotEmpty) {
        final id =
            await MemoryService.instance.add(kind: 'fact', content: f.trim(), source: 'chat');
        if (id > 0) added++;
      }
    }
    final s = (data['summary'] as String?)?.trim();
    if (s != null && s.isNotEmpty) {
      final id =
          await MemoryService.instance.add(kind: 'summary', content: s, source: 'chat');
      if (id > 0) added++;
    }
    return added;
  }
}
