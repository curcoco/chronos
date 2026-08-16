import 'package:sqflite/sqflite.dart';

import '../models/memory_item.dart';
import 'db_helper.dart';

/// AI 长期记忆服务(本地 SQLite 为主;云端同步由 SupabaseSyncService 负责)
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

  Future<void> markSynced(int id) async {
    final db = await _db.database;
    await db.update('memories', {'cloud_synced': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<List<MemoryItem>> unsynced() async {
    final db = await _db.database;
    final rows = await db.query('memories',
        where: 'cloud_synced = 0', orderBy: 'created_at ASC');
    return rows.map(MemoryItem.fromMap).toList();
  }

  /// 拼装注入到对话 system prompt 的「长期记忆」文本
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
}
