import 'package:flutter/material.dart';

import '../data/daily_content.dart';
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
  String _greeting = '嗨,同学';
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
    final greeting = await SettingsService.instance.greeting();
    if (!mounted) return;
    setState(() {
      _greeting = greeting;
      _quote = DailyContent.quoteFor(date);
      _dateLabel = monthDayLabel(now);
      _week = weekdayLabel(now);
    });
  }

  Future<void> _editGreeting() async {
    final controller = TextEditingController(text: _greeting);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改问候语'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(hintText: '输入你想看到的问候语'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    await SettingsService.instance.setGreeting(result);
    if (!mounted) return;
    setState(() => _greeting = result);
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
                    gradient: const LinearGradient(
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
                const Text(
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
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textMain,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _week,
                  style: const TextStyle(
                    fontSize: 17,
                    color: AppColors.textSub,
                  ),
                ),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _greeting,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textMain,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: _editGreeting,
                      icon: const Icon(
                        Icons.edit_rounded,
                        size: 20,
                        color: AppColors.textSub,
                      ),
                      tooltip: '自定义问候语',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '「$_quote」',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontStyle: FontStyle.italic,
                    color: AppColors.textSub,
                    height: 1.5,
                  ),
                ),
                const Spacer(flex: 3),
                FilledButton(
                  onPressed: () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const MainShell()),
                    );
                  },
                  child: const Text('开始今天 →'),
                ),
                const SizedBox(height: 12),
                // 「快速记一笔」:一键直达灵感速记输入,不进首页
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const QuickNotePage(),
                          fullscreenDialog: true,
                        ),
                      );
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
