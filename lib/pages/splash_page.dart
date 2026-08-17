import 'package:flutter/material.dart';

import '../data/daily_content.dart';
import '../routes.dart';
import '../services/settings_service.dart';
import '../theme.dart';
import '../utils/dates.dart';
import 'main_shell.dart';
import 'quick_note_page.dart';

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
                      colors: [AppColors.primaryLight, AppColors.primary],
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
                  child: const Icon(
                    Icons.school_rounded,
                    size: 46,
                    color: Colors.white,
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
                const SizedBox(height: 12),
                // 「快速记一笔」:一键直达灵感速记输入,不进首页
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      AppRoutes.push(context, const QuickNotePage(),
                          dialog: true);
                    },
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: AppColors.primaryDark,
                      side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.5),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.edit_note_rounded, size: 20),
                    label: const Text('快速记一笔'),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
