import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:student_workbench/core/config/api_config.dart';
import 'package:student_workbench/routes.dart';
import 'package:student_workbench/features/chat/pages/session_list_page.dart';
import 'package:student_workbench/features/chat/services/chat_service.dart';
import 'package:student_workbench/features/chat/services/eleven_service.dart';
import 'package:student_workbench/features/chat/services/llm_service.dart';
import 'package:student_workbench/features/chat/services/nocturne_service.dart';
import 'package:student_workbench/features/chat/tools/tool_registry.dart';
import 'package:student_workbench/features/memory/services/memory_service.dart';
import 'package:student_workbench/features/memory/services/memory_extractor.dart';
import 'package:student_workbench/core/theme.dart';
import 'package:student_workbench/core/widgets/frosted_snack.dart';
import 'package:student_workbench/features/settings/pages/api_settings_page.dart';
import 'package:student_workbench/features/memory/pages/memory_page.dart';

/// 零时闲话铺:与 AI 聊天(中转站大模型),AI 回复可语音朗读(elevenlabs)。
/// 会话按窗口长期保存(v12 起取消「零点万事清零」);[initialSessionId] 非空时
/// 直接绑定该会话,为空时进入先选择/新建会话。
class ChatPage extends StatefulWidget {
  final int? initialSessionId;

  const ChatPage({super.key, this.initialSessionId});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  static const String _kPersona = 'chat_persona';

  final ChatService _chatService = ChatService.instance;

  /// 工具由注册表统一管理(见 tool_registry.dart):只读工具 + 需确认的写工具。
  List<Map<String, dynamic>> get _tools => ToolRegistry.definitions();

  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// 发送给模型的最大历史条数:仅保留最近 N 条,控制 token 成本与延迟。
  /// (本地仍完整展示会话;只裁剪"喂给模型"的上下文。)
  static const int _maxContextMessages = 20;

  int? _sessionId; // 当前绑定的会话;null = 尚未选择/初始化
  bool _binding = true; // 正在初始化/选择会话
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

  /// 初始化:绑定会话(优先 initialSessionId → 弹列表选择/新建 → 读取消息)。
  Future<void> _init() async {
    var sessionId = widget.initialSessionId;
    if (sessionId == null) {
      final picked = await Navigator.of(context).push<int>(
        MaterialPageRoute(builder: (_) => const SessionListPage()),
      );
      if (!mounted) return;
      if (picked == null) {
        // 用户直接返回:仍需要一个会话才能聊天,创建一个空的兜底。
        sessionId = await _chatService.createSession();
      } else {
        sessionId = picked;
      }
    }
    final msgs = await _chatService.messages(sessionId);
    final prefs = await SharedPreferences.getInstance();
    final persona = prefs.getString(_kPersona);
    final llmOk = await LlmService.instance.isConfigured();
    if (!mounted) return;
    setState(() {
      _sessionId = sessionId;
      _messages = [
        for (final m in msgs) (role: m.role, content: m.content),
      ];
      _persona = (persona == null || persona.isEmpty)
          ? ApiConfig.defaultPersona
          : persona;
      _llmOk = llmOk;
      _binding = false;
    });
    _scrollToBottom();
  }

  /// 打开 API 配置页,返回后刷新配置状态
  Future<void> _openApiSettings() async {
    await AppRoutes.push(context, const ApiSettingsPage());
    final llmOk = await LlmService.instance.isConfigured();
    if (!mounted) return;
    setState(() => _llmOk = llmOk);
  }

  /// 追加消息并持久化到当前会话
  Future<void> _appendMessage(String role, String content) async {
    final sid = _sessionId;
    if (sid == null) return;
    await _chatService.addMessage(
        sessionId: sid, role: role, content: content);
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending || _sessionId == null) return;
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
    await _appendMessage('user', text);
    _scrollToBottom();
    try {
      // 注入长期记忆(RikkaHub 式相关条目):用最近的用户消息做关键词匹配,
      // 只注入相关记忆,避免记忆多了上下文膨胀。
      final query = _recentUserText();
      var memory = await MemoryService.instance.promptSectionFor(query);
      // 外置记忆(Nocturne MCP,用户自配):可用时额外注入检索结果,失败静默。
      final external =
          await NocturneService.instance.breath(query.isNotEmpty ? query : '最近话题');
      if (external != null && external.isNotEmpty) {
        memory = '$memory\n\n【外置记忆检索】\n$external';
      }
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
      await _appendMessage('assistant', reply);
      _scrollToBottom();
      // 对话后自动提炼记忆(快速模型,后台执行,失败静默不影响聊天)。
      await _autoExtract();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      showFrostedSnack(context, 'AI 请求失败,请检查网络或配置');
    }
  }

  /// 最近用户消息(用于记忆相关度匹配)
  String _recentUserText() {
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].role == 'user') return _messages[i].content;
    }
    return '';
  }

  /// 自动提炼:用最近对话更新长期记忆(本地);若配置了外置记忆(Nocturne),
  /// 提炼出的新条目同时 hold 到外置。失败静默(不打断聊天)。
  Future<void> _autoExtract() async {
    try {
      final result = await MemoryExtractor.instance
          .extractFrom(_messages.sublist(0, _messages.length));
      // 外置记忆同步(用户自配;未配置/失败自动忽略)。
      if (result.added > 0) {
        for (final item in result.addedItems) {
          await NocturneService.instance.hold(item);
        }
      }
    } catch (_) {
      // 提炼失败不影响聊天,下次对话会再试。
    }
  }

  /// 仅取最近 [_maxContextMessages] 条对话作为模型上下文,避免长对话 token 膨胀。
  List<({String role, String content})> _recentContext() {
    if (_messages.length <= _maxContextMessages) return List.of(_messages);
    return _messages.sublist(_messages.length - _maxContextMessages);
  }

  /// 本地工具执行:模型调用工具时在这里查询本地数据,返回文本结果。
  /// 写操作(记账/加任务/完成任务)先弹用户确认,确认后才真正执行。
  Future<String> _execTool(String name, Map<String, dynamic> args) async {
    // 写操作:先向用户确认。
    if (ToolRegistry.needsConfirm(name)) {
      final desc = _describeToolCall(name, args);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('小掌柜想帮你执行操作'),
          content: Text(
            '$desc\n\n是否允许?',
            style: const TextStyle(height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('不允许'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('允许'),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        return ToolRegistry.execute(name, args, confirmed: true);
      }
      return '用户拒绝了该操作,不要执行,并向用户确认是否需要调整。';
    }
    return ToolRegistry.execute(name, args);
  }

  /// 生成工具调用的可读描述(用于确认弹窗)。
  String _describeToolCall(String name, Map<String, dynamic> args) {
    switch (name) {
      case 'add_ledger':
        final type = (args['type'] as String?) ?? 'expense';
        final amount = (args['amount'] as num?)?.toDouble() ?? 0;
        final category = (args['category'] as String?) ?? '其他';
        final note = (args['note'] as String?)?.trim() ?? '';
        return '记一笔${type == 'income' ? '收入' : '支出'} ¥${amount.toStringAsFixed(2)}'
            '($category)${note.isEmpty ? '' : ' $note'}';
      case 'add_task':
        return '添加任务「${args['title']}」';
      case 'complete_task':
        return '完成任务「${args['title']}」';
      default:
        return '执行「$name」';
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
            onPressed: () async {
              final picked = await AppRoutes.push<int>(
                  context, const SessionListPage());
              if (picked == null || !mounted) return;
              final msgs = await _chatService.messages(picked);
              if (!mounted) return;
              setState(() {
                _sessionId = picked;
                _messages = [
                  for (final m in msgs) (role: m.role, content: m.content),
                ];
              });
              _scrollToBottom();
            },
            icon: const Icon(Icons.forum_outlined, size: 20),
            tooltip: '会话记录',
          ),
          IconButton(
            onPressed: () {
              AppRoutes.push(context, const MemoryPage());
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
        child: _binding
            ? const Center(child: CircularProgressIndicator())
            : Column(
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
                        '这里的对话会按会话保存,随时可以回来接着聊。',
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
