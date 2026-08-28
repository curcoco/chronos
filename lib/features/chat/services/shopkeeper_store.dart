import 'package:shared_preferences/shared_preferences.dart';

import 'package:chronos/core/config/api_config.dart';

/// 掌柜资料(闲话铺角色设定):名称 / 头像 / 人设。
/// 全部存 SharedPreferences(纯本地,不入源码)。
/// 「掌柜设置」页与聊天页共用本 store,避免散落读写。
class ShopkeeperStore {
  ShopkeeperStore._();
  static final ShopkeeperStore instance = ShopkeeperStore._();

  /// 掌柜名称(空 = 未设置)。
  static const String kName = 'chat_shopkeeper_name';

  /// 掌柜头像图片本地路径(空 = 未设置)。
  static const String kAvatar = 'chat_shopkeeper_avatar';

  /// 掌柜人设(与历史版本 key 保持一致,旧数据直接兼容)。
  static const String kPersona = 'chat_persona';

  /// 喂给模型的对话上下文条数(超过预算的部分自动压缩成摘要)。
  static const String kContextSize = 'chat_context_size';

  /// 上下文条数范围(条)。上限 800:实际发送还会受 token 预算自动裁剪,
  /// 不会撑爆模型上下文窗口。
  static const int contextMin = 10;
  static const int contextMax = 800;
  static const int contextDefault = 80;

  Future<String> name() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kName) ?? '';
  }

  Future<void> setName(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kName, value.trim());
  }

  Future<String> avatarPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kAvatar) ?? '';
  }

  Future<void> setAvatarPath(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kAvatar, value.trim());
  }

  Future<String> persona() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(kPersona);
    return (v == null || v.trim().isEmpty) ? ApiConfig.defaultPersona : v;
  }

  Future<void> setPersona(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPersona, value.trim());
  }

  /// 对话上下文条数(喂给模型的最大历史消息数;默认 80,可调 10~800,
  /// 实际发送还受 token 预算自动裁剪)。
  Future<int> contextSize() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt(kContextSize) ?? contextDefault)
        .clamp(contextMin, contextMax);
  }

  Future<void> setContextSize(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        kContextSize, value.clamp(contextMin, contextMax));
  }
}
