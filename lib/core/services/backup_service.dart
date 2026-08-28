import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:chronos/core/services/app_log.dart';
import 'package:chronos/core/services/db_helper.dart';

/// 恢复结果:是否成功导入数据库、设置项条数。
class RestoreResult {
  final bool dbRestored;
  final int prefsRestored;
  const RestoreResult({required this.dbRestored, required this.prefsRestored});
}

/// 本地数据导出:把 SQLite 数据库与设置项打包成 zip,存到应用可访问目录,
/// 方便用户备份或迁移到新设备。不含 API 密钥等敏感信息。
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  /// 导出为 zip,返回保存后的文件绝对路径。
  Future<String> exportZip() async {
    final archive = Archive();

    // 1) SQLite 数据库文件(全部业务数据:任务/灵感/心愿/金币/日记/记忆/计划等)
    final dbPath = p.join(await getDatabasesPath(), 'student_workbench.db');
    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      final bytes = await dbFile.readAsBytes();
      archive.addFile(ArchiveFile('student_workbench.db', bytes.length, bytes));
    }

    // 2) 设置项(昵称/主题/城市/问候语等),导出为 JSON。排除 API 密钥(api_ 前缀)。
    final prefs = await SharedPreferences.getInstance();
    final map = <String, Object?>{};
    for (final key in prefs.getKeys()) {
      if (key.startsWith('api_')) continue; // 不导出密钥
      map[key] = prefs.get(key);
    }
    final prefsJson = const JsonEncoder.withIndent('  ').convert(map);
    final prefsBytes = utf8.encode(prefsJson);
    archive.addFile(
        ArchiveFile('preferences.json', prefsBytes.length, prefsBytes));

    // 3) 元信息
    final meta = jsonEncode({
      'app': 'Chronos',
      'exported_at': DateTime.now().toIso8601String(),
      'note': '本地数据备份。含数据库与设置(不含 API 密钥)。',
    });
    final metaBytes = utf8.encode(meta);
    archive.addFile(ArchiveFile('backup-info.json', metaBytes.length, metaBytes));

    // 4) 应用日志(便于问题复现);无内容则跳过。
    final logText = await AppLog.instance.exportText();
    if (logText.isNotEmpty) {
      final logBytes = utf8.encode(logText);
      archive.addFile(
          ArchiveFile('app_log.txt', logBytes.length, logBytes));
    }

    // 5) 图片类本地文件(头像 / 掌柜头像 / 背景图 / 聊天图片),换机迁移不丢图。
    try {
      final docs = await getApplicationDocumentsDirectory();
      for (final name in [
        'avatar.jpg', 'avatar.png',
        'shopkeeper_avatar.jpg', 'shopkeeper_avatar.png',
        'background.jpg', 'background.png',
      ]) {
        final f = File(p.join(docs.path, name));
        if (await f.exists()) {
          final bytes = await f.readAsBytes();
          archive.addFile(ArchiveFile('media/$name', bytes.length, bytes));
        }
      }
      // 聊天图片目录(闲话铺发图,随消息落库的本地文件)。
      final chatImgs = Directory(p.join(docs.path, 'chat_imgs'));
      if (await chatImgs.exists()) {
        await for (final f in chatImgs.list()) {
          if (f is! File) continue;
          final bytes = await f.readAsBytes();
          archive.addFile(ArchiveFile(
              'media/chat_imgs/${p.basename(f.path)}', bytes.length, bytes));
        }
      }
    } catch (_) {
      // 图片打包失败不阻断导出(核心数据仍是数据库)。
    }

    // 打包
    final encoded = ZipEncoder().encode(archive)!;

    // 保存目录:优先外部可访问目录,回退到应用文档目录
    Directory outDir;
    try {
      outDir = await getApplicationDocumentsDirectory();
      final ext = await getExternalStorageDirectory();
      if (ext != null) outDir = ext;
    } catch (_) {
      outDir = await getApplicationDocumentsDirectory();
    }
    final backupDir = Directory(p.join(outDir.path, 'ChronosBackups'));
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    final stamp = _stamp(DateTime.now());
    final outPath = p.join(backupDir.path, 'chronos-backup-$stamp.zip');
    final outFile = File(outPath);
    await outFile.writeAsBytes(encoded, flush: true);
    return outPath;
  }

  static String _stamp(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  /// 导出「诊断包」:数据库 + 应用日志 + 设置项(不含密钥与媒体文件),
  /// 用于问题复现排查(如「掌柜不回复」「日志为空」等)。
  Future<String> exportDiagnosticZip() async {
    final archive = Archive();

    // 1) 数据库(全部业务数据,排除敏感项见 2)
    final dbPath = p.join(await getDatabasesPath(), 'student_workbench.db');
    final dbFile = File(dbPath);
    if (await dbFile.exists()) {
      final bytes = await dbFile.readAsBytes();
      archive.addFile(ArchiveFile('student_workbench.db', bytes.length, bytes));
    }

    // 2) 应用日志(关键埋点,问题复现核心)
    final logText = await AppLog.instance.exportText();
    if (logText.isNotEmpty) {
      final logBytes = utf8.encode(logText);
      archive.addFile(ArchiveFile('app_log.txt', logBytes.length, logBytes));
    }

    // 3) 设置项(排除 api_ 前缀密钥)
    final prefs = await SharedPreferences.getInstance();
    final map = <String, Object?>{};
    for (final key in prefs.getKeys()) {
      if (key.startsWith('api_')) continue;
      map[key] = prefs.get(key);
    }
    final prefsJson = const JsonEncoder.withIndent('  ').convert(map);
    final prefsBytes = utf8.encode(prefsJson);
    archive.addFile(
        ArchiveFile('preferences.json', prefsBytes.length, prefsBytes));

    final encoded = ZipEncoder().encode(archive)!;

    Directory outDir;
    try {
      outDir = await getApplicationDocumentsDirectory();
      final ext = await getExternalStorageDirectory();
      if (ext != null) outDir = ext;
    } catch (_) {
      outDir = await getApplicationDocumentsDirectory();
    }
    final diagDir = Directory(p.join(outDir.path, 'ChronosBackups'));
    if (!await diagDir.exists()) await diagDir.create(recursive: true);
    final outPath =
        p.join(diagDir.path, 'chronos-diagnostic-${_stamp(DateTime.now())}.zip');
    await File(outPath).writeAsBytes(encoded, flush: true);
    return outPath;
  }

  /// 从 zip 备份恢复:用备份内的 student_workbench.db 覆盖当前数据库,
  /// 并把 preferences.json 里的设置项写回(api_ 前缀密钥不受影响,备份里本就没有)。
  ///
  /// 覆盖前会先把当前数据库另存一份 pre-restore 备份(尽力而为),便于回滚。
  /// 恢复后数据库连接已重开,调用方应刷新页面数据。
  ///
  /// 抛出异常表示 zip 非法或不含数据库文件。
  Future<RestoreResult> restoreFromZip(String zipPath) async {
    final bytes = await File(zipPath).readAsBytes();
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('无法解析备份文件(不是有效的 zip)');
    }

    ArchiveFile? dbEntry;
    ArchiveFile? prefsEntry;
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final name = p.basename(f.name);
      if (name == 'student_workbench.db') dbEntry = f;
      if (name == 'preferences.json') prefsEntry = f;
    }
    if (dbEntry == null) {
      throw const FormatException('备份文件里没有数据库,无法恢复');
    }

    // 1) 先释放当前数据库连接,再覆盖 .db 文件(否则文件被占用)。
    final dbPath = await DbHelper.instance.databasePath();
    await DbHelper.instance.close();

    // 覆盖前把当前库另存 pre-restore(尽力而为,失败不阻断)。
    try {
      final cur = File(dbPath);
      if (await cur.exists()) {
        await cur.copy('$dbPath.pre-restore');
      }
    } catch (_) {}

    final dbBytes = dbEntry.content as List<int>;
    // 恢复前校验备份库版本:备份来自**更新**版本的 App 时禁止降级恢复
    // (旧 App 打开新库会因版本过高抛错,数据库打不开、页面连锁失败)。
    final probePath = '$dbPath.restore-probe';
    await File(probePath).writeAsBytes(dbBytes, flush: true);
    int? backupVersion;
    try {
      final probe = await openDatabase(probePath, readOnly: true);
      backupVersion = await probe.getVersion();
      await probe.close();
    } catch (_) {
      // 备份库损坏/非 sqlite:交给后续 openDatabase 自然失败,这里不阻断。
    } finally {
      final f = File(probePath);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    if (backupVersion != null && backupVersion > DbHelper.dbVersion) {
      throw FormatException(
          '备份来自更新的版本(数据库 v$backupVersion,当前 App 为 v${DbHelper.dbVersion}),'
          '请先升级 App 再恢复');
    }
    await File(dbPath).writeAsBytes(dbBytes, flush: true);

    // 2) 恢复设置项(跳过 api_ 前缀,避免覆盖本机已填密钥)。
    var prefsCount = 0;
    if (prefsEntry != null) {
      try {
        final jsonStr = utf8.decode(prefsEntry.content as List<int>);
        final decoded = jsonDecode(jsonStr);
        if (decoded is Map<String, dynamic>) {
          final prefs = await SharedPreferences.getInstance();
          for (final entry in decoded.entries) {
            final key = entry.key;
            if (key.startsWith('api_')) continue;
            final v = entry.value;
            if (v is bool) {
              await prefs.setBool(key, v);
            } else if (v is int) {
              await prefs.setInt(key, v);
            } else if (v is double) {
              await prefs.setDouble(key, v);
            } else if (v is String) {
              await prefs.setString(key, v);
            } else if (v is List) {
              await prefs.setStringList(
                  key, v.map((e) => e.toString()).toList());
            } else {
              continue;
            }
            prefsCount++;
          }
        }
      } catch (_) {
        // 设置项恢复失败不影响数据库恢复结果
      }
    }

    // 3) 媒体文件(头像 / 掌柜头像 / 背景图 / 聊天图片)写回文档目录,
    //    保证 prefs 里的图片路径与聊天消息里的图片路径恢复后能找到对应文件。
    try {
      final docs = await getApplicationDocumentsDirectory();
      for (final f in archive.files) {
        if (!f.isFile) continue;
        if (!f.name.startsWith('media/')) continue;
        final bytes = f.content as List<int>;
        if (f.name.startsWith('media/chat_imgs/')) {
          final dir = Directory(p.join(docs.path, 'chat_imgs'));
          if (!await dir.exists()) await dir.create(recursive: true);
          await File(p.join(dir.path, p.basename(f.name)))
              .writeAsBytes(bytes, flush: true);
        } else {
          await File(p.join(docs.path, p.basename(f.name)))
              .writeAsBytes(bytes, flush: true);
        }
      }
    } catch (_) {
      // 媒体恢复失败不阻断(数据库与设置已恢复)。
    }

    // 4) 触发数据库重开(应用新版本号 / 必要时迁移)。
    await DbHelper.instance.database;

    return RestoreResult(dbRestored: true, prefsRestored: prefsCount);
  }
}
