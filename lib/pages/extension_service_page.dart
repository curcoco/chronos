import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/key_store.dart';
import '../theme.dart';
import '../widgets/frosted_snack.dart';
import '../widgets/section_card.dart';

/// 拓展服务页(隐藏入口):仅特定用户可用。
/// 入口:系统设置或侧边栏的 Chronos 图标连点 7 下 → 输入 6 位数字密码。
/// 在此填写 Supabase URL / anon Key 后,可开启「云端 AI 长期记忆」;
/// 开启后,零时闲话铺的 AI 长期记忆页才会出现「自动上传云端」模块。
class ExtensionServicePage extends StatefulWidget {
  const ExtensionServicePage({super.key});

  /// 云端记忆总开关的持久化键(记忆页据此决定是否显示自动上传模块)。
  static const String prefCloudMemoryEnabled = 'ext_cloud_memory_enabled';

  @override
  State<ExtensionServicePage> createState() => _ExtensionServicePageState();
}

class _ExtensionServicePageState extends State<ExtensionServicePage> {
  final TextEditingController _urlCtrl = TextEditingController();
  final TextEditingController _keyCtrl = TextEditingController();
  bool _revealKey = false;
  bool _cloudEnabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final url = await KeyStore.instance.get(KeyStore.supabaseUrl);
    final key = await KeyStore.instance.get(KeyStore.supabaseAnonKey);
    final prefs = await SharedPreferences.getInstance();
    final enabled =
        prefs.getBool(ExtensionServicePage.prefCloudMemoryEnabled) ?? false;
    if (!mounted) return;
    setState(() {
      _urlCtrl.text = url;
      _keyCtrl.text = key;
      _cloudEnabled = enabled;
      _loading = false;
    });
  }

  Future<void> _saveConfig() async {
    await KeyStore.instance.set(KeyStore.supabaseUrl, _urlCtrl.text);
    await KeyStore.instance.set(KeyStore.supabaseAnonKey, _keyCtrl.text);
    if (!mounted) return;
    showFrostedSnack(context, '云端配置已保存(仅存本机)');
  }

  Future<void> _toggleCloud(bool v) async {
    if (v) {
      // 开启前要求已填写 URL 与 Key
      if (_urlCtrl.text.trim().isEmpty || _keyCtrl.text.trim().isEmpty) {
        showFrostedSnack(context, '请先填写 Supabase 地址与 anon Key');
        return;
      }
      // 开启即把当前输入写入本机,确保记忆页可用
      await _saveConfig();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(ExtensionServicePage.prefCloudMemoryEnabled, v);
    if (!mounted) return;
    setState(() => _cloudEnabled = v);
    showFrostedSnack(
        context, v ? '已开启云端 AI 长期记忆服务' : '已关闭(记忆仍保留在本地)');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('拓展服务')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '云端 AI 长期记忆为进阶服务,仅面向特定用户开放。'
                    '填写自己的 Supabase 地址与 anon Key 后开启,'
                    '记忆将可跨设备同步。所有信息仅保存在本机。',
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: AppColors.primaryDark),
                  ),
                ),
                const SizedBox(height: 14),
                SectionCard(
                  title: 'Supabase 连接',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _urlCtrl,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: 'Supabase 地址',
                          hintText: 'https://….supabase.co',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _keyCtrl,
                        obscureText: !_revealKey,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: 'Supabase anon Key',
                          hintText: 'eyJ…(anon public key)',
                          isDense: true,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _revealKey
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              size: 18,
                              color: AppColors.textSub,
                            ),
                            onPressed: () =>
                                setState(() => _revealKey = !_revealKey),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _saveConfig,
                          icon: const Icon(Icons.save_rounded, size: 18),
                          label: const Text('保存配置'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SectionCard(
                  title: '云端 AI 长期记忆',
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '开启云端记忆服务',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textMain),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '开启后,可在 零时闲话铺 → AI 长期记忆 页看到'
                              '「自动上传云端」模块。',
                              style: TextStyle(
                                  fontSize: 12,
                                  height: 1.5,
                                  color: AppColors.textSub),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _cloudEnabled,
                        activeThumbColor: AppColors.primary,
                        onChanged: _toggleCloud,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// 隐藏入口辅助:Chronos 图标连点计数器 + 6 位密码校验 → 进拓展服务页。
/// 用法:把要连点的图标包进 [SecretUnlockTap]。
class SecretUnlockTap extends StatefulWidget {
  final Widget child;

  const SecretUnlockTap({super.key, required this.child});

  /// 客户端校验口令(轻量门槛,非高强度加密)。
  static const String _password = '642798';

  @override
  State<SecretUnlockTap> createState() => _SecretUnlockTapState();
}

class _SecretUnlockTapState extends State<SecretUnlockTap> {
  int _taps = 0;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  void _onTap() {
    final now = DateTime.now();
    // 连点需在 1.5s 内,否则计数重置
    if (now.difference(_last) > const Duration(milliseconds: 1500)) {
      _taps = 0;
    }
    _last = now;
    _taps++;
    if (_taps >= 7) {
      _taps = 0;
      _promptPassword();
    }
  }

  Future<void> _promptPassword() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('拓展服务'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            hintText: '输入 6 位数字密码',
            counterText: '',
          ),
          onSubmitted: (_) =>
              Navigator.of(dialogCtx).pop(ctrl.text == SecretUnlockTap._password),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx)
                .pop(ctrl.text == SecretUnlockTap._password),
            child: const Text('进入'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (ok == true) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ExtensionServicePage()),
      );
    } else if (ok == false) {
      showFrostedSnack(context, '密码不正确');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: widget.child,
    );
  }
}
