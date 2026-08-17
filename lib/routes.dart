import 'package:flutter/material.dart';

/// 全局路由统一入口。
///
/// 全 App 的页面跳转一律走这里(不要再散落 `Navigator.push(MaterialPageRoute...)`),
/// 便于将来切换 go_router 或统一跳转行为(动画、深链)时只改一处。
class AppRoutes {
  AppRoutes._();

  /// 推入新页面,返回页面 pop 时的结果(可 await)。
  /// [dialog] 为 true 时以全屏对话框形式打开(如灵感速记)。
  static Future<T?> push<T>(
    BuildContext context,
    Widget page, {
    bool dialog = false,
  }) {
    return Navigator.of(context).push<T>(
      MaterialPageRoute<T>(
        builder: (_) => page,
        fullscreenDialog: dialog,
      ),
    );
  }

  /// 用新页面替换当前页面(不保留返回栈)。
  static Future<T?> pushReplacement<T>(
    BuildContext context,
    Widget page,
  ) {
    return Navigator.of(context).pushReplacement<T, void>(
      MaterialPageRoute<T>(builder: (_) => page),
    );
  }

  /// 推入新页面并清空整个导航栈(用于恢复备份后回到启动页)。
  static Future<T?> pushAndRemoveUntil<T>(
    BuildContext context,
    Widget page,
  ) {
    return Navigator.of(context).pushAndRemoveUntil<T>(
      MaterialPageRoute<T>(builder: (_) => page),
      (route) => false,
    );
  }
}
