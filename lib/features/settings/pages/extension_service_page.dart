import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:chronos/routes.dart';
import 'package:chronos/core/services/app_log.dart';
import 'package:chronos/core/services/key_store.dart';
import 'package:chronos/core/theme.dart';
import 'package:chronos/core/widgets/frosted_snack.dart';
import 'package:chronos/core/widgets/section_card.dart';
import 'package:chronos/core/widgets/status_views.dart';
import 'package:chronos/features/chat/services/nocturne_service.dart';

/// 外置记忆服务页(隐藏入口):配置用户自部署的 Nocturne Memory Core
/// (Ombre Brain 二改项目,MCP 长期记忆服务)。
/// 入口:系统设置或侧边栏的 Chronos 图标连点 7 下 → 输入 6 位数字密码。
/// 与「系统设置 → API 配置 → 外置记忆」字段一致,这里提供连通性测试。
class ExtensionServicePage extends StatefulWidget {
  const ExtensionServicePage({super.key});

  @override
  State<ExtensionServicePage> createState() => _ExtensionServicePageState();
}

class _ExtensionServicePageState extends State<ExtensionServicePage> {
  final TextEditingController _urlCtrl = TextEditingController();
  final TextEditingController _tokenCtrl = TextEditingController();
  bool _revealToken = false;
  bool _loading = true;
  String? _loadError; // 配置读取失败(渲染 ErrorView + 重试)
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final url = await KeyStore.instance.get(KeyStore.nocturneUrl);
      final token = await KeyStore.instance.get(KeyStore.nocturneToken);
      if (!mounted) return;
      setState(() {
        _urlCtrl.text = url;
        _tokenCtrl.text = token;
        _loading = false;
        _loadError = null;
      });
    } catch (e) {
      AppLog.instance.e('外置记忆配置读取失败:$e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '配置读取失败,请重试';
      });
    }
  }

  Future<void> _saveConfig() async {
    await KeyStore.instance.set(KeyStore.nocturneUrl, _urlCtrl.text);
    await KeyStore.instance.set(KeyStore.nocturneToken, _tokenCtrl.text);
    if (!mounted) return;
    showFrostedSnack(context, '外置记忆配置已保存(仅存本机)');
  }

  Future<void> _test() async {
    if (_testing) return;
    await _saveConfig();
    setState(() => _testing = true);
    final ok = await NocturneService.instance.probe();
    if (!mounted) return;
    setState(() => _testing = false);
    showFrostedSnack(
        context, ok ? '连接成功,外置记忆服务可用' : '连接失败,请检查地址 / token / 服务器状态');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('外置记忆服务')),
      body: _loadError != null
          ? ErrorView(
              message: _loadError!,
              onRetry: () {
                setState(() {
                  _loadError = null;
                  _loading = true;
                });
                _load();
              },
            )
          : _loading
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
                    '连接自部署的 Nocturne Memory Core(MCP 长期记忆服务),'
                    '记忆读写额外走外置库;不可用时自动回退本机记忆,不影响聊天。',
                    style: TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: AppColors.primaryDark),
                  ),
                ),
                const SizedBox(height: 14),
                SectionCard(
                  title: 'Nocturne 连接',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _urlCtrl,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: const InputDecoration(
                          labelText: '服务地址',
                          hintText: 'http://host:8000/mcp',
                          helperText: 'Streamable HTTP 端点',
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _tokenCtrl,
                        obscureText: !_revealToken,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: 'Bearer token',
                          hintText: '访问鉴权 token',
                          isDense: true,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _revealToken
                                  ? Icons.visibility_off_rounded
                                  : Icons.visibility_rounded,
                              size: 18,
                              color: AppColors.textSub,
                            ),
                            onPressed: () =>
                                setState(() => _revealToken = !_revealToken),
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
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _testing ? null : _test,
                          icon: _testing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.wifi_tethering_rounded,
                                  size: 18),
                          label: Text(_testing ? '正在测试…' : '测试连接'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// 隐藏入口辅助:Chronos 图标连点计数器 + 6 位密码校验 → 进外置记忆服务页。
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
        title: const Text('外置记忆服务'),
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
      AppRoutes.push(context, const ExtensionServicePage());
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
