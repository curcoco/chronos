/// 对话上下文的「条数 + token」双约束裁剪。
///
/// 把最近 N 条消息喂给模型时,不能只按条数截(用户可调到 800 条,但
/// 800 条长消息会超出模型上下文窗口导致请求失败),也不能只按 token 截。
/// 这里从尾部向前取尽量多的消息,同时满足:
/// - 条数 ≤ [maxCount](用户在掌柜设置里选的);
/// - 累计 token ≤ 模型档位预算(防止撑爆模型上下文,更早的部分交给摘要压缩)。
///
/// 模型档位由「API 配置 → 聊天模型 → 支持 1M 上下文」勾选决定:
/// - 支持 1M:预算 100 万 token,预警 80 万;
/// - 默认档:预算 20 万 token,预警 16.7 万。
class ContextBudget {
  ContextBudget._();

  /// 支持 1M 上下文的模型:预算与预警线(token)。
  static const int budgetFor1m = 1000000;
  static const int warnFor1m = 800000;

  /// 默认档模型:预算与预警线(token)。
  static const int budgetDefault = 200000;
  static const int warnDefault = 167000;

  /// 按模型档位取原始历史上下文预算。
  static int budgetFor(bool supports1m) =>
      supports1m ? budgetFor1m : budgetDefault;

  /// 按模型档位取预警线:上下文超过该值时提醒用户压缩/新开会话。
  static int warnThresholdFor(bool supports1m) =>
      supports1m ? warnFor1m : warnDefault;

  /// 粗估一条消息的 token 数:中文约 1 token/1.2 字符,英文约 1 token/4 字符,
  /// 统一按 1.2 字符/token 保守估算,另加角色/结构开销。用于防超限,不需精确。
  static int estimateTokens(String content) {
    if (content.isEmpty) return 4;
    return (content.length / 1.2).ceil() + 4;
  }

  /// 从 [messages](旧→新)尾部向前取尽量多的消息,返回应保留的条数。
  /// 约束:条数 ≤ [maxCount];累计 token ≤ [budget]。
  /// 至少保留最后 1 条(即使它单条就超预算),避免上下文为空。
  /// [reasoningContent] 参与记录类型但不计 token(思维链不占上下文预算)。
  static int keepCount(
    List<({String role, String content, String? reasoningContent})> messages, {
    required int maxCount,
    required int budget,
  }) {
    if (messages.isEmpty) return 0;
    var tokens = 0;
    var count = 0;
    for (var i = messages.length - 1; i >= 0; i--) {
      final t = estimateTokens(messages[i].content);
      final exceeded = count >= maxCount || (count > 0 && tokens + t > budget);
      if (exceeded) break;
      tokens += t;
      count++;
    }
    return count;
  }

  /// 累计估算一组消息的 token 数(旧→新)。
  static int totalTokens(
          List<({String role, String content, String? reasoningContent})>
              messages) =>
      messages.fold(0, (sum, m) => sum + estimateTokens(m.content));
}
