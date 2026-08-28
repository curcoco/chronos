import 'dart:convert';

import 'package:chronos/core/services/ai_provider.dart';
import 'package:chronos/core/services/app_log.dart';
import 'package:chronos/features/chat/services/llm_service.dart';
import 'package:chronos/features/memory/services/memory_service.dart';

/// 一次提炼的结果:新增条目列表(已去重)与新增条数。
class ExtractResult {
  final List<String> addedItems;
  final int added;
  const ExtractResult({required this.addedItems, required this.added});
}

/// 记忆提炼器(RikkaHub 式自动记忆):
/// 用「快速模型」(API 配置里单独配置的低成本模型,留空则复用对话模型)
/// 从对话中提取用户画像/事实/摘要,存入本地记忆表。可手动触发或对话后自动调用。
class MemoryExtractor {
  MemoryExtractor._();
  static final MemoryExtractor instance = MemoryExtractor._();

  /// 从最近对话提炼记忆并存入本地,返回新增条目(重复内容不计)。
  /// [history] 为用户与 AI 的对话(按时间正序);只取最近 40 条做提炼,
  /// 长会话不会把全部历史塞给快速模型(每条消息都会触发一次自动提炼)。
  /// 任何失败(模型输出格式漂移/网络)都记日志并返回空结果,绝不抛异常。
  Future<ExtractResult> extractFrom(
      List<({String role, String content})> history) async {
    if (history.isEmpty) return const ExtractResult(addedItems: [], added: 0);
    if (!await LlmService.instance.isConfigured()) {
      return const ExtractResult(addedItems: [], added: 0);
    }
    const maxHistory = 40;
    final slice = history.length > maxHistory
        ? history.sublist(history.length - maxHistory)
        : history;
    final fastModel = await AiProviders.fastModelRef();
    final prompt = '你是记忆提炼助手。根据下面的对话,提炼用户的长期记忆:\n'
        '1) profile:用户稳定身份/喜好/习惯(如有)\n'
        '2) fact:明确提到的重要事实(如有)\n'
        '3) summary:用一段话概括本次对话\n'
        '只输出 JSON:{"profile":["..."],"facts":["..."],"summary":"..."},不要多余文字。\n\n'
        '对话:\n'
        '${slice.map((m) => '${m.role == 'user' ? '用户' : 'AI'}:${m.content}').join('\n')}';
    final reply = await LlmService.instance.chat(
      history: [
        (role: 'user', content: prompt, reasoningContent: null)
      ],
      persona: '你是记忆提炼助手。',
      // 快速模型:留空则复用聊天模型
      modelRef: fastModel.isEmpty ? null : fastModel,
    );
    final cleaned = reply
        .replaceAll(RegExp(r'^```(json)?', multiLine: true), '')
        .replaceAll('```', '')
        .trim();

    // 解析零兜底:快速模型输出格式漂移(非 JSON / 字段类型不符 / 空回复)
    // 时记日志并静默跳过本次提炼,绝不把异常上抛打断调用方。
    final Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is! Map<String, dynamic>) {
        AppLog.instance.e('记忆提炼:模型输出不是 JSON 对象,跳过本次提炼');
        return const ExtractResult(addedItems: [], added: 0);
      }
      data = decoded;
    } catch (e) {
      AppLog.instance.e('记忆提炼:模型输出解析失败,跳过本次提炼:$e');
      return const ExtractResult(addedItems: [], added: 0);
    }

    // 字段容忍解析:类型不符(如 profile 是字符串而非数组)按缺失处理。
    List<String> listOf(Object? v) => v is List
        ? v.whereType<String>().map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
        : const [];

    final addedItems = <String>[];
    // add() 内部去重:重复内容返回 0,只统计真正新增的条数。
    for (final p in listOf(data['profile'])) {
      final id = await MemoryService.instance
          .add(kind: 'profile', content: p, source: 'chat');
      if (id > 0) addedItems.add(p);
    }
    for (final f in listOf(data['facts'])) {
      final id = await MemoryService.instance
          .add(kind: 'fact', content: f, source: 'chat');
      if (id > 0) addedItems.add(f);
    }
    final summary = data['summary'];
    final s = summary is String ? summary.trim() : '';
    if (s.isNotEmpty) {
      final id = await MemoryService.instance
          .add(kind: 'summary', content: s, source: 'chat');
      if (id > 0) addedItems.add(s);
    }
    return ExtractResult(addedItems: addedItems, added: addedItems.length);
  }
}
