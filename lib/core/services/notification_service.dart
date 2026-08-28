import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 本地通知 + 后台生成前台服务控制。
/// - 前台服务(Android 原生):app 退后台且掌柜生成时保活进程,SSE 不被系统冻结;
/// - 本地通知:生成完成弹「掌柜回复了」(点击回 app)。
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const MethodChannel _chan = MethodChannel('app/chat_service');
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _init = false;

  static const String _doneChannelId = 'chat_done';
  static const String _doneChannelName = '掌柜回复完成';
  static const int _doneNotificationId = 1002;

  Future<void> init() async {
    if (_init) return;
    _init = true;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      settings: const InitializationSettings(android: android),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(const AndroidNotificationChannel(
      _doneChannelId,
      _doneChannelName,
      importance: Importance.high,
    ));
  }

  /// Android 13+ 运行时申请通知权限;低版本直接返回 true。
  Future<bool> requestNotificationPermission() async {
    final impl = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (impl == null) return true;
    final granted = await impl.requestNotificationsPermission();
    return granted ?? false;
  }

  /// 启动前台服务(后台保活:显示「掌柜正在回复…」)。
  Future<void> startChatService() async {
    try {
      await _chan.invokeMethod('startChatService');
    } catch (_) {}
  }

  /// 停止前台服务。
  Future<void> stopChatService() async {
    try {
      await _chan.invokeMethod('stopChatService');
    } catch (_) {}
  }

  /// 生成完成通知:内容预览,点击回到 app。
  Future<void> notifyChatDone(String content) async {
    final preview = content.trim();
    await _plugin.show(
      id: _doneNotificationId,
      title: '掌柜回复了',
      body: preview.isEmpty ? '掌柜已回复,回来看看吧' : preview,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _doneChannelId,
          _doneChannelName,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
    );
  }
}
