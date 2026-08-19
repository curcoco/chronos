import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 轻量应用日志(P4 可观测性)。
///
/// 内存环形缓冲(最近 [maxLines] 条)+ 定期/主动 flush 到应用文档目录
/// `app_log.txt`(UTF-8,新行追加在头部)。关键操作与异常通过
/// [AppLog.i]/[AppLog.e] 记录;备份导出时日志文件一并打包进 zip,
/// 便于真机问题复现时带回现场。日志不含密钥(调用方自行避免写入敏感信息)。
class AppLog {
  AppLog._();
  static final AppLog instance = AppLog._();

  static const int maxLines = 500;

  final List<String> _buffer = [];
  Timer? _flushTimer;

  /// 启动时初始化(惰性启动 flush 定时器)。
  void init() {
    _flushTimer ??= Timer.periodic(const Duration(seconds: 15), (_) => flush());
  }

  /// 记录一条普通日志(如用户操作)。
  void i(String message) => _append('INFO', message);

  /// 记录一条异常日志(如网络/保存失败)。
  void e(String message) => _append('ERROR', message);

  void _append(String level, String message) {
    final line =
        '[${DateTime.now().toIso8601String()}] [$level] $message';
    _buffer.add(line);
    if (_buffer.length > maxLines) {
      _buffer.removeRange(0, _buffer.length - maxLines);
    }
  }

  /// 当前缓冲内容(新→旧)。
  List<String> lines() => List.of(_buffer.reversed);

  /// 日志文件路径。
  Future<String> logFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/app_log.txt';
  }  /// 把缓冲写回日志文件(新日志追加在文件头部,保持"最新在上")。
  Future<void> flush() async {
    if (_buffer.isEmpty) return;
    final path = await logFilePath();
    final file = File(path);
    final existing = await file.exists() ? await file.readAsString() : '';
    final head = '${_buffer.join('\n')}\n';
    // 文件总长度限制(约 256KB),超长截断尾部(旧日志)。
    const maxBytes = 256 * 1024;
    var content = head + existing;
    final bytes = utf8.encode(content);
    if (bytes.length > maxBytes) {
      content = utf8.decode(bytes.sublist(bytes.length - maxBytes), allowMalformed: true);
    }
    await file.writeAsString(content, flush: true);
    _buffer.clear();
  }

  /// 立即 flush 并返回日志文本(供备份打包)。
  Future<String> exportText() async {
    await flush();
    final path = await logFilePath();
    final file = File(path);
    return await file.exists() ? await file.readAsString() : '';
  }
}
