import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'package:student_workbench/core/services/db_helper.dart';

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

    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final outPath = p.join(backupDir.path, 'chronos-backup-$stamp.zip');
    final outFile = File(outPath);
    await outFile.writeAsBytes(encoded, flush: true);
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

    // 3) 触发数据库重开(应用新版本号 / 必要时迁移)。
    await DbHelper.instance.database;

    return RestoreResult(dbRestored: true, prefsRestored: prefsCount);
  }
}
