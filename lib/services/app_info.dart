import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

/// 更新检查结果
class UpdateStatus {
  /// 远程检查是否成功(联网可达)
  final bool reachable;
  /// 是否有可用更新
  final bool updateAvailable;
  /// 最新版本号(远程返回;离线时为内置兜底值)
  final String latestVersion;
  /// 更新说明(远程 JSON 的 note 字段)
  final String? note;

  const UpdateStatus({
    required this.reachable,
    required this.updateAvailable,
    required this.latestVersion,
    this.note,
  });
}

/// 应用信息:版本号读取与更新检查。
/// 本项目唯一联网点:更新检查(其余功能全部零网络)。
class AppInfo {
  AppInfo._();

  /// 离线兜底用的「最新版本」参照,每次发版时与 pubspec.yaml 的 version 同步更新。
  static const String latestVersion = '1.2.0';

  /// 更新检查地址:托管一个 HTTPS 可达的 latest.json,内容形如
  /// {"version":"1.2.0","note":"…","apk":"https://…/chronos-1.2.0.apk"}
  /// 真实地址:腾讯云 COS(国内直连,APK 在 releases/ 目录,见 D:\dev\student_workbench\releases\)。
  /// GitHub 仓库 curcoco/chronos 仅作源码备份/镜像,不再作为更新源。
  static const String updateCheckUrl =
      'https://chronos-update-1456265383.cos.ap-guangzhou.myqcloud.com/latest.json';

  /// 从打包进 APK 的 pubspec.yaml 读取安装版本(如 1.2.0+3 → 1.2.0)
  static Future<String> installedVersion() async {
    try {
      final raw = await rootBundle.loadString('pubspec.yaml');
      final match =
          RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(raw);
      return (match?.group(1) ?? '').split('+').first;
    } catch (_) {
      return '';
    }
  }

  /// 联网检查更新:成功返回远程结果;失败(离线/超时/格式错误)返回内置兜底结果。
  /// 旧版本因此能发现比自己新的版本。
  static Future<UpdateStatus> checkUpdate(String installed) async {
    final remote = await _fetchRemoteLatest();
    if (remote != null) {
      return UpdateStatus(
        reachable: true,
        updateAvailable:
            installed.isNotEmpty && _compare(installed, remote.version) < 0,
        latestVersion: remote.version,
        note: remote.note,
      );
    }
    return UpdateStatus(
      reachable: false,
      updateAvailable:
          installed.isNotEmpty && _compare(installed, latestVersion) < 0,
      latestVersion: latestVersion,
    );
  }

  /// 拉取远程最新版本信息;任何异常返回 null
  static Future<({String version, String? note})?> _fetchRemoteLatest() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client
          .getUrl(Uri.parse(updateCheckUrl))
          .timeout(const Duration(seconds: 6));
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 6));
      if (res.statusCode != HttpStatus.ok) return null;
      final body = await res.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      if (data is! Map<String, dynamic>) return null;
      final version = data['version'];
      if (version is! String || version.isEmpty) return null;
      final note = data['note'];
      return (version: version, note: note is String ? note : null);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 语义化版本比较 '1.2.0' vs '1.1.0' → 1(大于),返回 -1/0/1
  static int _compare(String a, String b) {
    final pa = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final pb = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}
