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

  /// 造一个 v9 结构的日记表(entry_date 带 UNIQUE),模拟旧版本库。
  Future<Database> openV9WithDiary() async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
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
        inMemoryDatabasePath,
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
        inMemoryDatabasePath,
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
}
