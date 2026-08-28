import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'package:chronos/routes.dart';
import 'package:chronos/core/services/ai_provider.dart';
import 'package:chronos/core/services/app_log.dart';
import 'package:chronos/core/theme.dart';
import 'package:chronos/core/widgets/frosted_snack.dart';
import 'package:chronos/core/widgets/section_card.dart';
import 'package:chronos/features/chat/services/eleven_service.dart';
import 'package:chronos/features/chat/services/shopkeeper_store.dart';
import 'package:chronos/features/chat/services/tavily_service.dart';
import 'package:chronos/features/memory/pages/memory_page.dart';
import 'package:chronos/features/settings/pages/api_settings_page.dart';

/// 掌柜设置(聚合页):掌柜形象(名称/头像)、人物设定、记忆管理,
/// 以及默认模型 / 搜索服务 / 语音服务的配置入口。
/// 模型、搜索、语音的字段统一在「系统设置 → API 配置」填写,本页只做跳转,
/// 避免同一配置双入口互相覆盖。
class ShopkeeperSettingsPage extends StatefulWidget {
  const ShopkeeperSettingsPage({super.key});

  @override
  State<ShopkeeperSettingsPage> createState() => _ShopkeeperSettingsPageState();
}

class _ShopkeeperSettingsPageState extends State<ShopkeeperSettingsPage> {
  String _name = '';
  String _avatarPath = '';
  String _persona = '';
  String _modelSummary = '';
  String _searchStatus = '';
  String _voiceStatus = '';
  int _contextSize = ShopkeeperStore.contextDefault;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final store = ShopkeeperStore.instance;
      final name = await store.name();
      final avatar = await store.avatarPath();
      final persona = await store.persona();
      final model = await _loadModelSummary();
      final search = await _searchSummary();
      final voice = await _voiceSummary();
      final contextSize = await store.contextSize();
      if (!mounted) return;
      setState(() {
        _name = name;
        _avatarPath = avatar;
        _persona = persona;
        _modelSummary = model;
        _searchStatus = search;
        _voiceStatus = voice;
        _contextSize = contextSize;
      });
    } catch (e) {
      AppLog.instance.e('掌柜设置加载失败:$e');
    }
  }

  Future<String> _loadModelSummary() async {
    String modelName(String ref) {
      final r = ModelRef.parse(ref);
      return r == null ? '' : r.modelId;
    }

    final chatRef = await AiProviders.chatModelRef();
    final ocrRef = await AiProviders.ocrModelRef();
    final chat = modelName(chatRef);
    final ocr = modelName(ocrRef);
    return '聊天模型:${chat.isEmpty ? '未设置' : chat}\n'
        'OCR 模型:${ocr.isEmpty ? '未设置(默认模型不支持图片时不可用)' : ocr}';
  }

  Future<String> _searchSummary() async {
    final ok = await TavilyService.instance.isConfigured();
    return 'Tavily(默认)${ok ? ' · 已配置' : ' · 未配置,前往填写 Key'}';
  }

  Future<String> _voiceSummary() async {
    final ok = await ElevenService.instance.isConfigured();
    return 'elevenlabs${ok ? ' · 已配置' : ' · 未配置,前往填写 Key / 语音 ID'}';
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    showFrostedSnack(context, msg);
  }

  Future<void> _editName() async {
    final controller = TextEditingController(text: _name);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('掌柜名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(hintText: '如:阿闲 / 掌柜小铺'),
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
    if (result == null || !mounted) return;
    await ShopkeeperStore.instance.setName(result);
    if (!mounted) return;
    setState(() => _name = result);
    _showSnack(result.isEmpty ? '已清除掌柜名称' : '掌柜名称已更新');
  }

  /// 对话上下文长度:滑杆选择 10~800 条(更大上下文 = 更懂近期对话,
  /// 但也更耗 token)。实际发送还受 token 预算自动裁剪:超出预算的更早
  /// 部分自动压缩成摘要,不会撑爆模型上下文窗口。
  Future<void> _editContextSize() async {
    final min = ShopkeeperStore.contextMin;
    final max = ShopkeeperStore.contextMax;
    var value = _contextSize;
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('对话上下文长度'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '每次发给掌柜最近 $value 条消息。条数越大越「记得住」,'
                '消耗的 token 也越多;超出预算的更早部分会自动压缩成摘要,'
                '不会撑爆模型上下文。',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSub, height: 1.5),
              ),
              const SizedBox(height: 8),
              Slider(
                value: value.toDouble(),
                min: min.toDouble(),
                max: max.toDouble(),
                divisions: (max - min) ~/ 10,
                label: '$value 条',
                onChanged: (v) =>
                    setDialogState(() => value = v.round()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(value),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    await ShopkeeperStore.instance.setContextSize(result);
    if (!mounted) return;
    setState(() => _contextSize = result);
    _showSnack('对话上下文已设为最近 $result 条');
  }

  Future<void> _editAvatar() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('更换头像'),
              onTap: () => Navigator.of(sheetCtx).pop('pick'),
            ),
            if (_avatarPath.isNotEmpty)
              ListTile(
                leading: Icon(Icons.person_off_outlined,
                    color: AppColors.textSub),
                title: const Text('移除头像'),
                onTap: () => Navigator.of(sheetCtx).pop('remove'),
              ),
            const Divider(height: 1),
            ListTile(
              title: Center(
                child: Text('取消', style: TextStyle(color: AppColors.textSub)),
              ),
              onTap: () => Navigator.of(sheetCtx).pop(),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'pick':
        await _pickAvatar();
      case 'remove':
        await ShopkeeperStore.instance.setAvatarPath('');
        if (!mounted) return;
        setState(() => _avatarPath = '');
        _showSnack('已移除掌柜头像');
    }
  }

  Future<void> _pickAvatar() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 256,
      maxHeight: 256,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    try {
      // 存到应用文档目录(备份 zip 会带上,便于换机迁移)。
      final dir = await getApplicationDocumentsDirectory();
      final ext = picked.path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
      final dest = File('${dir.path}/shopkeeper_avatar.$ext');
      await File(picked.path).copy(dest.path);
      await ShopkeeperStore.instance.setAvatarPath(dest.path);
      if (!mounted) return;
      setState(() => _avatarPath = dest.path);
      _showSnack('掌柜头像已更新');
    } catch (_) {
      _showSnack('头像设置失败,请重试');
    }
  }

  Future<void> _editPersona() async {
    final controller = TextEditingController(text: _persona);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('人物设定'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 6,
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
    if (result == null || !mounted) return;
    if (result.isEmpty) {
      _showSnack('人设不能为空');
      return;
    }
    await ShopkeeperStore.instance.setPersona(result);
    if (!mounted) return;
    setState(() => _persona = result);
    _showSnack('人设已更新');
  }

  Future<void> _openApiSettings() async {
    await AppRoutes.push(context, const ApiSettingsPage());
    await _load(); // 返回后刷新模型/搜索/语音状态
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('掌柜设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          // ---------- 基础设定:掌柜形象 ----------
          SectionCard(
            title: '基础设定',
            child: Column(
              children: [
                Row(
                  children: [
                    _avatarWidget(),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _name.isEmpty ? '未命名掌柜' : _name,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textMain,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '名称与头像会显示在闲话铺',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.textSub),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _editAvatar,
                      icon: const Icon(Icons.photo_camera_outlined,
                          size: 20),
                      tooltip: '更换头像',
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.badge_outlined,
                      size: 20, color: AppColors.primaryDark),
                  title: const Text('掌柜名称',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    _name.isEmpty ? '未设置(默认不署名)' : _name,
                    style: TextStyle(fontSize: 11, color: AppColors.textSub),
                  ),
                  trailing: Icon(Icons.chevron_right_rounded,
                      size: 20, color: AppColors.textSub),
                  onTap: _editName,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // ---------- 人物设定 ----------
          SectionCard(
            title: '人物设定',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.psychology_rounded,
                  size: 20, color: AppColors.primaryDark),
              title: const Text('掌柜人设',
                  style:
                      TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              subtitle: Text(
                _persona.length > 40
                    ? '${_persona.substring(0, 40)}…'
                    : _persona,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: AppColors.textSub),
              ),
              trailing: Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.textSub),
              onTap: _editPersona,
            ),
          ),
          const SizedBox(height: 14),
          // ---------- 能力与记忆 ----------
          SectionCard(
            title: '能力与记忆',
            child: Column(
              children: [
                _jumpTile(
                  icon: Icons.memory_rounded,
                  title: '记忆管理',
                  subtitle: '本地长期记忆可查看/编辑;外置记忆(Nocturne MCP)'
                      '在「API 配置 → 外置记忆地址」填写后自动启用',
                  onTap: () =>
                      AppRoutes.push(context, const MemoryPage()),
                ),
                const Divider(height: 1),
                _jumpTile(
                  icon: Icons.format_list_numbered_rounded,
                  title: '对话上下文长度',
                  subtitle: '每次发给掌柜最近 $_contextSize 条消息'
                      '(超出 token 预算的自动压缩成摘要,不丢信息)',
                  onTap: _editContextSize,
                ),
                const Divider(height: 1),
                _jumpTile(
                  icon: Icons.smart_toy_outlined,
                  title: '默认模型',
                  subtitle: _modelSummary,
                  onTap: _openApiSettings,
                ),
                const Divider(height: 1),
                _jumpTile(
                  icon: Icons.travel_explore_rounded,
                  title: '搜索服务',
                  subtitle: _searchStatus,
                  onTap: _openApiSettings,
                ),
                const Divider(height: 1),
                _jumpTile(
                  icon: Icons.record_voice_over_outlined,
                  title: '语音服务',
                  subtitle: _voiceStatus,
                  onTap: _openApiSettings,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '模型、搜索、语音的具体配置在「系统设置 → API 配置」填写,'
            '密钥仅存本机。',
            style: TextStyle(fontSize: 12, color: AppColors.textSub, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _avatarWidget() {
    final path = _avatarPath;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.primaryLight,
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
      size: 26, color: AppColors.primaryDark);

  Widget _jumpTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 20, color: AppColors.primaryDark),
      title: Text(title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: TextStyle(fontSize: 11, color: AppColors.textSub)),
      trailing: Icon(Icons.chevron_right_rounded,
          size: 20, color: AppColors.textSub),
      onTap: onTap,
    );
  }
}
