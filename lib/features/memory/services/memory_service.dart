import 'package:sqflite/sqflite.dart';

import 'package:student_workbench/features/memory/models/memory_item.dart';
import 'package:student_workbench/core/services/db_helper.dart';

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
  Future<int> add({
    required String kind,
    required String content,
    String source = 'manual',
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
    return db.insert('memories', MemoryItem(
      kind: kind,
      content: text,
      source: source,
      createdAt: now,
      updatedAt: now,
    ).toMap());
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

  /// 编辑一条记忆的内容
  Future<void> update(int id, String content) async {
    final db = await _db.database;
    await db.update('memories',
        {'content': content.trim(), 'updated_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?', whereArgs: [id]);
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

  /// 相关条目注入(RikkaHub 式):按 [query] 关键词匹配记忆,优先注入相关条目,
  /// 而不是全量塞入。无相关时回退最近 N 条,保证记忆多时也不膨胀。
  Future<String> promptSectionFor(String query) async {
    final all = await list();
    if (all.isEmpty) return '';
    // 关键词:拆出中文/英文词(长度 ≥2 的片段),去掉常见停用词。
    final q = query.toLowerCase();
    final tokens = RegExp(r'[\u4e00-\u9fa5]{2,}|[a-z]{3,}')
        .allMatches(q)
        .map((m) => m.group(0)!)
        .where((t) => !const {'今天', '明天', '昨天', '什么', '怎么', '可以'}.contains(t))
        .toList();

    int scoreOf(MemoryItem m) {
      final c = m.content.toLowerCase();
      var s = 0;
      for (final t in tokens) {
        if (c.contains(t)) s++;
      }
      return s;
    }

    // 按相关度排序,同分按更新时间新者优先。
    final scored = all.map((m) => (item: m, score: scoreOf(m))).toList()
      ..sort((a, b) {
        if (a.score != b.score) return b.score.compareTo(a.score);
        return b.item.updatedAt.compareTo(a.item.updatedAt);
      });
    // 相关条目(score>0)全取;无相关时取最近 5 条兜底。
    final relevant = scored.where((e) => e.score > 0).map((e) => e.item).toList();
    final picked = relevant.isNotEmpty ? relevant.take(10).toList() : scored.take(5).map((e) => e.item).toList();
    if (picked.isEmpty) return '';

    final buf = StringBuffer('\n\n【关于用户的长期记忆,回答时可参考】\n');
    for (final m in picked) {
      buf.write('- [${kindLabels[m.kind] ?? m.kind}] ${m.content}\n');
    }
    return buf.toString();
  }
}
