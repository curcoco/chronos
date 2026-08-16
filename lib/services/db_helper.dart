import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite 本地数据库单例:任务 / 灵感 / 心愿 / 金币记录
class DbHelper {
  DbHelper._();
  static final DbHelper instance = DbHelper._();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'student_workbench.db');
    return openDatabase(
      path,
      version: 8,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // v2:coin_records 增加 task_id,用于取消完成时精确收回金币
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE coin_records ADD COLUMN task_id INTEGER');
    }
    // v3:第二批模块 —— 复盘 / 英文收藏 / 记账流水 / 记账设置
    if (oldVersion < 3) {
      await _createBatch2Tables(db);
    }
    // v4:notes 增加收藏标记(灵感收藏)
    if (oldVersion < 4) {
      await db.execute(
          'ALTER TABLE notes ADD COLUMN favorite INTEGER NOT NULL DEFAULT 0');
    }
    // v5:notes 增加心情标记(随笔合并入灵感速记)+ 第三批健康模块表
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE notes ADD COLUMN mood TEXT');
      await _createBatch3Tables(db);
    }
    // v6:长期记忆表(AI 记忆:画像/事实/摘要,本地为主,可同步云端)
    if (oldVersion < 6) {
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
    }
    // v7:日记表(灵感速记 → 日记,按天一篇的长文本)
    if (oldVersion < 7) {
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
    }
    // v8:计划条目表(本周计划 / 长期目标,scope 区分:week / longterm)
    if (oldVersion < 8) {
      await _createPlanTable(db);
    }
  }

  Future<void> _createPlanTable(Database db) async {
    await db.execute('''
      CREATE TABLE plan_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        scope TEXT NOT NULL,
        title TEXT NOT NULL,
        detail TEXT NOT NULL DEFAULT '',
        done INTEGER NOT NULL DEFAULT 0,
        due_date TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_plan_scope ON plan_items(scope)');
  }

  Future<void> _createBatch3Tables(Database db) async {
    await db.execute('''
      CREATE TABLE kitchen_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        cat TEXT NOT NULL,
        name TEXT NOT NULL,
        cal INTEGER NOT NULL DEFAULT 0,
        price REAL NOT NULL DEFAULT 0,
        link TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE workouts(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT NOT NULL,
        minutes INTEGER NOT NULL,
        work_date TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE health_settings(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createBatch2Tables(Database db) async {
    await db.execute('''
      CREATE TABLE reviews(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        review_date TEXT NOT NULL UNIQUE,
        progress INTEGER NOT NULL DEFAULT 0,
        done TEXT NOT NULL DEFAULT '',
        problem TEXT NOT NULL DEFAULT '',
        plan TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE english_favs(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        fav_type TEXT NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        UNIQUE(fav_type, content)
      )
    ''');
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
    await db.execute(
        'CREATE INDEX idx_ledger_date ON ledger_txns(txn_date)');
    await db.execute('''
      CREATE TABLE ledger_settings(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE tasks(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        category TEXT NOT NULL DEFAULT '学习',
        priority INTEGER NOT NULL DEFAULT 1,
        done INTEGER NOT NULL DEFAULT 0,
        task_date TEXT NOT NULL,
        auto INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_tasks_date ON tasks(task_date)');

    await db.execute('''
      CREATE TABLE notes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE wishes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        cost INTEGER NOT NULL,
        redeemed INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE coin_records(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount INTEGER NOT NULL,
        reason TEXT NOT NULL,
        type TEXT NOT NULL,
        task_id INTEGER,
        rec_date TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_coin_date ON coin_records(rec_date)');

    await _createBatch2Tables(db);
    await _createBatch3Tables(db);
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
    await _createPlanTable(db);
  }
}
