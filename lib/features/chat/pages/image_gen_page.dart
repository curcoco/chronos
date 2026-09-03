import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:chronos/core/services/ai_provider.dart';
import 'package:chronos/core/services/app_log.dart';
import 'package:chronos/core/services/key_store.dart';
import 'package:chronos/core/theme.dart';
import 'package:chronos/core/widgets/app_text_field.dart';
import 'package:chronos/core/widgets/frosted_snack.dart';

/// 一个可选生图模型(提供商|模型 或 独立 key_store 配置)。
class _ImgModelOption {
  final String ref; // "providerId|modelId" 或 "standalone"
  final String label;
  const _ImgModelOption(this.ref, this.label);
}

/// 已生成的图片:解码结果 + 持久化到 chat_imgs/ 的本地路径。
class _GenImage {
  final ImageGenResult result;
  final String path;
  _GenImage(this.result, this.path);
}

/// 生图工作台:输入提示词(可带参考底图/尺寸/清晰度/张数/风格)→ 调生图模型
/// → 预览 → 勾选发到聊天。产物从聊天输入栏「生成图片」按钮进入,生成图随消息落库。
class ImageGenPage extends StatefulWidget {
  const ImageGenPage({super.key});

  @override
  State<ImageGenPage> createState() => _ImageGenPageState();
}

class _ImageGenPageState extends State<ImageGenPage> {
  final TextEditingController _prompt = TextEditingController();
  final ScrollController _scroll = ScrollController();

  final List<_ImgModelOption> _models = [];
  _ImgModelOption? _selectedModel;
  String _modelErr = '';

  String? _refImagePath;
  String? _refImageBase64;
  String? _size;
  String? _quality;
  int _count = 1;
  String? _style;

  bool _generating = false;
  String? _error;
  List<_GenImage> _results = [];
  final Set<int> _selected = {};
  int _saveSeq = 0;

  @override
  void initState() {
    super.initState();
    _initModels();
  }

  @override
  void dispose() {
    _prompt.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 加载可选生图模型:先取多提供商(每个提供商的所有模型),再取 API 配置的
  /// 独立生图模型(兜底);按已保存的引用 [KeyStore.imageGenRef] 恢复选择。
  Future<void> _initModels() async {
    final providers = await AiProviders.load();
    final options = <_ImgModelOption>[];
    for (final pr in providers) {
      if (!pr.enabled) continue;
      for (final m in pr.models) {
        if (m.isEmpty) continue;
        options.add(_ImgModelOption('${pr.id}|$m', '${pr.name} · $m'));
      }
    }
    final standaloneModel = await KeyStore.instance.get(KeyStore.imageGenModel);
    if (standaloneModel.isNotEmpty) {
      options.add(_ImgModelOption('standalone', '独立设置 · $standaloneModel'));
    }
    final savedRef = await KeyStore.instance.get(KeyStore.imageGenRef);
    _ImgModelOption? selected;
    if (savedRef.isNotEmpty) {
      for (final o in options) {
        if (o.ref == savedRef) {
          selected = o;
          break;
        }
      }
    }
    if (selected == null && options.isNotEmpty) {
      final one = savedRef == 'standalone';
      selected = one
          ? options.lastWhere((o) => o.ref == 'standalone',
              orElse: () => options.first)
          : options.first;
    }
    if (!mounted) return;
    setState(() {
      _models
        ..clear()
        ..addAll(options);
      _selectedModel = selected;
      if (options.isEmpty) {
        _modelErr = providers.isEmpty
            ? '未配置生图模型,请到「设置 → API 配置」填写,或在「设置 → 模型与服务」添加提供商'
            : '未配置生图模型,请到「设置 → API 配置」填写';
      }
    });
  }

  Future<({String baseUrl, String apiKey, String model})?> _resolveModel()
      async {
    final sel = _selectedModel;
    if (sel == null) return null;
    if (sel.ref == 'standalone') {
      final u = await KeyStore.instance.get(KeyStore.imageGenUrl);
      final k = await KeyStore.instance.get(KeyStore.imageGenKey);
      final m = await KeyStore.instance.get(KeyStore.imageGenModel);
      if (u.isEmpty || k.isEmpty || m.isEmpty) {
        _modelErr = '生图模型未配置,请到「设置 → API 配置」填写';
        return null;
      }
      return (baseUrl: u, apiKey: k, model: m);
    }
    final ep = await AiProviders.resolve(sel.ref);
    if (ep == null) {
      _modelErr = '所选生图模型未配置或已失效,请重新选择';
      return null;
    }
    return ep;
  }

  Future<void> _pickRefImage() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      final bytes = await File(picked.path).readAsBytes();
      setState(() {
        _refImagePath = picked.path;
        _refImageBase64 = base64Encode(bytes);
      });
    } catch (_) {
      if (!mounted) return;
      showFrostedSnack(context, '选择参考图失败,请重试');
    }
  }

  Future<void> _generate() async {
    final prompt = _prompt.text.trim();
    if (prompt.isEmpty) {
      showFrostedSnack(context, '请先描述你想生成的画面');
      return;
    }
    if (_generating) return;
    final ep = await _resolveModel();
    if (!mounted) return;
    if (ep == null) {
      showFrostedSnack(context, _modelErr.isEmpty ? '未配置生图模型' : _modelErr);
      return;
    }
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final options = ImageGenOptions(
        model: ep.model,
        prompt: prompt,
        size: _size,
        quality: _quality,
        n: _count,
        style: _style,
        imageBase64: _refImageBase64,
      );
      final results = await AiProviders.generateImage(
        url: ep.baseUrl,
        apiKey: ep.apiKey,
        options: options,
      );
      if (!mounted) return;
      final imgs = <_GenImage>[];
      for (final r in results) {
        imgs.add(_GenImage(r, await _persist(r)));
      }
      if (!mounted) return;
      setState(() {
        _results = imgs;
        _selected.clear();
      });
      _scrollDown();
    } on ImageGenException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      AppLog.instance.e('生图失败:$e');
      if (!mounted) return;
      setState(() => _error = '生成图片失败,请稍后重试($e)');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<String> _persist(ImageGenResult r) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'chat_imgs'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final dest = p.join(dir.path,
        'gen_${DateTime.now().millisecondsSinceEpoch}_${_saveSeq++}.${r.ext}');
    await File(dest).writeAsBytes(r.bytes);
    return dest;
  }

  /// 以某张图为底图重新生成(图生图/变体)。
  Future<void> _varyFrom(_GenImage img) async {
    final bytes = img.result.bytes;
    setState(() {
      _refImageBase64 = base64Encode(bytes);
      _refImagePath = img.path;
    });
    await _generate();
  }

  Future<void> _saveToGallery(String path) async {
    try {
      await Gal.putImage(path);
      if (!mounted) return;
      showFrostedSnack(context, '已保存到相册');
    } catch (e) {
      AppLog.instance.e('保存生图到相册失败:$e');
      if (!mounted) return;
      showFrostedSnack(context, '保存失败,请重试');
    }
  }

  void _sendSelected() {
    if (_selected.isEmpty) return;
    final paths = <String>[];
    for (final i in _selected) {
      if (i >= 0 && i < _results.length) paths.add(_results[i].path);
    }
    if (paths.isEmpty) return;
    Navigator.of(context).pop(paths);
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('生成图片')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _modelCard(),
                const SizedBox(height: 14),
                Text('提示词', style: TextStyle(fontSize: 13, color: AppColors.textSub)),
                const SizedBox(height: 6),
                AppTextField(
                  controller: _prompt,
                  minLines: 3,
                  maxLines: 6,
                  hintText: '描述你想生成的画面,越详细越好…',
                ),
                const SizedBox(height: 14),
                _refCard(),
                const SizedBox(height: 14),
                _optionCard('尺寸', {
                  null: '默认',
                  '1024x1024': '方形',
                  '1792x1024': '横屏',
                  '1024x1792': '竖屏',
                }, _size, (v) => setState(() => _size = v)),
                const SizedBox(height: 10),
                _optionCard('清晰度', {
                  null: '默认',
                  'standard': '标准',
                  'hd': '高清',
                }, _quality, (v) => setState(() => _quality = v)),
                const SizedBox(height: 10),
                _countCard(),
                const SizedBox(height: 10),
                _optionCard('风格', {
                  null: '默认',
                  'vivid': '鲜活',
                  'natural': '自然',
                }, _style, (v) => setState(() => _style = v)),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _generating ? null : _generate,
                  icon: _generating
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(_generating ? '生成中…' : '生成图片'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDECEA),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFC62828),
                          height: 1.5),
                    ),
                  ),
                ],
                if (_results.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('生成结果(${_results.length})',
                      style:
                          TextStyle(fontSize: 13, color: AppColors.textSub)),
                  const SizedBox(height: 8),
                  _resultsGrid(),
                ],
              ],
            ),
          ),
          if (_results.isNotEmpty) _bottomBar(),
        ],
      ),
    );
  }

  Widget _modelCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: _models.isEmpty
          ? Text(_modelErr,
              style: TextStyle(fontSize: 12, color: AppColors.textSub))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('生图模型',
                    style: TextStyle(fontSize: 13, color: AppColors.textSub)),
                const SizedBox(height: 8),
                DropdownButtonHideUnderline(
                  child: DropdownButton<_ImgModelOption>(
                    value: _selectedModel,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(12),
                    items: [
                      for (final m in _models)
                        DropdownMenuItem(
                          value: m,
                          child: Text(m.label,
                              style: const TextStyle(fontSize: 14),
                              overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (m) {
                      setState(() => _selectedModel = m);
                      if (m != null) {
                        KeyStore.instance.set(KeyStore.imageGenRef, m.ref);
                      }
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _refCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('参考底图(图生图)',
                  style: TextStyle(fontSize: 13, color: AppColors.textSub)),
              const SizedBox(width: 6),
              Text('可选',
                  style: TextStyle(fontSize: 11, color: AppColors.textSub)),
            ],
          ),
          const SizedBox(height: 8),
          if (_refImagePath == null)
            OutlinedButton.icon(
              onPressed: _pickRefImage,
              icon: const Icon(Icons.add_photo_alternate_rounded, size: 18),
              label: const Text('选择参考图'),
            )
          else
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    File(_refImagePath!),
                    width: 56, height: 56, fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                        width: 56, height: 56, color: AppColors.line),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('已选底图,生成时作为图生图输入',
                      style: TextStyle(fontSize: 12, color: AppColors.textSub)),
                ),
                IconButton(
                  onPressed: () => setState(() {
                    _refImagePath = null;
                    _refImageBase64 = null;
                  }),
                  icon: const Icon(Icons.close_rounded,
                      size: 18, color: Colors.grey),
                  tooltip: '移除底图',
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _optionCard(String title, Map<String?, String> options, String? value,
      ValueChanged<String?> onPick) {
    final selected = value;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 13, color: AppColors.textSub)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final e in options.entries)
                ChoiceChip(
                  label: Text(e.value,
                      style: const TextStyle(fontSize: 12.5)),
                  selected: selected == e.key,
                  onSelected: (_) => onPick(e.key),
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    fontSize: 12.5,
                    color: selected == e.key
                        ? AppColors.onPrimarySoft
                        : AppColors.textSub,
                  ),
                  selectedColor: AppColors.primarySoft,
                  backgroundColor: AppColors.card,
                  side: BorderSide(
                      color: selected == e.key
                          ? AppColors.primaryDark
                          : AppColors.line),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _countCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('生成张数',
              style: TextStyle(fontSize: 13, color: AppColors.textSub)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final n in [1, 2, 3, 4])
                ChoiceChip(
                  label: Text('$n',
                      style: const TextStyle(fontSize: 12.5)),
                  selected: _count == n,
                  onSelected: (_) => setState(() => _count = n),
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    fontSize: 12.5,
                    color: _count == n
                        ? AppColors.onPrimarySoft
                        : AppColors.textSub,
                  ),
                  selectedColor: AppColors.primarySoft,
                  backgroundColor: AppColors.card,
                  side: BorderSide(
                      color: _count == n
                          ? AppColors.primaryDark
                          : AppColors.line),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _resultsGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1,
      ),
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final img = _results[i];
        final sel = _selected.contains(i);
        return Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: GestureDetector(
                  onTap: () => setState(() {
                    if (sel) {
                      _selected.remove(i);
                    } else {
                      _selected.add(i);
                    }
                  }),
                  child: Image.file(
                    File(img.path),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        Container(color: AppColors.line),
                  ),
                ),
              ),
            ),
            // 选中角标
            Positioned(
              top: 6, left: 6,
              child: Icon(
                sel ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                size: 20,
                color: sel ? AppColors.primaryDark : Colors.white,
              ),
            ),
            // 右下角操作菜单
            Positioned(
              bottom: 4, right: 4,
              child: Material(
                color: Colors.black45,
                shape: const CircleBorder(),
                child: PopupMenuButton<String>(
                  color: AppColors.card,
                  onSelected: (a) async {
                    if (a == 'vary') {
                      await _varyFrom(img);
                    } else if (a == 'save') {
                      await _saveToGallery(img.path);
                    } else if (a == 'send') {
                      Navigator.of(context).pop([img.path]);
                    }
                  },
                  icon: const Icon(Icons.more_horiz_rounded,
                      size: 18, color: Colors.white),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'send', child: Text('发到聊天')),
                    PopupMenuItem(
                        value: 'vary', child: Text('以此图为底图再生成')),
                    PopupMenuItem(
                        value: 'save', child: Text('保存到相册')),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _bottomBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border(top: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _selected.isEmpty
                    ? '点选图片,再发到聊天'
                    : '已选 ${_selected.length} 张',
                style: TextStyle(fontSize: 13, color: AppColors.textSub),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonal(
              onPressed: _selected.isEmpty ? null : _sendSelected,
              child: const Text('发到聊天'),
            ),
          ],
        ),
      ),
    );
  }
}
