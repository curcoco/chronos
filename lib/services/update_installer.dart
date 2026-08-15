import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// APK 下载与安装(唯一联网点:更新检查 / 下载)。
/// 下载走 Dart HttpClient(带进度),安装走原生 method channel(FileProvider + 系统安装器)。
class UpdateInstaller {
  UpdateInstaller._();

  static const MethodChannel _channel = MethodChannel('app/install');

  /// 下载 APK 到应用缓存目录,返回本地文件路径。
  /// [onProgress] 回调下载进度 0.0 ~ 1.0;失败抛 HttpException(带具体原因,便于排查)。
  static Future<String> downloadApk(
    String url, {
    required void Function(double progress) onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/chronos-update.apk');

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 10));
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != HttpStatus.ok) {
        throw HttpException('服务器返回错误(HTTP ${res.statusCode})');
      }
      final total = res.contentLength;
      final sink = file.openWrite();
      var received = 0;
      try {
        // 每个数据块 30 秒内必须到达,防止网络卡死
        await for (final chunk in res.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress(received / total);
        }
        await sink.flush();
      } on TimeoutException {
        throw HttpException('下载超时,网络中断或服务器响应过慢');
      } finally {
        await sink.close();
      }
      if (!file.existsSync() || file.lengthSync() == 0) {
        throw HttpException('下载文件为空');
      }
      if (total > 0 && received < total) {
        throw HttpException('下载不完整($received/$total 字节),请重试');
      }
      onProgress(1);
      return file.path;
    } on HttpException {
      rethrow;
    } on TimeoutException {
      throw HttpException('连接超时,请检查网络');
    } catch (e) {
      throw HttpException('下载中断(${e.runtimeType})');
    } finally {
      client.close(force: true);
    }
  }

  /// 调起系统安装器(ACTION_VIEW + FileProvider content URI)。
  /// Android 8+ 首次会弹「安装未知应用」授权,由系统处理。
  static Future<void> installApk(String path) async {
    await _channel.invokeMethod('installApk', {'path': path});
  }
}
