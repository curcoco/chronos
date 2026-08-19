import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:student_workbench/features/diary/models/diary_entry.dart';
import 'package:student_workbench/features/notes/models/note.dart';
import 'package:student_workbench/core/services/db_helper.dart';

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
}
