import 'package:flutter/material.dart';

import 'package:chronos/core/data/daily_content.dart';
import 'package:chronos/core/data/content_updater.dart';
import 'package:chronos/routes.dart';
import 'package:chronos/core/services/settings_service.dart';
import 'package:chronos/core/theme.dart';
import 'package:chronos/core/utils/dates.dart';
import 'package:chronos/features/chat/pages/chat_page.dart';
import 'package:chronos/features/ledger/pages/ledger_page.dart';
import 'package:chronos/features/shell/pages/main_shell.dart';
import 'package:chronos/features/notes/pages/quick_note_page.dart';

/// 启动页:日期 + 星期 + 问候语(可自定义)+ 随机金句 + 开始今天
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  String _greetingText = '';
  String _quote = '';
  String _dateLabel = '';
  String _week = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final now = DateTime.now();
    final date = todayStr();
    final nickname = await SettingsService.instance.nickname();
    final isSet = await SettingsService.instance.isNicknameSet();
    if (!mounted) return;
    setState(() {
      // 只有用户主动设定昵称才显示;否则显示「今天想做点什么?」
      _greetingText =
          isSet ? '$nickname,今天也请多指教' : '今天想做点什么?';
      _quote = DailyContent.quoteFor(date);
      _dateLabel = monthDayLabel(now);
      _week = weekdayLabel(now);
    });
    // 后台热更离线内容池(金句/词库等,小更新不换包);失败静默用内置。
    ContentUpdater.instance.update();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFD6EDFF), Color(0xFFF1F8FE), Colors.white],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const Spacer(flex: 2),
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.primaryLight, AppColors.primarySoft],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.school_rounded,
                    size: 46,
                    color: AppColors.onPrimarySoft,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Chronos',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryDark,
                  ),
                ),
                const Spacer(flex: 2),
                Text(
                  _dateLabel,
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textMain,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _week,
                  style: TextStyle(
                    fontSize: 17,
                    color: AppColors.textSub,
                  ),
                ),
                const SizedBox(height: 30),
                // 分层问候:时段词(大) + 昵称/引导(小) + 金句
                Text(
                  timeGreeting(DateTime.now()),
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textMain,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _greetingText,
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.textSub,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '「$_quote」',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: AppColors.textSub,
                    height: 1.5,
                  ),
                ),
                const Spacer(flex: 3),
                FilledButton(
                  onPressed: () {
                    AppRoutes.pushReplacement(context, const MainShell());
                  },
                  child: const Text('开始今天 →'),
                ),
                const SizedBox(height: 16),
                // 四个快捷入口:灵感速记 / 闲话铺 / 记账(返回后进入首页)。
                // 首页由「开始今天」进入;速记/闲话铺/记账返回后均落到首页。
                Row(
                  children: [
                    Expanded(
                      child: _entryButton(
                        icon: Icons.edit_note_rounded,
                        label: '灵感速记',
                        onTap: () async {
                          await AppRoutes.push(context, const QuickNotePage(),
                              dialog: true);
                          if (!context.mounted) return;
                          AppRoutes.pushReplacement(context, const MainShell());
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _entryButton(
                        icon: Icons.smart_toy_rounded,
                        label: '闲话铺',
                        onTap: () async {
                          await AppRoutes.push(context, const ChatPage());
                          if (!context.mounted) return;
                          AppRoutes.pushReplacement(context, const MainShell());
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _entryButton(
                        icon: Icons.account_balance_wallet_rounded,
                        label: '记账',
                        onTap: () async {
                          await AppRoutes.push(context, const LedgerPage());
                          if (!context.mounted) return;
                          AppRoutes.pushReplacement(context, const MainShell());
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 启动页小入口按钮(图标 + 文字,竖排)。
  Widget _entryButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 64),
        padding: const EdgeInsets.symmetric(vertical: 8),
        foregroundColor: AppColors.primaryDark,
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.5)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
