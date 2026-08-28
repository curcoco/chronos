import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:chronos/routes.dart';
import 'package:chronos/core/services/ai_provider.dart';
import 'package:chronos/core/services/app_log.dart';
import 'package:chronos/core/services/db_helper.dart';
import 'package:chronos/core/services/key_store.dart';
import 'package:chronos/core/services/notification_service.dart';
import 'package:chronos/core/services/settings_service.dart';
import 'package:chronos/core/theme.dart';
import 'package:chronos/core/utils/context_budget.dart';
import 'package:chronos/core/widgets/app_text_field.dart';
import 'package:chronos/core/widgets/frosted_snack.dart';
import 'package:chronos/core/widgets/status_views.dart';
import 'package:chronos/features/chat/pages/session_list_page.dart';
import 'package:chronos/features/chat/pages/shopkeeper_settings_page.dart';
import 'package:chronos/features/chat/services/chat_service.dart';
import 'package:chronos/features/chat/services/eleven_service.dart';
import 'package:chronos/features/chat/services/llm_service.dart';
import 'package:chronos/features/chat/services/nocturne_service.dart';
import 'package:chronos/features/chat/services/shopkeeper_store.dart';
import 'package:chronos/features/chat/tools/tool_registry.dart';
import 'package:chronos/features/memory/services/memory_service.dart';
import 'package:chronos/features/memory/services/auto_memory_service.dart';
import 'package:chronos/features/memory/services/memory_extractor.dart';
import 'package:chronos/features/settings/pages/api_settings_page.dart';

/// 零时闲话铺:与 AI 掌柜聊天(中转站大模型),AI 回复可语音朗读(elevenlabs)。
/// - 全屏页面进入(底部导航不显示);首次进入直达**最近会话**,不再先弹会话列表;
///   会话切换通过 AppBar「会话记录」完成;
/// - 掌柜身份(名称/头像/人设)在「掌柜设置」页配置;
/// - 支持发图:[initialSessionId] 指定会话直达;图片先走聊天默认模型,
///   模型不支持时回退到配置的 OCR 模型识别文字后再对话;图片会复制到
///   应用文档目录并随消息落库(v14),历史消息也能显示原图;
/// - 文本消息**流式输出**(SSE,逐字上屏),生成中可点「停止」;
/// - 会话按窗口长期保存(v12 起取消「零点万事清零」)。
class ChatPage extends StatefulWidget {
  final int? initialSessionId;

  const ChatPage({super.key, this.initialSessionId});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final ChatService _chatService = ChatService.instance;

  /// 工具由注册表统一管理(见 tool_registry.dart):只读工具 + 需确认的写工具。
  List<Map<String, dynamic>> get _tools => ToolRegistry.definitions();

  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll = ScrollController();

  /// 喂给模型的最大历史条数:超过时先压缩早期对话(快速模型摘要)再裁剪,
  /// 长对话不丢早期信息。可在「掌柜设置」里调整(10~800)。
  /// 实际发送还受 token 预算([ContextBudget.rawHistoryBudget])自动裁剪,
  /// 不会撑爆模型上下文窗口。
  /// (本地仍完整展示会话;只裁剪"喂给模型"的上下文。)
  int _maxContextMessages = ShopkeeperStore.contextDefault;

  int? _sessionId; // 当前绑定的会话;null = 尚未初始化
  bool _binding = true;

  /// 聊天消息:role=user/assistant;imagePath 为用户消息的图片本地路径(v14 起落库);
  /// createdAt 为消息时间(毫秒,用于气泡时间戳);
  /// thinking 为推理模型的思维链文本(仅内存展示,不落库)。
  List<
          ({
            String role,
            String content,
            String? imagePath,
            int createdAt,
            String? thinking
          })>
      _messages = [];
  String _persona = '';
  String _shopkeeperName = '';
  String _shopkeeperAvatar = '';
  String _userAvatar = ''; // 用户头像本地路径(空 = 未设置,显示占位图标)
  String? _pendingImagePath; // 已选待发送的图片
  bool _picking = false;
  bool _generating = false; // 生图中
  bool _sending = false;
  bool _translating = false; // 翻译中,防重复触发
  bool _llmOk = false;

  /// Token 仪表盘:最近一次请求用量 + 本会话累计(供聊天页顶部展示)。
  LlmUsage? _lastUsage;
  int _sessionPromptTokens = 0;
  int _sessionCompletionTokens = 0;
  int _sessionCachedTokens = 0;

  /// 聊天模型是否支持 1M 上下文(API 配置勾选)→ 决定上下文 token 档位。
  bool _supports1m = false;
  bool _contextWarned = false; // 本次会话是否已提示过「上下文较大」

  /// 流式请求句柄:用于「停止生成」与页面销毁/切会话时取消。
  StreamSubscription<({String text, String reasoning})>? _streamSub;
  Completer<void>? _streamDone;

  /// 上下文压缩缓存:已压缩到的消息条数与摘要文本。
  int _compressedUpTo = 0;
  String? _compressedSummary;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelStream();
    _ctrl.dispose();
    _scroll.dispose();
    ElevenService.instance.stop();
    super.dispose();
  }

  bool _bgGenerating = false; // 是否正后台生成(启动过前台服务保活)
  bool _notifAsked = false; // 是否已请求过通知权限(Android 13+)

  /// app 退后台且正生成 → 启动前台服务保活,SSE 不被系统冻结(受「后台生成通知」开关控制)。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_sending &&
        SettingsService.instance.backgroundNotify.value &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.inactive)) {
      _bgGenerating = true;
      NotificationService.instance.startChatService();
    }
  }

  /// 初始化:直达最近会话(无则新建);指定 [initialSessionId] 时直接绑定。
  Future<void> _init() async {
    var sessionId = widget.initialSessionId;
    if (sessionId == null) {
      // 直达模式:最近更新的会话优先(createSession 会更新 updated_at)。
      final sessions = await _chatService.sessions();
      sessionId = sessions.isEmpty
          ? await _chatService.createSession()
          : sessions.first.id!;
    }
    final msgs = await _chatService.messages(sessionId);
    final persona = await ShopkeeperStore.instance.persona();
    final name = await ShopkeeperStore.instance.name();
    final avatar = await ShopkeeperStore.instance.avatarPath();
    final contextSize = await ShopkeeperStore.instance.contextSize();
    final userAvatar = await SettingsService.instance.avatarPath();
    final llmOk = await LlmService.instance.isConfigured();
    final supports1m =
        (await KeyStore.instance.get(KeyStore.llmSupports1m)) == '1';
    if (!mounted) return;
    setState(() {
      _sessionId = sessionId;
      _messages = [
        for (final m in msgs)
          (role: m.role,
              content: m.content,
              imagePath: m.imagePath,
              createdAt: m.createdAt,
              thinking: m.reasoningContent),
      ];
      _persona = persona;
      _shopkeeperName = name;
      _shopkeeperAvatar = avatar;
      _maxContextMessages = contextSize;
      _userAvatar = userAvatar;
      _llmOk = llmOk;
      _supports1m = supports1m;
      _binding = false;
    });
    _scrollToBottom();
    _maybeShowGuide();
  }

  /// 首次进入的一次性引导:提示「会话记录」入口在右上角。
  Future<void> _maybeShowGuide() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('chat_guide_done') ?? false) return;
    await prefs.setBool('chat_guide_done', true);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showFrostedSnack(context, '会话记录在右上角,可切换 / 管理聊天窗口');
    });
  }

  /// 打开 API 配置页,返回后刷新配置状态(含 1M 上下文档位)。
  Future<void> _openApiSettings() async {
    await AppRoutes.push(context, const ApiSettingsPage());
    final llmOk = await LlmService.instance.isConfigured();
    final supports1m =
        (await KeyStore.instance.get(KeyStore.llmSupports1m)) == '1';
    if (!mounted) return;
    setState(() {
      _llmOk = llmOk;
      _supports1m = supports1m;
    });
  }

  /// 打开掌柜设置页,返回后刷新掌柜资料(名称/头像/人设/上下文条数)。
  Future<void> _openShopkeeperSettings() async {
    await AppRoutes.push(context, const ShopkeeperSettingsPage());
    final persona = await ShopkeeperStore.instance.persona();
    final name = await ShopkeeperStore.instance.name();
    final avatar = await ShopkeeperStore.instance.avatarPath();
    final contextSize = await ShopkeeperStore.instance.contextSize();
    if (!mounted) return;
    setState(() {
      _persona = persona;
      _shopkeeperName = name;
      _shopkeeperAvatar = avatar;
      _maxContextMessages = contextSize;
    });
  }

  /// 追加消息并持久化到当前会话
  Future<void> _appendMessage(String role, String content,
      {String? imagePath, String? reasoningContent}) async {
    final sid = _sessionId;
    if (sid == null) return;
    await _chatService.addMessage(
        sessionId: sid,
        role: role,
        content: content,
        imagePath: imagePath,
        reasoningContent: reasoningContent);
  }

  /// 最终人设:基础人设 + 掌柜名称(设置了名称时)+ Auto Memory 指令块(开启时)。
  String _buildPersona() {
    final base = _shopkeeperName.trim().isEmpty
        ? _persona
        : '$_persona\n用户称你为「${_shopkeeperName.trim()}」,请以这个身份与用户对话。';
    if (!SettingsService.instance.autoMemory.value) return base;
    return '$base\n${AutoMemoryService.instructionBlock}';
  }

  /// 记忆注入段:本地长期记忆 + 外置记忆(Nocturne MCP,未配置静默)。
  /// 外置记忆只做「锦上添花」:地址不可达/超时时跳过,绝不阻塞聊天主流程。
  Future<String> _memorySection() async {
    final query = _recentUserText();
    var memory = await MemoryService.instance.promptSectionFor(query);
    try {
      final external = await NocturneService.instance
          .breath(query.isNotEmpty ? query : '最近话题')
          .timeout(const Duration(seconds: 8));
      if (external != null && external.isNotEmpty) {
        memory = '$memory\n\n【外置记忆检索】\n$external';
      }
    } catch (e) {
      AppLog.instance.e('外置记忆检索超时/失败,跳过(不影响聊天):$e');
    }
    return memory;
  }

  /// 组装喂给模型的上下文:
  /// - 条数上限(用户设置)+ 模型档位 token 预算双约束,从尾部向前取尽量多的消息;
  /// - 超过预警线时提醒一次(更早的部分自动压缩成摘要);
  /// - 更早的部分用快速模型压缩成摘要(带缓存,失败回退为直接丢弃超限部分);
  /// - 返回去掉 imagePath 的纯文本记录;assistant 消息带 reasoningContent
  ///   (推理模型如 DeepSeek 要求把上一轮思维链原样回传,否则 API 拒绝)。
  Future<List<({String role, String content, String? reasoningContent})>>
      _buildContext() async {
    List<({String role, String content, String? reasoningContent})> two(
            List<
                    ({
                      String role,
                      String content,
                      String? imagePath,
                      int createdAt,
                      String? thinking
                    })>
                msgs) =>
        [
          for (final m in msgs)
            (
              role: m.role,
              content: m.content,
              reasoningContent:
                  m.role == 'assistant' ? m.thinking : null,
            )
        ];
    if (_messages.isEmpty) return const [];
    final budget = ContextBudget.budgetFor(_supports1m);
    final kept = ContextBudget.keepCount(
      two(_messages),
      maxCount: _maxContextMessages,
      budget: budget,
    );
    if (_messages.length <= kept) return two(_messages);
    final overflow = _messages.length - kept;
    if (overflow > _compressedUpTo) {
      final slice = _messages.sublist(0, overflow);
      try {
        final summary = await _compressSlice(two(slice));
        _compressedSummary = summary;
        _compressedUpTo = overflow;
      } catch (e) {
        AppLog.instance.e('上下文压缩失败,回退硬裁剪:$e');
        _compressedSummary = null;
        _compressedUpTo = _messages.length; // 避免每次发送都重试
      }
    }
    final tail = two(_messages.sublist(_messages.length - kept));
    final summary = _compressedSummary;
    // 上下文较大预警(每次会话最多提示一次,提醒用户适时压缩/新开会话)。
    _maybeWarnContext(tail);
    if (summary == null || summary.isEmpty) return tail;
    return [
      (role: 'user', content: '【更早的对话摘要】\n$summary', reasoningContent: null),
      ...tail,
    ];
  }

  /// 原始上下文累计 token 超过模型档位预警线时,提示一次「上下文较大」。
  void _maybeWarnContext(
      List<({String role, String content, String? reasoningContent})> tail) {
    if (_contextWarned || !mounted) return;
    final tokens = ContextBudget.totalTokens(tail);
    final warn = ContextBudget.warnThresholdFor(_supports1m);
    if (tokens <= warn) return;
    _contextWarned = true;
    AppLog.instance.i('上下文较大:约 $tokens token(预警 $warn)');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showFrostedSnack(context, '上下文较长,已自动压缩,建议新开会话');
    });
  }

  /// 用快速模型把一段早期对话压成要点摘要(供 [chatStream] 上下文)。
  Future<String> _compressSlice(
      List<({String role, String content, String? reasoningContent})>
          slice) async {
    final fastModel = await AiProviders.fastModelRef();
    final prompt = '把下面的对话压缩成 3~5 条要点摘要(用户信息、决定、待办优先),'
        '只输出摘要文本,不要解释:\n\n'
        '${slice.map((m) => '${m.role == 'user' ? '用户' : 'AI'}:${m.content}').join('\n')}';
    return LlmService.instance
        .chat(
          history: [(role: 'user', content: prompt, reasoningContent: null)],
          persona: '你是对话摘要助手。',
          modelRef: fastModel.isEmpty ? null : fastModel,
        )
        .timeout(const Duration(seconds: 20));
  }

  /// 发送:文本走流式输出(逐字上屏,可停止);图片走默认模型→OCR 回退(非流式)。
  Future<void> _send() async {
    final text = _ctrl.text.trim();
    final imgPath = _pendingImagePath;
    if ((text.isEmpty && imgPath == null) || _sending || _sessionId == null) {
      return;
    }
    // Android 13+ 首次发送时申请通知权限(后台生成完成通知需要;不阻塞发送)。
    if (!_notifAsked && SettingsService.instance.backgroundNotify.value) {
      _notifAsked = true;
      NotificationService.instance.requestNotificationPermission();
    }
    final llmOk = await LlmService.instance.isConfigured();
    if (!mounted) return;
    if (!llmOk) {
      // 配置缺失是「掌柜不回复」最常见原因:记日志便于排查是哪个字段没填。
      AppLog.instance.e('发送被拦截:聊天服务未配置'
          '(中转站地址/API Key/聊天模型缺一不可,见 系统设置 → API 配置)');
      showFrostedSnack(context, '聊天服务未配置,请先到 API 配置');
      return;
    }
    _ctrl.clear();
    final userContent = imgPath == null
        ? text
        : (text.isEmpty ? '[图片]' : '$text\n[图片]');
    // 图片持久化:复制到应用文档目录,随消息落库(历史消息可显示原图)。
    String? storedImage;
    if (imgPath != null) {
      storedImage = await _persistImage(imgPath);
    }
    setState(() {
      _messages.add((
          role: 'user',
          content: userContent,
          imagePath: storedImage ?? imgPath,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          thinking: null));
      _pendingImagePath = null;
      _sending = true;
    });
    try {
      await _appendMessage('user', userContent, imagePath: storedImage ?? imgPath);
      AppLog.instance
          .i('已保存用户消息(会话 $_sessionId, 含图片=${imgPath != null})');
      _scrollToBottom();
      // 记忆注入有整体超时:外置记忆不可达时 8 秒内降级,不阻塞发送。
      final memory =
          await _memorySection().timeout(const Duration(seconds: 15));
      AppLog.instance.i('开始请求掌柜回复(会话 $_sessionId)');
      // 先放一个空的 assistant 气泡,流式逐字填充。
      setState(() {
        _messages.add((
            role: 'assistant',
            content: '',
            imagePath: null,
            createdAt: DateTime.now().millisecondsSinceEpoch,
            thinking: null));
      });
      final result = await _streamReply(
          text: text, imgPath: imgPath, storedImage: storedImage, memory: memory);
      // Auto Memory:截取并执行回复里的记忆标签,标签本身从正文剥离。
      final am = await AutoMemoryService.instance.processReply(result.text);
      final reply = am.cleaned;
      if (!mounted) return;
      if (reply.trim().isEmpty) {
        // 空回复视为失败(例如流被停止且没有产生任何文本):以 AI 气泡完整提示,
        // 不再挤在底部提示条里(一长就显示不全)。
        setState(() {
          _fillErrorBubble('掌柜没有回复,请稍后重试');
          _sending = false;
        });
        AppLog.instance.e('掌柜回复为空(流式)');
        return;
      }
      setState(() {
        final prev = _messages[_messages.length - 1];
        _messages[_messages.length - 1] = (
            role: 'assistant',
            content: reply,
            imagePath: null,
            createdAt: prev.createdAt,
            thinking: prev.thinking);
        _sending = false;
      });
      await _appendMessage('assistant', reply,
          reasoningContent:
              result.thinking.trim().isEmpty ? null : result.thinking);
      AppLog.instance.i('掌柜回复完成(长度 ${reply.length})');
      _scrollToBottom();
      if (am.results.isNotEmpty) {
        _reportAutoMemory(am.results);
      }
      // 对话后自动提炼记忆(快速模型,后台执行,失败静默不影响聊天)。
      await _autoExtract();
    } on LlmImageNotSupportedError {
      if (!mounted) return;
      setState(() {
        _fillErrorBubble('该模型不支持图片,请配置 OCR 模型');
        _sending = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // 失败原因完整显示在 AI 气泡里(可回溯),不再只靠底部提示条。
        _fillErrorBubble(_friendlyError(e));
        _sending = false;
      });
      AppLog.instance.e('聊天请求失败:$e');
      _scrollToBottom();
    } finally {
      _finishBackendGeneration();
    }
  }

  /// 生成结束(成功/失败/停止):若后台生成过 → 停前台服务 + 弹完成通知。
  void _finishBackendGeneration() {
    if (!_bgGenerating) return;
    _bgGenerating = false;
    final last = _messages.isNotEmpty ? _messages.last.content : '';
    NotificationService.instance
      ..stopChatService()
      ..notifyChatDone(last.isEmpty ? '掌柜已回复' : last);
  }

  /// 把错误/提示信息作为 AI 气泡展示(完整可见、可回溯):
  /// - 最后一条是空的 assistant 气泡 → 直接填入(替换「掌柜正在想…」);
  /// - 最后一条是 assistant 且已有部分文本 → 保留原文,换行追加提示;
  /// - 否则(异常发生在空气泡之前)→ 补一条 assistant 气泡。
  /// 注意:错误气泡不落库(不属于真实对话,避免混入后续上下文)。
  void _fillErrorBubble(String message) {
    final text = message.trim();
    if (text.isEmpty) return;
    if (_messages.isNotEmpty && _messages.last.role == 'assistant') {
      final cur = _messages.last;
      final t = cur.createdAt;
      _messages[_messages.length - 1] = (
        role: 'assistant',
        content: cur.content.isEmpty ? text : '${cur.content}\n\n$text',
        imagePath: null,
        createdAt: t,
        thinking: cur.thinking,
      );
    } else {
      _messages.add((
          role: 'assistant',
          content: text,
          imagePath: null,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          thinking: null));
    }
  }

  /// Token 仪表盘:记录一次请求的用量(收到即刷新显示)。
  void _recordUsage(LlmUsage? usage) {
    if (usage == null || !mounted) return;
    setState(() {
      _lastUsage = usage;
      _sessionPromptTokens += usage.promptTokens;
      _sessionCompletionTokens += usage.completionTokens;
      _sessionCachedTokens += usage.cachedTokens;
    });
  }

  /// 请求掌柜回复:文本 → 流式(可停止);图片 → 非流式(默认模型→OCR 回退)。
  /// 返回 (完整回复文本, 思维链全文);思维链用于落库回传(推理模型要求)。
  Future<({String text, String thinking})> _streamReply({
    required String text,
    required String? imgPath,
    required String? storedImage,
    required String memory,
  }) async {
    if (imgPath != null) {
      final path = storedImage ?? imgPath;
      return (
        text: await _chatWithImage(text, path, memory, onUsage: _recordUsage)
            .timeout(const Duration(seconds: 150)),
        thinking: '',
      );
    }
    final buf = StringBuffer();
    final thinkBuf = StringBuffer(); // 思维链(推理模型),单独拼接
    final completer = Completer<void>();
    _streamSub = LlmService.instance
        .chatStream(
          history: await _buildContext(),
          persona: _buildPersona() + memory,
          tools: _tools,
          onTool: _execTool,
          onUsage: _recordUsage,
        )
        .listen(
      (chunk) {
        if (!mounted) return;
        if (chunk.text.isNotEmpty) buf.write(chunk.text);
        if (chunk.reasoning.isNotEmpty) thinkBuf.write(chunk.reasoning);
        setState(() {
          if (_messages.isNotEmpty && _messages.last.role == 'assistant') {
            // 流式逐字更新:保留气泡的 createdAt(发送时刻),只换内容。
            final t = _messages.last.createdAt;
            _messages[_messages.length - 1] = (
                role: 'assistant',
                content: buf.toString(),
                imagePath: null,
                createdAt: t,
                thinking: thinkBuf.toString());
          }
        });
        _scrollToBottom();
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );
    _streamDone = completer;
    try {
      await completer.future.timeout(const Duration(seconds: 150));
    } on TimeoutException {
      await _streamSub?.cancel();
      _streamSub = null;
      _streamDone = null;
      rethrow;
    } finally {
      _streamSub = null;
      _streamDone = null;
    }
    return (text: buf.toString(), thinking: thinkBuf.toString());
  }

  /// 停止生成:取消流式订阅并让等待继续(保留已生成的部分文本)。
  Future<void> _stopGenerating() async {
    final sub = _streamSub;
    final done = _streamDone;
    _streamSub = null;
    _streamDone = null;
    AppLog.instance.i('用户停止生成');
    await sub?.cancel();
    if (done != null && !done.isCompleted) done.complete();
  }

  /// 取消当前流式请求(页面销毁 / 切换会话时调用,不保留文本)。
  void _cancelStream() {
    _streamSub?.cancel();
    _streamSub = null;
    _streamDone = null;
  }

  /// 把选中的图片复制到应用文档目录 chat_imgs/(持久化,历史消息显示原图)。
  /// 复制失败时返回原路径(本会话仍可显示,只是不落库)。
  Future<String?> _persistImage(String srcPath) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'chat_imgs'));
      if (!await dir.exists()) await dir.create(recursive: true);
      final ext = srcPath.toLowerCase().endsWith('.png') ? '.png' : '.jpg';
      final dest =
          p.join(dir.path, 'msg_${DateTime.now().millisecondsSinceEpoch}$ext');
      await File(srcPath).copy(dest);
      return dest;
    } catch (e) {
      AppLog.instance.e('图片持久化失败,本会话仍可显示:$e');
      return srcPath;
    }
  }

  /// 带图对话:先走聊天默认模型;模型不支持图片时回退 OCR 模型识别文字,
  /// 再用识别结果让聊天模型继续对话。
  Future<String> _chatWithImage(String text, String path, String memory,
      {void Function(LlmUsage?)? onUsage}) async {
    final bytes = await File(path).readAsBytes();
    final base64Str = base64Encode(bytes);
    final mime = _mimeOf(path);
    try {
      return await LlmService.instance.chatWithImage(
        text: text.isEmpty ? '请看这张图片' : text,
        history: await _buildContext(),
        persona: _buildPersona() + memory,
        imageBase64: base64Str,
        imageMime: mime,
        tools: _tools,
        onTool: _execTool,
        onUsage: onUsage,
      );
    } on LlmImageNotSupportedError {
      rethrow;
    } catch (e) {
      AppLog.instance.i('默认模型不支持图片,回退 OCR 模型:$e');
      final ocrModel = await AiProviders.ocrModelRef();
      if (ocrModel.isEmpty) {
        throw const LlmImageNotSupportedError();
      }
      // 1) OCR 模型提取图片文字
      final ocrText = await LlmService.instance.chatWithImage(
        text: '请识别这张图片中的全部文字,只输出识别结果,不要任何解释。',
        history: const [],
        persona: '你是 OCR 文字识别模型,只输出图片中识别到的文字。',
        imageBase64: base64Str,
        imageMime: mime,
        modelRef: ocrModel,
      );
      // 2) 把识别结果交给聊天模型继续对话
      return await LlmService.instance.chat(
        history: [
          ...await _buildContext(),
          (
            role: 'user',
            content: '[用户发来一张图片]\n图片中的文字:\n$ocrText',
            reasoningContent: null
          ),
        ],
        persona: _buildPersona() + memory,
        tools: _tools,
        onTool: _execTool,
        onUsage: onUsage,
      );
    }
  }

  static String _mimeOf(String path) =>
      path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';

  /// 把图片字节保存到 chat_imgs/,返回本地路径。
  Future<String> _persistImageBytes(Uint8List bytes, String ext) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'chat_imgs'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final dest =
        p.join(dir.path, 'gen_${DateTime.now().millisecondsSinceEpoch}.$ext');
    await File(dest).writeAsBytes(bytes);
    return dest;
  }

  /// 生成图片:输入提示词 → 调生图模型(GPT-image-2 等)→ 存为聊天图片消息并落库。
  Future<void> _generateImage() async {
    final url = await KeyStore.instance.get(KeyStore.imageGenUrl);
    final key = await KeyStore.instance.get(KeyStore.imageGenKey);
    final model = await KeyStore.instance.get(KeyStore.imageGenModel);
    if (!mounted) return;
    if (url.isEmpty || key.isEmpty || model.isEmpty) {
      showFrostedSnack(context, '未配置生图模型,请到 设置 → API 配置 填写');
      return;
    }
    final promptCtrl = TextEditingController();
    final prompt = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('生成图片'),
        content: AppTextField(
          controller: promptCtrl,
          maxLines: 3,
          hintText: '描述你想生成的画面…',
          onSubmit: () => Navigator.of(ctx).pop(promptCtrl.text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(promptCtrl.text.trim()),
            child: const Text('生成'),
          ),
        ],
      ),
    );
    if (prompt == null || prompt.isEmpty || !mounted) return;
    setState(() => _generating = true);
    try {
      final result = await AiProviders.generateImage(
        url: url,
        apiKey: key,
        model: model,
        prompt: prompt,
      ).timeout(const Duration(seconds: 120));
      if (!mounted) return;
      if (result == null) {
        showFrostedSnack(context, '生成失败:请检查生图模型配置或网络');
        return;
      }
      final path = await _persistImageBytes(result.bytes, 'png');
      if (!mounted) return;
      setState(() {
        _messages.add((
          role: 'assistant',
          content: '已生成图片',
          imagePath: path,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          thinking: null,
        ));
      });
      await _appendMessage('assistant', '已生成图片', imagePath: path);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      AppLog.instance.e('生图失败:$e');
      showFrostedSnack(context, '生成失败,请重试');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  /// 让掌柜看生成的图:把图片作为图片消息发出(走 _send,默认模型→OCR 回退)。
  Future<void> _refImageToShopkeeper(String path) async {
    if (_sending) return;
    setState(() => _pendingImagePath = path);
    if (_ctrl.text.trim().isEmpty) {
      _ctrl.text = '请看看这张图';
    }
    await _send();
  }

  /// 选择待发送图片(压缩到 1280px,内存/传输都友好)。
  Future<void> _pickImage() async {
    if (_picking || _sending) return;
    setState(() => _picking = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 80,
      );
      if (picked == null || !mounted) return;
      setState(() => _pendingImagePath = picked.path);
    } catch (_) {
      if (!mounted) return;
      showFrostedSnack(context, '选择图片失败,请重试');
    } finally {
      if (mounted) setState(() => _picking = false);
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
  /// Auto Memory 操作汇报:用一个 frosted 提示简要说明掌柜写了/改了哪些档案。
  void _reportAutoMemory(List<AutoMemoryOpResult> results) {
    if (!mounted || results.isEmpty) return;
    final okCount = results.where((r) => r.ok).length;
    final failCount = results.length - okCount;
    final parts = <String>[
      if (okCount > 0) '记忆 $okCount 条',
      if (failCount > 0) '跳过 $failCount 条',
    ];
    if (parts.isEmpty) return;
    showFrostedSnack(context, '掌柜已更新档案:${parts.join(' / ')}');
  }

  Future<void> _autoExtract() async {
    try {
      final result = await MemoryExtractor.instance
          .extractFrom(_messages.map((m) => (role: m.role, content: m.content)).toList());
      // 外置记忆同步(用户自配;未配置/失败自动忽略)。
      if (result.added > 0) {
        for (final item in result.addedItems) {
          await NocturneService.instance.hold(item);
        }
        AppLog.instance.i('自动提炼新增 ${result.added} 条记忆');
      }
    } catch (e) {
      AppLog.instance.e('自动提炼失败:$e');
    }
  }

  /// Token 仪表盘:最近一次请求用量 + 缓存命中 + 本会话累计。
  /// 未产生任何用量且未在生成时不显示,保持聊天页干净。
  Widget _tokenBar() {
    if (!_sending && _lastUsage == null) return const SizedBox.shrink();
    final Color sub = AppColors.textSub;
    if (_sending) {
      return _tokenStrip([
        Text('生成中…', style: TextStyle(fontSize: 11, color: sub)),
      ]);
    }
    final u = _lastUsage!;
    final cachePct = u.promptTokens > 0
        ? ((u.cachedTokens / u.promptTokens) * 100).round()
        : 0;
    final session = _sessionPromptTokens + _sessionCompletionTokens;
    return _tokenStrip([
      Text(
        '${u.promptTokens}+${u.completionTokens}=${u.totalTokens}',
        style: TextStyle(fontSize: 11, color: sub),
      ),
      if (u.cachedTokens > 0) ...[
        const SizedBox(width: 8),
        Icon(Icons.bolt_rounded, size: 12, color: const Color(0xFF43A047)),
        Text('缓存命中 ${u.cachedTokens}($cachePct%)',
            style: TextStyle(
                fontSize: 11,
                color: const Color(0xFF43A047),
                fontWeight: FontWeight.w600)),
      ],
      const Spacer(),
      Text(
        _sessionCachedTokens > 0
            ? '本会话 $session tokens · 缓存 $_sessionCachedTokens'
            : '本会话 $session tokens',
        style: TextStyle(fontSize: 11, color: sub),
      ),
    ]);
  }

  Widget _tokenStrip(List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      color: AppColors.card.withValues(alpha: 0.6),
      child: Row(
        children: [
          Icon(Icons.data_usage_rounded, size: 13, color: AppColors.textSub),
          const SizedBox(width: 6),
          ...children,
        ],
      ),
    );
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
        final r = await ToolRegistry.execute(name, args, confirmed: true);
        AppLog.instance.i('小掌柜执行写操作:$desc → $r');
        return r;
      }
      AppLog.instance.i('用户拒绝了小掌柜的写操作:$desc');
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
      showFrostedSnack(context, '语音服务未配置,请先到 API 配置');
      return;
    }
    try {
      await ElevenService.instance.speak(content);
    } catch (e) {
      // 语音失败(Key 失效/额度清零/网络)记日志,便于诊断「朗读没声音」。
      AppLog.instance.e('语音朗读失败:$e');
      if (!mounted) return;
      showFrostedSnack(context, '语音播放失败,请检查语音配置或额度');
    }
  }

  /// 消息时间戳:今天的消息不显示(当天对话界面保持干净),
  /// 跨天消息显示「MM/dd HH:mm」用于区分历史。
  static String? _timeLabel(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return null;
    }
    return '${t.month.toString().padLeft(2, '0')}/'
        '${t.day.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  /// 长按消息:弹出操作菜单(复制 / 翻译;最后一条 AI 回复额外支持重新生成)。
  Future<void> _showMessageActions(int index) async {
    final m = _messages[index];
    final text = m.content.trim();
    if (text.isEmpty) return;
    final isLastAssistant =
        index == _messages.length - 1 && m.role == 'assistant';
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy_rounded, size: 20),
              title: const Text('复制'),
              onTap: () => Navigator.of(context).pop('copy'),
            ),
            ListTile(
              leading: const Icon(Icons.translate_rounded, size: 20),
              title: const Text('翻译'),
              onTap: () => Navigator.of(context).pop('translate'),
            ),
            if (isLastAssistant)
              ListTile(
                leading: const Icon(Icons.refresh_rounded, size: 20),
                title: const Text('重新生成'),
                onTap: () => Navigator.of(context).pop('regenerate'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'copy':
        await _copyMessage(text);
      case 'translate':
        await _translateMessage(text);
      case 'regenerate':
        await _regenerate();
    }
  }

  Future<void> _copyMessage(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showFrostedSnack(context, '已复制');
  }

  /// 翻译消息:调聊天模型翻译(内容为中文则译成英文,否则译成简体中文),
  /// 译文在弹窗内完整展示,可一键复制;失败仅提示不打断对话。
  Future<void> _translateMessage(String content) async {
    if (_translating) return;
    setState(() => _translating = true);
    try {
      final prompt = '把以下内容翻译:若内容为中文则译成英文,否则译成简体中文。'
          '只输出译文,不要任何解释或原文。\n\n$content';
      final result = await LlmService.instance
          .chat(
            history: [
              (role: 'user', content: prompt, reasoningContent: null)
            ],
            persona: '你是翻译助手。',
          )
          .timeout(const Duration(seconds: 60));
      final translation = result.trim();
      if (!mounted) return;
      if (translation.isEmpty) {
        showFrostedSnack(context, '翻译结果为空,请重试');
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('译文'),
          content: SingleChildScrollView(
            child: SelectableText(translation,
                style: const TextStyle(fontSize: 14, height: 1.6)),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: translation));
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('复制译文'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (e) {
      AppLog.instance.e('翻译失败:$e');
      if (!mounted) return;
      showFrostedSnack(context, '翻译失败,请稍后重试');
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  /// 重新生成最后一条 AI 回复:删除旧回复(内存 + DB),以原上下文重新请求。
  /// 上下文锚点取最后一条用户消息(图片消息保持图片路径走原链路)。
  Future<void> _regenerate() async {
    if (_sending || _sessionId == null) return;
    if (_messages.isEmpty || _messages.last.role != 'assistant') return;
    // 1) 定位上下文锚点(最后一条用户消息,含图片路径)
    String? anchorText;
    String? anchorImage;
    for (var i = _messages.length - 1; i >= 0; i--) {
      if (_messages[i].role == 'user') {
        anchorText = _messages[i].content;
        anchorImage = _messages[i].imagePath;
        break;
      }
    }
    // 2) 移除内存中的最后一条 assistant 回复
    setState(() => _messages.removeLast());
    // 3) 删除 DB 中该会话的最后一条 assistant 消息(旧回复)
    final sid = _sessionId!;
    try {
      final db = await DbHelper.instance.database;
      final rows = await db.query('chat_messages',
          where: 'session_id = ? AND role = ?',
          whereArgs: [sid, 'assistant'],
          orderBy: 'created_at DESC',
          limit: 1);
      if (rows.isNotEmpty) {
        await db.delete('chat_messages',
            where: 'id = ?', whereArgs: [rows.first['id']]);
      }
    } catch (e) {
      AppLog.instance.e('重新生成:删除旧回复失败:$e');
    }
    // 4) 重新请求:上下文 = 移除回复后的现有消息(最后一条是原用户消息)
    setState(() {
      _messages.add((
          role: 'assistant',
          content: '',
          imagePath: null,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          thinking: null));
      _sending = true;
    });
    try {
      final memory =
          await _memorySection().timeout(const Duration(seconds: 15));
      final result = await _streamReply(
          text: anchorText ?? '',
          imgPath: anchorImage,
          storedImage: anchorImage,
          memory: memory);
      final reply = result.text;
      if (!mounted) return;
      if (reply.trim().isEmpty) {
        setState(() {
          _fillErrorBubble('掌柜没有回复,请稍后重试');
          _sending = false;
        });
        return;
      }
      setState(() {
        final prev = _messages[_messages.length - 1];
        _messages[_messages.length - 1] = (
            role: 'assistant',
            content: reply,
            imagePath: null,
            createdAt: prev.createdAt,
            thinking: prev.thinking);
        _sending = false;
      });
      await _appendMessage('assistant', reply,
          reasoningContent:
              result.thinking.trim().isEmpty ? null : result.thinking);
      _scrollToBottom();
      await _autoExtract();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _fillErrorBubble(_friendlyError(e));
        _sending = false;
      });
      AppLog.instance.e('重新生成失败:$e');
      _scrollToBottom();
    } finally {
      _finishBackendGeneration();
    }
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
        title: Text(_shopkeeperName.trim().isEmpty
            ? '零时闲话铺'
            : '闲话铺 · ${_shopkeeperName.trim()}'),
        actions: [
          IconButton(
            onPressed: () async {
              _cancelStream(); // 切换会话前取消进行中的生成
              final picked = await AppRoutes.push<int>(
                  context, const SessionListPage());
              if (picked == null || !mounted) return;
              final msgs = await _chatService.messages(picked);
              if (!mounted) return;
              setState(() {
                _sessionId = picked;
                _messages = [
                  for (final m in msgs)
                    (role: m.role,
                        content: m.content,
                        imagePath: m.imagePath,
                        createdAt: m.createdAt,
                        thinking: m.reasoningContent),
                ];
                _compressedUpTo = 0;
                _compressedSummary = null;
                _contextWarned = false;
                _lastUsage = null;
                _sessionPromptTokens = 0;
                _sessionCompletionTokens = 0;
                _sessionCachedTokens = 0;
              });
              _scrollToBottom();
            },
            icon: const Icon(Icons.forum_outlined, size: 20),
            tooltip: '会话记录',
          ),
          IconButton(
            onPressed: _openShopkeeperSettings,
            icon: const Icon(Icons.storefront_rounded, size: 20),
            tooltip: '掌柜设置',
          ),
        ],
      ),
      body: SafeArea(
        child: _binding
            ? const LoadingView(hint: '正在打开会话…')
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
            _tokenBar(),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                // 首项欢迎语 + 每条消息;懒构建,长会话不一次性渲染全部。
                itemCount: 1 + _messages.length,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _bubble(content: _welcomeText(), mine: false),
                    );
                  }
                  final i = index - 1;
                  final m = _messages[i];
                  final isLast = i == _messages.length - 1;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _bubble(
                      content: _displayText(m.content),
                      mine: m.role == 'user',
                      imagePath: m.imagePath,
                      // 旧数据(v14 前)没有图片路径:曾发过图片的仍显示占位
                      hadImage: m.imagePath == null && m.content.endsWith('[图片]'),
                      // 生成中的空气泡显示「掌柜正在想…」
                      thinking:
                          _sending && isLast && m.role == 'assistant' && m.content.isEmpty,
                      chainText: m.thinking,
                      createdAt: m.createdAt,
                      onSpeak: m.role == 'assistant'
                          ? () => _speak(m.content)
                          : null,
                      // 生成图(assistant + 带图)提供「让掌柜看看这张图」。
                      onRefImage: (m.role == 'assistant' && m.imagePath != null)
                          ? () => _refImageToShopkeeper(m.imagePath!)
                          : null,
                      // 长按弹出操作菜单(复制/翻译/重新生成);无内容(生成中)不弹。
                      onLongPress: m.content.trim().isEmpty
                          ? null
                          : () => _showMessageActions(i),
                    ),
                  );
                },
              ),
            ),
            // 待发送图片预览条
            if (_pendingImagePath != null)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(File(_pendingImagePath!),
                          width: 48, height: 48, fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                              width: 48, height: 48,
                              color: AppColors.line)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('已选图片,随下一条消息发送',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSub)),
                    ),
                    IconButton(
                      onPressed: () =>
                          setState(() => _pendingImagePath = null),
                      icon: const Icon(Icons.close_rounded,
                          size: 18, color: Colors.grey),
                      tooltip: '取消图片',
                    ),
                  ],
                ),
              ),
            // 输入区
            Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
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
                    child: AppTextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 4,
                      hintText: '和掌柜聊聊…',
                      // 提交语义走共享输入框:显式 text 键盘 + 「完成」动作键 +
                      // 结尾换行兜底,修复中文输入法下「按发送键没反应、
                      // 要收起键盘才能发出消息」的问题。
                      // 生成中锁定提交(此时按钮是「停止」)。
                      submitLocked: _sending,
                      onSubmit: _send,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 生图按钮:输入提示词生成图片(GPT-image-2 等,需配置生图模型)。
                  IconButton(
                    onPressed: _generating ? null : _generateImage,
                    icon: _generating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.brush_rounded,
                            size: 22, color: AppColors.textSub),
                    tooltip: '生成图片',
                  ),
                  const SizedBox(width: 4),
                  // 右侧按钮随状态切换(只重建按钮,不动整页):
                  // 生成中 → 「停止」;输入有内容(或已选待发图片) → 发送(↑);
                  // 否则 → 「+」选图。
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _ctrl,
                    builder: (context, value, _) {
                      final hasText = value.text.trim().isNotEmpty;
                      final canSend = hasText || _pendingImagePath != null;
                      return Material(
                        color: _sending
                            ? AppColors.card
                            : (canSend ? AppColors.primarySoft : AppColors.card),
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: _sending
                              ? _stopGenerating
                              : (canSend ? _send : _pickImage),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Icon(
                              _sending
                                  ? Icons.stop_rounded
                                  : (canSend
                                      ? Icons.arrow_upward_rounded
                                      : Icons.add_rounded),
                              size: 22,
                              color: _sending
                                  ? AppColors.textSub
                                  : (canSend
                                      ? AppColors.onPrimarySoft
                                      : AppColors.textSub),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 欢迎语:带上掌柜名称(若已设置)。
  String _welcomeText() {
    final name = _shopkeeperName.trim();
    final who = name.isEmpty ? '掌柜' : '掌柜「$name」';
    return '欢迎光临零时闲话铺,我是$who,见多识广,专业在线,玩笑不断。'
        '对话按会话保存,随时回来接着聊。';
  }

  /// 展示文本:去掉消息末尾的「[图片]」占位标记(图片单独以缩略图展示)。
  static String _displayText(String content) {
    if (content.endsWith('[图片]')) {
      final t = content.substring(0, content.length - 4);
      return t.endsWith('\n') ? t.substring(0, t.length - 1) : t;
    }
    return content;
  }

  /// 点击聊天图片:全屏预览(双指缩放) + 保存到相册。
  Future<void> _viewImage(String path) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              maxScale: 5,
              child: Center(
                child: Image.file(File(path),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                        Icons.broken_image_outlined,
                        size: 64,
                        color: Colors.white38)),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.of(ctx).pop(),
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 26),
                tooltip: '关闭',
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 28,
              child: Center(
                child: FilledButton.icon(
                  onPressed: () => _saveImageToGallery(path),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('保存到相册'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 保存聊天图片到系统相册(gal;Android 10+ 走 MediaStore 无需权限)。
  Future<void> _saveImageToGallery(String path) async {
    try {
      await Gal.putImage(path);
      if (!mounted) return;
      showFrostedSnack(context, '已保存到相册');
    } catch (e) {
      AppLog.instance.e('保存聊天图片到相册失败:$e');
      if (!mounted) return;
      showFrostedSnack(context, '保存失败,请重试');
    }
  }

  /// 掌柜头像:34px 圆角方形,与聊天气泡(圆角 16)观感一致、大小和谐。
  Widget _shopkeeperAvatarWidget() {
    final path = _shopkeeperAvatar;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: path.isNotEmpty
          ? Image.file(File(path),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _avatarFallback())
          : _avatarFallback(),
    );
  }

  Widget _avatarFallback() => Icon(Icons.storefront_rounded,
      size: 18, color: AppColors.primaryDark);

  /// 用户头像:样式与掌柜头像一致(34px 圆角方形),显示在右侧用户气泡旁。
  /// 未设置头像时显示人形占位图标,保证左右布局始终对齐。
  Widget _userAvatarWidget() {
    final path = _userAvatar;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: path.isNotEmpty
          ? Image.file(File(path),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _userAvatarFallback())
          : _userAvatarFallback(),
    );
  }

  Widget _userAvatarFallback() =>
      Icon(Icons.person_rounded, size: 18, color: AppColors.primaryDark);

  Widget _bubble({
    required String content,
    required bool mine,
    String? imagePath,
    bool hadImage = false,
    bool thinking = false,
    String? chainText,
    int? createdAt,
    VoidCallback? onSpeak,
    VoidCallback? onLongPress,
    VoidCallback? onRefImage,
  }) {
    final bubble = GestureDetector(
      onLongPress: onLongPress,
      child: Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.72,
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: mine ? AppColors.primarySoft : AppColors.card,
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
          // 思维链(推理模型):灰色折叠块,默认收起,点击展开全文。
          if (chainText != null && chainText.trim().isNotEmpty) ...[
            _ThinkingBlock(text: chainText),
            const SizedBox(height: 8),
          ],
          if (imagePath != null) ...[
            InkWell(
              onTap: () => _viewImage(imagePath),
              borderRadius: BorderRadius.circular(10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(File(imagePath),
                    width: 160,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                        width: 160, height: 90, color: AppColors.line)),
              ),
            ),
            // 生成图气泡:提供「让掌柜看看这张图」,把图发给掌柜继续对话。
            if (onRefImage != null) ...[
              const SizedBox(height: 6),
              InkWell(
                onTap: onRefImage,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('让掌柜看看这张图',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.primaryDark)),
                ),
              ),
            ],
            if (content.isNotEmpty) const SizedBox(height: 8),
          ] else if (hadImage) ...[
            // 旧数据(v14 前):图片未随消息落库,以占位提示曾发过图片
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.image_outlined,
                      size: 13, color: AppColors.primaryDark),
                  const SizedBox(width: 4),
                  Text('图片',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.primaryDark)),
                ],
              ),
            ),
            if (content.isNotEmpty) const SizedBox(height: 8),
          ],
          if (content.isNotEmpty)
            Text(
              content,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: mine ? AppColors.onPrimarySoft : AppColors.textMain,
              ),
            )
          else if (thinking)
            // 生成中且尚无文本:显示等待提示
            Text(
              '掌柜正在想…',
              style: TextStyle(fontSize: 12, color: AppColors.textSub),
            ),
          // 时间戳:生成中的空气泡不显示;今天的消息不显示,跨天显示日期。
          if (!thinking && createdAt != null) ...[
            if (_timeLabel(createdAt) case final String label) ...[
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: mine
                      ? AppColors.onPrimarySoft.withValues(alpha: 0.75)
                      : AppColors.textSub,
                ),
              ),
            ],
          ],
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
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: mine
          ? Row(
              mainAxisSize: MainAxisSize.min,
              // 用户头像在右侧,与气泡顶对齐(与掌柜左侧头像镜像对称)。
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(child: bubble),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _userAvatarWidget(),
                ),
              ],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              // 头像与气泡首行对齐(聊天气泡普遍高于头像,顶对齐更自然)
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: _shopkeeperAvatarWidget(),
                ),
                const SizedBox(width: 8),
                Flexible(child: bubble),
              ],
            ),
    );
  }

  /// 把异常转成简短的用户可读文本(完整原因进日志):
  /// - 超时单独提示;
  /// - 其余取异常详情(HTTP 状态码 + 响应体片段,如「服务返回 401: invalid api key」),
  ///   压平换行后截断(气泡内完整展示,不再挤底部提示条),让用户第一眼
  ///   知道该改哪个配置,而不是笼统的「请求失败」。
  static String _friendlyError(Object e) {
    if (e is TimeoutException) return '请求超时,请检查网络或稍后重试';
    var text = e.toString();
    final idx = text.indexOf(': ');
    if (idx > 0) text = text.substring(idx + 2);
    text = text.replaceAll('\n', ' ').trim();
    if (text.length > 600) text = '${text.substring(0, 600)}…';
    return 'AI 请求失败:$text';
  }
}

/// 思维链折叠块(推理模型):灰色小字 + 默认收起,点击「思考过程」展开全文。
/// 只展示,不参与复制/翻译等操作(操作针对正文)。
class _ThinkingBlock extends StatefulWidget {
  final String text;
  const _ThinkingBlock({required this.text});

  @override
  State<_ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<_ThinkingBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final text = widget.text.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.line.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.psychology_alt_outlined,
                      size: 13, color: AppColors.textSub),
                  const SizedBox(width: 4),
                  Text(
                    '思考过程',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSub,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    _expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 14,
                    color: AppColors.textSub,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                text,
                style: TextStyle(
                    fontSize: 11, height: 1.5, color: AppColors.textSub),
              ),
            ),
        ],
      ),
    );
  }
}
