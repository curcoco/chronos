import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

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
}
