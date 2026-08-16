import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../services/eleven_service.dart';
import '../services/llm_service.dart';
import '../services/memory_service.dart';
import '../services/note_service.dart';
import '../services/task_service.dart';
import '../services/weather_service.dart';
import '../theme.dart';
import '../utils/dates.dart';
import '../widgets/frosted_snack.dart';
import 'api_settings_page.dart';
import 'memory_page.dart';

/// 零时闲话铺:与 AI 聊天(中转站大模型),AI 回复可语音朗读(elevenlabs)
/// 每日对话当天清空(零点万事清零)。
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  static const String _kDate = 'chat_date';
  static const String _kMessages = 'chat_messages';
  static const String _kPersona = 'chat_persona';

  /// 本地工具(函数调用):模型可查询天气 / 今日任务 / 灵感记录
  static const List<Map<String, dynamic>> _tools = [
    {
      'type': 'function',
      'function': {
        'name': 'get_weather',
        'description': '查询指定城市的当前天气',
        'parameters': {
          'type': 'object',
          'properties': {
            'city': {
              'type': 'string',
              'description': '城市拼音,如 beijing / hangzhou',
            },
          },
          'required': ['city'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_today_tasks',
        'description': '查询今天的学习任务列表',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'get_notes',
        'description': '查询最近的灵感速记记录',
        'parameters': {'type': 'object', 'properties': {}},
      },
    },
  ];

  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// 发送给模型的最大历史条数:仅保留最近 N 条,控制 token 成本与延迟。
  /// (本地仍完整展示当天对话;只裁剪"喂给模型"的上下文。)
  static const int _maxContextMessages = 20;

  List<({String role, String content})> _messages = [];
  String _persona = ApiConfig.defaultPersona;
  bool _sending = false;
  bool _llmOk = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    ElevenService.instance.stop();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString(_kDate);
    final today = todayStr();
    var messages = <({String role, String content})>[];
    if (savedDate == today) {
      final raw = prefs.getString(_kMessages);
      if (raw != null && raw.isNotEmpty) {
        try {
          final list = jsonDecode(raw) as List;
          messages = [
            for (final m in list.cast<Map<String, dynamic>>())
              (role: m['role'] as String, content: m['content'] as String),
          ];
        } catch (_) {
          messages = [];
        }
      }
    }
    // 跨天自动清空(零点万事清零)
    if (savedDate != today) {
      await prefs.remove(_kMessages);
    }
    await prefs.setString(_kDate, today);
    final persona = prefs.getString(_kPersona);
    final llmOk = await LlmService.instance.isConfigured();
    if (!mounted) return;
    setState(() {
      _persona = (persona == null || persona.isEmpty)
          ? ApiConfig.defaultPersona
          : persona;
      _messages = messages;
      _llmOk = llmOk;
    });
  }

  /// 打开 API 配置页,返回后刷新配置状态
  Future<void> _openApiSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ApiSettingsPage()),
    );
    final llmOk = await LlmService.instance.isConfigured();
    if (!mounted) return;
    setState(() => _llmOk = llmOk);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _kMessages,
        jsonEncode([
          for (final m in _messages)
            {'role': m.role, 'content': m.content},
        ]));
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    final llmOk = await LlmService.instance.isConfigured();
    if (!mounted) return;
    if (!llmOk) {
      showFrostedSnack(context, '聊天服务未配置,请先到 系统设置 → API 配置 填写');
      return;
    }
    _ctrl.clear();
    setState(() {
      _messages.add((role: 'user', content: text));
      _sending = true;
    });
    _scrollToBottom();
    try {
      // 注入长期记忆(画像/事实/摘要),让 AI 记住用户
      final memory = await MemoryService.instance.promptSection();
      final reply = await LlmService.instance.chat(
        history: _recentContext(),
        persona: _persona + memory,
        tools: _tools,
        onTool: _execTool,
      );
      if (!mounted) return;
      setState(() {
        _messages.add((role: 'assistant', content: reply));
        _sending = false;
      });
      await _save();
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      showFrostedSnack(context, 'AI 请求失败,请检查网络或配置');
    }
  }

  /// 仅取最近 [_maxContextMessages] 条对话作为模型上下文,避免长对话 token 膨胀。
  List<({String role, String content})> _recentContext() {
    if (_messages.length <= _maxContextMessages) return List.of(_messages);
    return _messages.sublist(_messages.length - _maxContextMessages);
  }

  /// 本地工具执行:模型调用工具时在这里查询本地数据,返回文本结果
  Future<String> _execTool(String name, Map<String, dynamic> args) async {
    switch (name) {
      case 'get_weather':
        final city = (args['city'] as String?)?.trim() ?? '';
        if (city.isEmpty) return '缺少城市参数';
        if (!await WeatherService.instance.isConfigured()) {
          return '天气服务未配置(API 配置页未填心知天气 Key)';
        }
        try {
          final w = await WeatherService.instance.fetchCity(city);
          return '${w.city} 当前 ${w.text},${w.temp}℃';
        } catch (e) {
          return '天气查询失败:$e';
        }
      case 'get_today_tasks':
        final tasks = await TaskService().todayTasks(todayStr());
        if (tasks.isEmpty) return '今天没有任务';
        return tasks
            .map((t) =>
                '${t.done ? "[已完成]" : "[待完成]"} ${t.title}(${t.category})')
            .join('\n');
      case 'get_notes':
        final notes = await NoteService().notes();
        if (notes.isEmpty) return '还没有灵感记录';
        return notes.take(5).map((n) => n.content).join('\n');
      default:
        return '未知工具:$name';
    }
  }

  Future<void> _speak(String content) async {
    final ok = await ElevenService.instance.isConfigured();
    if (!mounted) return;
    if (!ok) {
      showFrostedSnack(context, '语音服务未配置,请先到 系统设置 → API 配置 填写');
      return;
    }
    try {
      await ElevenService.instance.speak(content);
    } catch (_) {
      if (!mounted) return;
      showFrostedSnack(context, '语音播放失败,请检查语音配置或额度');
    }
  }

  Future<void> _editPersona() async {
    final controller = TextEditingController(text: _persona);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('掌柜人设'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(hintText: '设定掌柜的性格与说话风格'),
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPersona, result);
    if (!mounted) return;
    setState(() => _persona = result);
    showFrostedSnack(context, '人设已更新');
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('零时闲话铺'),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MemoryPage()),
              );
            },
            icon: const Icon(Icons.psychology_rounded, size: 20),
            tooltip: 'AI 长期记忆',
          ),
          IconButton(
            onPressed: _editPersona,
            icon: const Icon(Icons.tune_rounded, size: 20),
            tooltip: '掌柜人设',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (!_llmOk)
              InkWell(
                onTap: _openApiSettings,
                child: Container(
                  width: double.infinity,
                  color: const Color(0xFFFFF3E0),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: const Text(
                    '聊天服务未配置,点击前往 API 配置',
                    style: TextStyle(
                        fontSize: 11, color: Color(0xFFE65100)),
                  ),
                ),
              ),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                children: [
                  _bubble(
                    content:
                        '欢迎光临零时闲话铺,铺子里的我见多识广,专业在线,玩笑不断。'
                        '本店铁律:午夜零点准时打烊,闲谈限时寄存,零点万事清零。',
                    mine: false,
                  ),
                  const SizedBox(height: 10),
                  for (final m in _messages) ...[
                    _bubble(
                      content: m.content,
                      mine: m.role == 'user',
                      onSpeak: m.role == 'assistant'
                          ? () => _speak(m.content)
                          : null,
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (_sending)
                    Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('掌柜正在想…',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textSub)),
                      ),
                    ),
                ],
              ),
            ),
            // 输入区
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              decoration: BoxDecoration(
                color: AppColors.card,
                border: Border(
                  top: BorderSide(color: AppColors.line),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: '和掌柜聊聊…',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: AppColors.primary,
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: _send,
                      child: const SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(Icons.send_rounded,
                            size: 22, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble({
    required String content,
    required bool mine,
    VoidCallback? onSpeak,
  }) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: mine ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          border: mine ? null : Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              content,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: mine ? Colors.white : AppColors.textMain,
              ),
            ),
            if (onSpeak != null) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  InkWell(
                    onTap: onSpeak,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: EdgeInsets.all(2),
                      child: Icon(Icons.volume_up_rounded,
                          size: 16, color: AppColors.textSub),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
