/// 闲话铺工具定义(给模型看的 JSON schema 与执行器)。
///
/// 设计(工具注册表架构):
/// - [definition] 是 OpenAI 兼容的工具定义(名称/描述/参数 schema);
/// - [execute] 是本地执行器,返回文本结果回传给模型;
/// - 写操作(记账/加任务等)通过 [requireConfirm] 标记,由聊天页在调用前
///   弹用户确认;确认类工具的执行器只返回「待确认意图」文本,
///   确认后由注册表调用真正的执行逻辑。
class ChatTool {
  final Map<String, dynamic> definition;
  final String name;
  final bool requireConfirm;

  /// 执行器:返回结果文本。
  final Future<String> Function(Map<String, dynamic> args) execute;

  /// 用户确认后的真正执行(仅写操作需要;读操作与 execute 相同)。
  final Future<String> Function(Map<String, dynamic> args)? executeConfirmed;

  const ChatTool({
    required this.definition,
    required this.name,
    this.requireConfirm = false,
    required this.execute,
    this.executeConfirmed,
  });

  /// 工具名(从 definition 提取的快捷方式)。
  String get displayName => (definition['function'] as Map)['name'] as String? ?? name;
}
