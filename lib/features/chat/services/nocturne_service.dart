import 'package:mcp_client/mcp_client.dart';

import 'package:student_workbench/core/services/app_log.dart';
import 'package:student_workbench/core/services/key_store.dart';

/// 外置记忆服务(用户自配,应用只提供接口)。
///
/// 通过 MCP(Streamable HTTP)连接用户自部署的 Nocturne Memory Core
/// (Ombre Brain 二改项目)。用户需在「系统设置 → API 配置 → 外置记忆」填写
/// 服务地址与 Bearer token。
///
/// 设计:未配置 / 连接失败 / 调用失败时全部静默降级,不影响本地记忆与聊天。
class NocturneService {
  NocturneService._();
  static final NocturneService instance = NocturneService._();

  static const String _kUrl = 'nocturne_url';
  static const String _kToken = 'nocturne_token';

  /// 外置记忆是否已配置(URL 与 token 均非空)。
  static Future<bool> isConfigured() async {
    final s = KeyStore.instance;
    return (await s.get(_kUrl)).isNotEmpty &&
        (await s.get(_kToken)).isNotEmpty;
  }

  static Future<String> configuredUrl() async =>
      KeyStore.instance.get(_kUrl);
  static Future<String> configuredToken() async =>
      KeyStore.instance.get(_kToken);

  /// 建立一次短连接并执行 [action],用完即断。
  /// 任何异常(未配置/网络/服务端)都返回 null,由调用方静默降级。
  Future<T?> _withClient<T>(
    Future<T> Function(Client client) action, {
    String? what,
  }) async {
    if (!await isConfigured()) return null;
    final url = await configuredUrl();
    final token = await configuredToken();
    try {
      final config = McpClient.simpleConfig(
        name: 'Chronos',
        version: '1.0.0',
        enableDebugLogging: false,
      );
      final result = await McpClient.createAndConnect(
        config: config,
        transportConfig: TransportConfig.streamableHttp(
          baseUrl: url,
          headers: {'Authorization': 'Bearer $token'},
          timeout: const Duration(seconds: 15),
          maxConcurrentRequests: 5,
          useHttp2: false,
        ),
      );
      return await result.fold(
        (client) async {
          try {
            return await action(client);
          } finally {
            client.disconnect();
          }
        },
        (error) {
          AppLog.instance.e('外置记忆连接失败($what):$error');
          return null;
        },
      );
    } catch (e) {
      AppLog.instance.e('外置记忆调用异常($what):$e');
      return null;
    }
  }

  /// 写入记忆(Nocturne 的 hold 工具)。
  /// [content] 记忆内容;成功返回 true;未配置/失败返回 false。
  Future<bool> hold(String content) async {
    final ok = await _withClient<bool>(
      (client) async {
        final res = await client.callTool('hold', {'content': content});
        return res.isError == false;
      },
      what: 'hold',
    );
    return ok ?? false;
  }

  /// 检索记忆(Nocturne 的 breath 工具)。
  /// [query] 检索词;成功返回工具结果文本;未配置/失败返回 null。
  Future<String?> breath(String query) async {
    return _withClient<String>(
      (client) async {
        final res = await client.callTool('breath', {'query': query});
        final parts = res.content
            .map((c) => switch (c) {
                  TextContent(:final text) => text,
                  _ => '',
                })
            .where((t) => t.isNotEmpty);
        return parts.join('\n');
      },
      what: 'breath',
    );
  }

  /// 外置记忆是否可用(配置 + 连通性探测)。失败不抛异常。
  Future<bool> probe() async {
    return await _withClient<bool>(
          (client) async {
            await client.listTools();
            return true;
          },
          what: 'probe',
        ) ??
        false;
  }
}
