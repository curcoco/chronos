import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:chronos/features/diary/models/diary_entry.dart';
import 'package:chronos/features/notes/models/note.dart';
import 'package:chronos/core/services/db_helper.dart';
import 'package:chronos/features/coins/models/wish.dart';
import 'package:chronos/features/coins/services/coin_service.dart';

/// 数据库层集成测试:用 sqflite_common_ffi 在桌面/CI 上跑真实 SQLite。
/// 覆盖两条高风险路径:
/// 1) v9 → v10 迁移不丢数据、且去掉了 diary_entries 的 UNIQUE 约束(一天可多篇)。
/// 2) 迁移后 diary/note 的 CRUD 语义正确。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  /// 每个测试用独立的内存库路径,避免跨测试共享(表残留/重复建表)。
  var memSeq = 0;
  String uniqueMemPath() => 'file:mem_${memSeq++}?mode=memory&cache=shared';

  /// 造一个 v9 结构的日记表(entry_date 带 UNIQUE),模拟旧版本库。
  Future<Database> openV9WithDiary() async {
    final db = await databaseFactory.openDatabase(
      uniqueMemPath(),
      options: OpenDatabaseOptions(version: 9),
    );
    await db.execute('''
      CREATE TABLE diary_entries(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        content TEXT NOT NULL,
        mood TEXT,
        entry_date TEXT NOT NULL UNIQUE,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    return db;
  }

  group('DB 迁移 v9 → v10', () {    test('迁移保留既有数据', () async {
      final db = await openV9WithDiary();
      await db.insert('diary_entries', {
        'content': '旧日记',
        'mood': 'happy',
        'entry_date': '2026-08-17',
        'created_at': 1000,
        'updated_at': 1000,
      });

      await DbHelper.runMigrations(db, 9, DbHelper.dbVersion);

      final rows = await db.query('diary_entries');
      expect(rows.length, 1);
      expect(rows.first['content'], '旧日记');
      expect(rows.first['entry_date'], '2026-08-17');
      await db.close();
    });

    test('迁移后同一天可插入多篇(UNIQUE 约束已移除)', () async {
      final db = await openV9WithDiary();
      await db.insert('diary_entries', {
        'content': '第一篇',
        'entry_date': '2026-08-17',
        'created_at': 1000,
        'updated_at': 1000,
      });

      await DbHelper.runMigrations(db, 9, DbHelper.dbVersion);

      // 迁移前若插入同日期会因 UNIQUE 抛错;迁移后应成功。
      await db.insert('diary_entries', {
        'content': '第二篇',
        'entry_date': '2026-08-17',
        'created_at': 2000,
        'updated_at': 2000,
      });

      final sameDay = await db.query('diary_entries',
          where: 'entry_date = ?', whereArgs: ['2026-08-17']);
      expect(sameDay.length, 2);
      await db.close();
    });
  });

  group('DB 迁移 v11:补齐 notes 缺失的 favorite/mood 列', () {
    /// 造一个"全新安装漏建列"的旧 notes 表:只有 id/content/created_at。
    Future<Database> openNotesMissingCols(int version) async {
      final db = await databaseFactory.openDatabase(
        uniqueMemPath(),
        options: OpenDatabaseOptions(version: version),
      );
      await db.execute('''
        CREATE TABLE notes(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          content TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');
      return db;
    }

    test('迁移前写入 mood 会失败,迁移后补列可成功保存', () async {
      final db = await openNotesMissingCols(10);

      // 迁移前:插入含 mood 的行应抛错(复现"灵感速记保存失败")。
      await expectLater(
        db.insert('notes',
            {'content': '灵感', 'created_at': 1, 'mood': 'happy'}),
        throwsA(anything),
      );

      await DbHelper.runMigrations(db, 10, DbHelper.dbVersion);

      // 迁移后:favorite/mood 列已补齐,保存成功。
      final id = await db.insert('notes', {
        'content': '灵感',
        'created_at': 2,
        'favorite': 1,
        'mood': 'happy',
      });
      expect(id, greaterThan(0));

      final rows = await db.query('notes', where: 'id = ?', whereArgs: [id]);
      expect(rows.first['mood'], 'happy');
      expect(rows.first['favorite'], 1);
      await db.close();
    });

    test('已含列的库再次迁移不报错(幂等)', () async {
      final db = await databaseFactory.openDatabase(
        uniqueMemPath(),
        options: OpenDatabaseOptions(version: 10),
      );
      await db.execute('''
        CREATE TABLE notes(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          content TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          favorite INTEGER NOT NULL DEFAULT 0,
          mood TEXT
        )
      ''');
      // 不应因列已存在而抛错。
      await DbHelper.runMigrations(db, 10, DbHelper.dbVersion);
      final cols = await db.rawQuery('PRAGMA table_info(notes)');
      final names = cols.map((c) => c['name'] as String).toSet();
      expect(names.containsAll({'favorite', 'mood'}), isTrue);
      await db.close();
    });
  });

  group('模型 <-> Map 往返', () {    test('DiaryEntry toMap/fromMap 一致', () {
      const e = DiaryEntry(
        content: '内容',
        mood: 'calm',
        date: '2026-08-17',
        createdAt: 111,
        updatedAt: 222,
      );
      final back = DiaryEntry.fromMap({...e.toMap(), 'id': 5});
      expect(back.id, 5);
      expect(back.content, '内容');
      expect(back.mood, 'calm');
      expect(back.date, '2026-08-17');
      expect(back.createdAt, 111);
      expect(back.updatedAt, 222);
    });

    test('Note toMap/fromMap 一致(含收藏/心情)', () {
      const n = Note(
        content: '灵感',
        createdAt: 999,
        favorite: true,
        mood: 'sad',
      );
      final back = Note.fromMap({...n.toMap(), 'id': 3});
      expect(back.id, 3);
      expect(back.content, '灵感');
      expect(back.favorite, isTrue);
      expect(back.mood, 'sad');
    });
  });

  group('DB 迁移 v12:闲话铺会话表', () {
    Future<Database> openV11() async {
      final db = await databaseFactory.openDatabase(
        uniqueMemPath(),
        options: OpenDatabaseOptions(version: 11),
      );
      await db.execute('''
        CREATE TABLE tasks(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL,
          task_date TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');
      return db;
    }

    test('迁移后创建 chat_sessions / chat_messages 并可读写', () async {
      final db = await openV11();
      await DbHelper.runMigrations(db, 11, DbHelper.dbVersion);

      final now = 1000;
      final sid = await db.insert('chat_sessions', {
        'title': '闲聊',
        'created_at': now,
        'updated_at': now,
      });
      expect(sid, greaterThan(0));

      final mid = await db.insert('chat_messages', {
        'session_id': sid,
        'role': 'user',
        'content': '你好',
        'created_at': now,
      });
      expect(mid, greaterThan(0));

      final msgs = await db.query('chat_messages',
          where: 'session_id = ?', whereArgs: [sid]);
      expect(msgs.length, 1);
      expect(msgs.first['content'], '你好');

      // 跨天不清空:迁移后插入不同日期的消息仍保留(取消零点清零)。
      final later = await db.insert('chat_messages', {
        'session_id': sid,
        'role': 'assistant',
        'content': '在的',
        'created_at': now + 86400000,
      });
      expect(later, greaterThan(0));
      final all = await db.query('chat_messages',
          where: 'session_id = ?', whereArgs: [sid]);
      expect(all.length, 2);
      await db.close();
    });

    test('已含会话表的库再次迁移不报错(幂等)', () async {
      final db = await openV11();
      // 第一次:11 → 13 建表。
      await DbHelper.runMigrations(db, 11, DbHelper.dbVersion);
      // 第二次:模拟数据库已到当前版本,再次调用不重复建表、不报错。
      await DbHelper.runMigrations(db, DbHelper.dbVersion, DbHelper.dbVersion);
      final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'");
      final names = tables.map((r) => r['name'] as String).toSet();
      expect(names.containsAll({'chat_sessions', 'chat_messages'}), isTrue);
      await db.close();
    });
  });

  group('DB 迁移 v13:用户自传跟练视频表', () {
    Future<Database> openV12() async {
      final db = await databaseFactory.openDatabase(
        uniqueMemPath(),
        options: OpenDatabaseOptions(version: 12),
      );
      await db.execute('''
        CREATE TABLE chat_sessions(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL DEFAULT '',
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      return db;
    }

    test('迁移后创建 user_videos 并可读写删除', () async {
      final db = await openV12();
      await DbHelper.runMigrations(db, 12, DbHelper.dbVersion);

      final id = await db.insert('user_videos', {
        'title': '晨间拉伸',
        'path': '/data/video.mp4',
        'note': '10 分钟',
        'created_at': 1000,
      });
      expect(id, greaterThan(0));

      final rows = await db.query('user_videos', where: 'id = ?', whereArgs: [id]);
      expect(rows.length, 1);
      expect(rows.first['title'], '晨间拉伸');

      await db.delete('user_videos', where: 'id = ?', whereArgs: [id]);
      final after = await db.query('user_videos');
      expect(after, isEmpty);
      await db.close();
    });

    test('已含视频表的库再次迁移不报错(幂等)', () async {
      final db = await openV12();
      await DbHelper.runMigrations(db, 12, DbHelper.dbVersion);
      await DbHelper.runMigrations(db, 13, DbHelper.dbVersion);
      final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table'");
      final names = tables.map((r) => r['name'] as String).toSet();
      expect(names.contains('user_videos'), isTrue);
      await db.close();
    });
  });

  group('记账流水删除与撤销(LedgerService.deleteTxn/restoreTxn 依赖的 SQL 语义)', () {
    /// 只建 ledger_txns 一张表即可验证删除/撤销语义(与 v3 建表结构一致)。
    Future<Database> openLedgerDb() async {
      final db = await databaseFactory.openDatabase(
        uniqueMemPath(),
        options: OpenDatabaseOptions(version: 1),
      );
      await db.execute('''
        CREATE TABLE ledger_txns(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          type TEXT NOT NULL,
          amount REAL NOT NULL,
          category TEXT NOT NULL,
          note TEXT NOT NULL DEFAULT '',
          txn_date TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');
      return db;
    }

    test('删除后记录消失(记错可删)', () async {
      final db = await openLedgerDb();
      final id = await db.insert('ledger_txns', {
        'type': 'expense',
        'amount': 12.5,
        'category': '餐饮',
        'note': '午饭',
        'txn_date': '2026-08-17',
        'created_at': 100,
      });
      expect(id, greaterThan(0));

      await db.delete('ledger_txns', where: 'id = ?', whereArgs: [id]);
      final after = await db.query('ledger_txns');
      expect(after, isEmpty);
      await db.close();
    });

    test('撤销:按原 id/时间插回,字段完整(id 被保留)', () async {
      final db = await openLedgerDb();
      final id = await db.insert('ledger_txns', {
        'type': 'income',
        'amount': 50,
        'category': '零花钱',
        'note': '',
        'txn_date': '2026-08-17',
        'created_at': 200,
      });
      await db.delete('ledger_txns', where: 'id = ?', whereArgs: [id]);

      // 模拟 restoreTxn:用原 toMap(含 id)重新插入。
      final restoredId = await db.insert('ledger_txns', {
        'id': id,
        'type': 'income',
        'amount': 50,
        'category': '零花钱',
        'note': '',
        'txn_date': '2026-08-17',
        'created_at': 200,
      });
      expect(restoredId, id); // 原 id 保留,撤销后数据一致
      final row = (await db.query('ledger_txns')).single;
      expect(row['type'], 'income');
      expect((row['amount'] as num).toDouble(), 50);
      expect(row['created_at'], 200);
      await db.close();
    });
  });

  group('DB 迁移 v14:聊天消息图片落库 + 记忆唯一索引', () {
    /// 造一个 v13 结构的库(chat 两张表 + memories,均无 v14 的新能力)。
    Future<Database> openV13() async {
      final db = await databaseFactory.openDatabase(
        uniqueMemPath(),
        options: OpenDatabaseOptions(version: 13),
      );
      await db.execute('''
        CREATE TABLE chat_sessions(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL DEFAULT '',
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE chat_messages(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id INTEGER NOT NULL,
          role TEXT NOT NULL,
          content TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE memories(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          kind TEXT NOT NULL,
          content TEXT NOT NULL,
          source TEXT NOT NULL DEFAULT 'manual',
          cloud_synced INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      return db;
    }

    test('迁移后 chat_messages 有 image_path:旧消息保留、可写图片路径', () async {
      final db = await openV13();
      final sid = await db.insert('chat_sessions',
          {'title': '闲聊', 'created_at': 1, 'updated_at': 1});
      await db.insert('chat_messages',
          {'session_id': sid, 'role': 'user', 'content': '旧消息', 'created_at': 1});

      await DbHelper.runMigrations(db, 13, DbHelper.dbVersion);

      // 旧消息仍在
      final old = await db.query('chat_messages');
      expect(old.length, 1);
      expect(old.first['content'], '旧消息');
      // 新列可写:发图消息带本地图片路径
      final mid = await db.insert('chat_messages', {
        'session_id': sid,
        'role': 'user',
        'content': '带图消息\n[图片]',
        'image_path': '/docs/chat_imgs/msg_1.jpg',
        'created_at': 2,
      });
      expect(mid, greaterThan(0));
      final row =
          (await db.query('chat_messages', where: 'id = ?', whereArgs: [mid]))
              .single;
      expect(row['image_path'], '/docs/chat_imgs/msg_1.jpg');
      await db.close();
    });

    test('迁移清理记忆重复并建唯一索引:重复插入被拒、最早一条保留', () async {
      final db = await openV13();
      await db.insert('memories',
          {'kind': 'fact', 'content': '喜欢数学', 'created_at': 1, 'updated_at': 1});
      await db.insert('memories',
          {'kind': 'fact', 'content': '喜欢数学', 'created_at': 2, 'updated_at': 2});
      await db.insert('memories',
          {'kind': 'profile', 'content': '初三', 'created_at': 3, 'updated_at': 3});

      await DbHelper.runMigrations(db, 13, DbHelper.dbVersion);

      // 重复只剩最早一条
      final facts =
          await db.query('memories', where: 'kind = ?', whereArgs: ['fact']);
      expect(facts.length, 1);
      expect(facts.first['created_at'], 1);
      // 唯一索引生效:同 kind+content 重复插入被拒
      await expectLater(
        db.insert('memories', {
          'kind': 'fact',
          'content': '喜欢数学',
          'created_at': 9,
          'updated_at': 9,
        }),
        throwsA(anything),
      );
      await db.close();
    });
  });

  group('DB 迁移 v15:chat_messages 加 reasoning_content(推理模型回传)', () {
    /// 造一个 v14 结构的库(chat 表有 image_path,无 reasoning_content)。
    Future<Database> openV14() async {
      final db = await databaseFactory.openDatabase(
        uniqueMemPath(),
        options: OpenDatabaseOptions(version: 14),
      );
      await db.execute('''
        CREATE TABLE chat_sessions(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          title TEXT NOT NULL DEFAULT '',
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE chat_messages(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id INTEGER NOT NULL,
          role TEXT NOT NULL,
          content TEXT NOT NULL,
          image_path TEXT,
          created_at INTEGER NOT NULL
        )
      ''');
      return db;
    }

    test('迁移后 chat_messages 有 reasoning_content:旧消息保留、可写思维链', () async {
      final db = await openV14();
      final sid = await db.insert('chat_sessions',
          {'title': '闲聊', 'created_at': 1, 'updated_at': 1});
      await db.insert('chat_messages', {
        'session_id': sid,
        'role': 'assistant',
        'content': '旧回复',
        'created_at': 1,
      });

      await DbHelper.runMigrations(db, 14, DbHelper.dbVersion);

      // 旧消息仍在
      final old = await db.query('chat_messages');
      expect(old.length, 1);
      expect(old.first['content'], '旧回复');
      // 新列可写:推理模型回复带思维链
      final mid = await db.insert('chat_messages', {
        'session_id': sid,
        'role': 'assistant',
        'content': '思考后回答',
        'reasoning_content': '第一步…第二步…',
        'created_at': 2,
      });
      expect(mid, greaterThan(0));
      final row =
          (await db.query('chat_messages', where: 'id = ?', whereArgs: [mid]))
              .single;
      expect(row['reasoning_content'], '第一步…第二步…');
      await db.close();
    });
  });

  group('DB 迁移 v16:memories 加「情感衰减/浮现/可见性」列', () {
    /// 造一个 v15 结构的库(有 memories 表,但无 v16 新列)。
    Future<Database> openV15Memories() async {
      final db = await databaseFactory.openDatabase(
        uniqueMemPath(),
        options: OpenDatabaseOptions(version: 15),
      );
      await db.execute('''
        CREATE TABLE memories(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          kind TEXT NOT NULL,
          content TEXT NOT NULL,
          source TEXT,
          created_at INTEGER NOT NULL
        )
      ''');
      // 补上 v14 唯一索引,贴近真实旧库
      await db.execute(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_memories_kind_content '
          'ON memories(kind, content)');
      return db;
    }

    test('迁移后 memories 有 importance/pinned/visibility 等列:旧数据保留、默认值生效', () async {
      final db = await openV15Memories();
      await db.insert('memories',
          {'kind': 'fact', 'content': '旧记忆', 'created_at': 1});

      await DbHelper.runMigrations(db, 15, DbHelper.dbVersion);

      // 旧数据仍在
      final old = await db.query('memories');
      expect(old.length, 1);
      expect(old.first['content'], '旧记忆');
      // 新列默认值:importance=5, pinned=0, visibility='public'
      expect(old.first['importance'], 5);
      expect(old.first['pinned'], 0);
      expect(old.first['visibility'], 'public');
      expect(old.first['activation_count'], 0);
      // 新列可写:标记重要/置顶/私有
      final mid = old.first['id'] as int;
      await db.update('memories', {
        'importance': 10,
        'pinned': 1,
        'visibility': 'private',
        'tags': '重要|待办',
      }, where: 'id = ?', whereArgs: [mid]);
      final row =
          (await db.query('memories', where: 'id = ?', whereArgs: [mid])).single;
      expect(row['importance'], 10);
      expect(row['pinned'], 1);
      expect(row['visibility'], 'private');
      expect(row['tags'], '重要|待办');
      await db.close();
    });

    test('已含 v16 新列的库再次迁移不报错(幂等)', () async {
      final db = await openV15Memories();
      // 先补上所有新列,模拟已升级到 v16 的库
      for (final ddl in [
        'ALTER TABLE memories ADD COLUMN importance INTEGER NOT NULL DEFAULT 5',
        'ALTER TABLE memories ADD COLUMN pinned INTEGER NOT NULL DEFAULT 0',
        'ALTER TABLE memories ADD COLUMN last_activated INTEGER',
        'ALTER TABLE memories ADD COLUMN activation_count INTEGER NOT NULL DEFAULT 0',
        'ALTER TABLE memories ADD COLUMN resolved INTEGER NOT NULL DEFAULT 0',
        "ALTER TABLE memories ADD COLUMN visibility TEXT NOT NULL DEFAULT 'public'",
        'ALTER TABLE memories ADD COLUMN domain TEXT',
        'ALTER TABLE memories ADD COLUMN tags TEXT',
      ]) {
        await db.execute(ddl);
      }

      await DbHelper.runMigrations(db, 15, DbHelper.dbVersion);

      final cols = (await db.rawQuery('PRAGMA table_info(memories)'))
          .map((c) => c['name'] as String)
          .toSet();
      for (final col in {'importance', 'pinned', 'last_activated',
          'activation_count', 'resolved', 'visibility', 'domain', 'tags'}) {
        expect(cols.contains(col), isTrue, reason: '缺列 $col');
      }
      await db.close();
    });
  });

  group('CoinService 事务原子性(修复「并发/连点重复发币」)', () {
    setUp(() async {
      // 每个测试用全新库文件:关闭单例连接并删除 db(含 wal/shm)。
      await DbHelper.instance.close();
      final dir = await databaseFactory.getDatabasesPath();
      for (final name in [
        'student_workbench.db',
        'student_workbench.db-wal',
        'student_workbench.db-shm',
      ]) {
        final f = File(p.join(dir, name));
        if (await f.exists()) await f.delete();
      }
    });

    test('rewardDaily 并发两次只发放一次(查重+发放在同一事务)', () async {
      final results = await Future.wait([
        CoinService.instance.rewardEnglish('2026-08-20'),
        CoinService.instance.rewardEnglish('2026-08-20'),
      ]);
      // 两次调用只有一个成功发放(2 枚),另一个返回 0。
      expect(results.fold<int>(0, (s, v) => s + v), 2);
      expect(await CoinService.instance.earnedToday('2026-08-20'), 2);
      // 库里只有一条 english 记录
      final rows = await (await DbHelper.instance.database)
          .query('coin_records', where: "type = 'english'");
      expect(rows.length, 1);
    });

    test('redeemWish 并发兑换只成功一次、余额不为负、心愿标记一致', () async {
      final db = await DbHelper.instance.database;
      await db.insert('wishes', {
        'title': '测试心愿',
        'cost': 5,
        'redeemed': 0,
        'created_at': 1,
      });
      await CoinService.instance.addRecord(
          amount: 5, reason: '初始金币', type: 'bonus', date: '2026-08-20');
      final id = (await db.rawQuery('SELECT id FROM wishes LIMIT 1'))
          .single['id'] as int;
      final wish = Wish.fromMap({
        'id': id,
        'title': '测试心愿',
        'cost': 5,
        'redeemed': 0,
        'created_at': 1,
      });
      final results = await Future.wait([
        CoinService.instance.redeemWish(wish, '2026-08-20'),
        CoinService.instance.redeemWish(wish, '2026-08-20'),
      ]);
      expect(results.where((r) => r).length, 1); // 只有一次成功
      expect(await CoinService.instance.balance(), 0); // 5 - 5,不为负
      final row = (await db.query('wishes')).single;
      expect(row['redeemed'], 1);
    });
  });
}
