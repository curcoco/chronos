import 'dart:async';
import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

import 'package:chronos/features/memory/models/memory_item.dart';
import 'package:chronos/core/services/db_helper.dart';

/// AI 长期记忆服务(本地 SQLite 为主;外置记忆见 NocturneService)
class MemoryService {
  MemoryService._();
  static final MemoryService instance = MemoryService._();
  DbHelper get _db => DbHelper.instance;

  static const List<String> kinds = ['profile', 'fact', 'summary'];
  static const Map<String, String> kindLabels = {
    'profile': '画像',
    'fact': '事实',
    'summary': '摘要',
  };

  /// 新增一条记忆;返回新行 id。空内容或同 kind 下已存在完全相同内容(去重)时返回 0 不插入。
  /// [importance]/[pinned]/[visibility]/[domain]/[tags] 为可选元数据,供手动添加/提炼带参传入。
  Future<int> add({
    required String kind,
    required String content,
    String source = 'manual',
    int importance = 5,
    bool pinned = false,
    String visibility = 'public',
    String? domain,
    List<String> tags = const [],
  }) async {
    final db = await _db.database;
    final text = content.trim();
    if (text.isEmpty) return 0;
    // 去重:同一 kind 下内容完全相同视为重复(避免反复提炼堆积)。
    final dup = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM memories WHERE kind = ? AND content = ?',
          [kind, text],
        )) ??
        0;
    if (dup > 0) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      return await db.insert('memories', MemoryItem(
        kind: kind,
        content: text,
        source: source,
        createdAt: now,
        updatedAt: now,
        importance: importance.clamp(1, 10),
        pinned: pinned,
        visibility: visibility,
        domain: domain,
        tags: tags,
      ).toMap());
    } on DatabaseException catch (e) {
      // v14 唯一索引兜底:并发/重复插入的唯一约束冲突视为「已存在」;
      // 其它真实 DB 失败(磁盘满/库损坏)必须上抛,让上层可见并记日志,
      // 不能与「去重」混为一谈静默吞掉。
      if (e.isUniqueConstraintError()) return 0;
      rethrow;
    }
  }

  Future<List<MemoryItem>> list({String? kind}) async {
    final db = await _db.database;
    final rows = await db.query(
      'memories',
      where: kind == null ? null : 'kind = ?',
      whereArgs: kind == null ? null : [kind],
      orderBy: 'updated_at DESC',
    );
    return rows.map(MemoryItem.fromMap).toList();
  }

  Future<void> delete(int id) async {
    final db = await _db.database;
    await db.delete('memories', where: 'id = ?', whereArgs: [id]);
  }

  /// 撤销删除:按原内容重新插入(保留 source;同 kind 下已存在相同内容时
  /// 视为已恢复,返回 0)。
  Future<int> restore(MemoryItem item) =>
      add(kind: item.kind, content: item.content, source: item.source);

  /// 编辑一条记忆的内容(与 [add] 同一校验口径:trim + 非空,避免空串入库)。
  /// 可选元数据参数,仅当非 null 时才写入(空串 content 直接返回)。
  Future<void> update(
    int id,
    String content, {
    int? importance,
    bool? pinned,
    String? visibility,
    String? domain,
    List<String>? tags,
  }) async {
    final text = content.trim();
    if (text.isEmpty) return;
    final db = await _db.database;
    final updates = <String, Object?>{
      'content': text,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    };
    if (importance != null) updates['importance'] = importance.clamp(1, 10);
    if (pinned != null) updates['pinned'] = pinned ? 1 : 0;
    if (visibility != null) updates['visibility'] = visibility;
    if (domain != null) updates['domain'] = domain;
    if (tags != null) updates['tags'] = List<String>.from(tags).join('|');
    await db.update('memories', updates, where: 'id = ?', whereArgs: [id]);
  }

  /// 拼装注入到对话 system prompt 的「长期记忆」文本(全量版,兼容旧调用)。
  Future<String> promptSection() async {
    final all = await list();
    if (all.isEmpty) return '';
    final profiles = all.where((m) => m.kind == 'profile').take(10);
    final facts = all.where((m) => m.kind == 'fact').take(10);
    final summaries = all.where((m) => m.kind == 'summary').take(3);
    final buf = StringBuffer('\n\n【关于用户的长期记忆,回答时可参考】\n');
    if (profiles.isNotEmpty) {
      buf.write('用户画像:\n');
      for (final m in profiles) {
        buf.write('- ${m.content}\n');
      }
    }
    if (facts.isNotEmpty) {
      buf.write('已知事实:\n');
      for (final m in facts) {
        buf.write('- ${m.content}\n');
      }
    }
    if (summaries.isNotEmpty) {
      buf.write('近期对话摘要:\n');
      for (final m in summaries) {
        buf.write('- ${m.content}\n');
      }
    }
    return buf.toString();
  }

  /// 记忆浮现评分(自然衰减 + 软饱和,InternalBeyond 式):
  /// pinned 恒最高;否则 重要性 × 激活因子(软饱和<2) × 衰减 exp(-λ·天)。
  /// 已解决记忆衰减更快(λ=0.12 vs 0.05)。
  double recallScore(MemoryItem m) {
    if (m.pinned) return 999999;
    final now = DateTime.now().millisecondsSinceEpoch;
    final activeAt = m.lastActivated ?? m.createdAt;
    final days = math.max(0.0, (now - activeAt) / 86400000);
    final lambda = m.resolved ? 0.12 : 0.05;
    final decay = math.exp(-lambda * days);
    final activationFactor = 1 + m.activationCount / (m.activationCount + 300);
    return m.importance * activationFactor * decay;
  }

  /// 本地关键词提取(零 token):英文单词≥3 + 中文 2/3 字 n-gram。
  List<String> extractKeywords(String text) {
    final cleaned =
        text.replaceAll(RegExp(r'[\[\]()（）【】「」《》、，。！？；：\s]'), ' ');
    final kws = <String>{};
    for (final w in RegExp(r'[a-zA-Z]{3,}').allMatches(cleaned)) {
      kws.add(w.group(0)!.toLowerCase());
    }
    final zh = cleaned.replaceAll(RegExp(r'[a-zA-Z0-9\s]+'), '');
    for (var i = 0; i < zh.length - 1; i++) {
      kws.add(zh.substring(i, i + 2));
      if (i < zh.length - 2) kws.add(zh.substring(i, i + 3));
    }
    return kws.toList();
  }

  /// 语义相关性(本地命中加成,最高 2.5×):命中数 / 关键词数。
  double _relevance(MemoryItem m, List<String> keywords) {
    if (keywords.isEmpty) return 1;
    final hay = '${m.content}|${m.tags.join('|')}|${m.domain ?? ''}'
        .toLowerCase();
    var hits = 0;
    for (final kw in keywords) {
      if (hay.contains(kw)) hits++;
    }
    return 1 + (hits / keywords.length) * 1.5;
  }

  /// 记录一次记忆被检索/激活(次数+1,更新 last_activated),长用记忆更稳定。
  Future<void> touchActivated(List<MemoryItem> items) async {
    if (items.isEmpty) return;
    final db = await _db.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final m in items) {
      batch.update(
        'memories',
        {
          'activation_count': m.activationCount + 1,
          'last_activated': now,
        },
        where: 'id = ?',
        whereArgs: [m.id],
      );
    }
    await batch.commit(noResult: true);
  }

  /// 相关条目注入(浮现代替全量):按「浮现分 × 相关性」排序,只注入
  /// public 记忆,pinned 常驻最前,在 [maxChars] 字符预算内依次填入。
  /// 无相关时也按浮现分取最值得的若干条,而非机械最近 N 条。
  Future<String> promptSectionFor(String query,
      {int maxChars = 1200}) async {
    final all = await list();
    if (all.isEmpty) return '';
    final keywords = extractKeywords(query);
    // 只注入 public 记忆。
    final injectable = all.where((m) => m.visibility == 'public').toList();
    if (injectable.isEmpty) return '';

    final scored = injectable
        .map((m) => (
              item: m,
              // Auto Memory 档案(source='auto')略高优先,让「关于用户的认知」更稳。
              score: recallScore(m) *
                  _relevance(m, keywords) *
                  (m.source == 'auto' ? 1.1 : 1),
            ))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final buf = StringBuffer('\n\n【关于用户的长期记忆,回答时可参考】\n');
    var used = 0;
    final picked = <MemoryItem>[];
    for (final e in scored) {
      // Auto Memory 档案带 #id,供掌柜在后续 <mem_edit>/<mem_delete> 里引用。
      final idTag = e.item.source == 'auto' ? ' #${e.item.id}' : '';
      final line =
          '- [${kindLabels[e.item.kind] ?? e.item.kind}]$idTag ${e.item.content}\n';
      if (used > 0 && used + line.length > maxChars) break;
      buf.write(line);
      used += line.length;
      picked.add(e.item);
    }
    if (picked.isEmpty) return '';
    // 异步记录激活(不阻塞注入)。
    unawaited(touchActivated(picked));
    return buf.toString();
  }
}
