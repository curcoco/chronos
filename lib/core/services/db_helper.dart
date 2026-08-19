import 'dart:io';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

/// SQLite 本地数据库单例:任务 / 灵感 / 心愿 / 金币记录
class DbHelper {
  DbHelper._();
  static final DbHelper instance = DbHelper._();

  /// 当前数据库版本(结构变更时递增)
  static const int dbVersion = 13;

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  /// 关闭并释放当前连接(下次访问会重新打开)。
  /// 用于「从备份恢复」等需要先释放 .db 文件句柄的场景。
  Future<void> close() async {
    final db = _db;
    _db = null;
    if (db != null) await db.close();
  }

  /// 当前数据库文件的绝对路径。
  Future<String> databasePath() async =>
      join(await getDatabasesPath(), 'student_workbench.db');

  Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'student_workbench.db');
    // 结构升级前先做一次原始文件备份(安全网):迁移出错时可回滚。
    await _backupBeforeUpgradeIfNeeded(path);
    return openDatabase(
      path,
      version: dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// 若检测到本地库版本低于目标版本,升级前把原始 .db 文件复制一份到
  /// 同目录 backups/ 下(带时间戳),作为迁移失败时的回滚安全网。
  /// 任何异常都不阻断正常打开流程(备份是尽力而为)。
  Future<void> _backupBeforeUpgradeIfNeeded(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return; // 首次安装,无需备份
      // 只读打开读取现有版本号,避免触发升级。
      final probe = await openDatabase(path, readOnly: true);
      final oldVersion = await probe.getVersion();
      await probe.close();
      if (oldVersion >= dbVersion) return; // 无需升级
      final dir = Directory(join(dirname(path), 'backups'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final now = DateTime.now();
      String two(int v) => v.toString().padLeft(2, '0');
      final stamp =
          '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}';
      final dest =
          join(dir.path, 'pre-migrate-v$oldVersion-$stamp.db');
      await file.copy(dest);
    } catch (_) {
      // 备份失败不影响 App 正常打开
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await runMigrations(db, oldVersion, newVersion);
  }

  /// 迁移逻辑(公开供测试直接驱动:用 ffi 造旧版本库后调用此方法验证)。
  static Future<void> runMigrations(
      Database db, int oldVersion, int newVersion) async {
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
    // v10:日记支持「一天多篇、无上限」——去掉 entry_date 的 UNIQUE 约束。
    // SQLite 无法直接删除列约束,需重建表并迁移数据。
    if (oldVersion < 10) {
      await _migrateDiaryDropUnique(db);
    }
    // v11:修复 notes 表缺列。历史上 _onCreate(全新安装)漏建了 favorite/mood 两列,
    // 而 addNote(mood: ...) 会写入 mood 列 → 全新装机的用户保存灵感时因
    // "no column named mood" 静默失败(灵感速记无法保存)。这里按列存在性补齐,
    // 已有该列的升级用户不受影响。
    if (oldVersion < 11) {
      await _ensureNotesColumns(db);
    }
    // v12:闲话铺会话管理 —— 取消「零点万事清零」,聊天按会话长期保存。
    // chat_sessions:会话(标题/创建/更新时间);chat_messages:会话内消息。
    if (oldVersion < 12) {
      await _createChatTables(db);
    }
    // v13:健康-视频跟练支持用户自传视频(user_videos 表)。
    if (oldVersion < 13) {
      await _createUserVideosTable(db);
    }
  }

  /// 确保 notes 表含 favorite / mood 列(缺则补;已有则跳过,避免重复列报错)。
  static Future<void> _ensureNotesColumns(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(notes)');
    if (cols.isEmpty) return; // notes 表不存在(理论上不会发生),不处理。
    final names = cols.map((c) => c['name'] as String).toSet();
    if (!names.contains('favorite')) {
      await db.execute(
          'ALTER TABLE notes ADD COLUMN favorite INTEGER NOT NULL DEFAULT 0');
    }
    if (!names.contains('mood')) {
      await db.execute('ALTER TABLE notes ADD COLUMN mood TEXT');
    }
  }

  /// 重建 diary_entries,去掉 entry_date 的 UNIQUE 约束(一天可多篇)。
  static Future<void> _migrateDiaryDropUnique(Database db) async {
    await db.transaction((txn) async {
      await txn.execute('ALTER TABLE diary_entries RENAME TO diary_entries_old');
      await txn.execute('''
        CREATE TABLE diary_entries(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          content TEXT NOT NULL,
          mood TEXT,
          entry_date TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      await txn.execute('''
        INSERT INTO diary_entries (id, content, mood, entry_date, created_at, updated_at)
        SELECT id, content, mood, entry_date, created_at, updated_at FROM diary_entries_old
      ''');
      await txn.execute('DROP TABLE diary_entries_old');
      await txn.execute(
          'CREATE INDEX idx_diary_date ON diary_entries(entry_date)');
    });
  }

  static Future<void> _createPlanTable(Database db) async {
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

  static Future<void> _createBatch3Tables(Database db) async {
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

  static Future<void> _createBatch2Tables(Database db) async {
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
        created_at INTEGER NOT NULL,
        favorite INTEGER NOT NULL DEFAULT 0,
        mood TEXT
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
        entry_date TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_diary_date ON diary_entries(entry_date)');
    await _createPlanTable(db);
    await _createChatTables(db);
    await _createUserVideosTable(db);
  }

  /// 用户自传跟练视频表(标题/本地文件路径/备注)。
  static Future<void> _createUserVideosTable(Database db) async {
    await db.execute('''
      CREATE TABLE user_videos(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        path TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL
      )
    ''');
  }

  /// 闲话铺会话表:chat_sessions(会话)+ chat_messages(消息)。
  /// v12 起取消「零点万事清零」,聊天按会话长期保存。
  static Future<void> _createChatTables(Database db) async {
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
    await db.execute(
        'CREATE INDEX idx_chat_msg_session ON chat_messages(session_id)');
  }
}
