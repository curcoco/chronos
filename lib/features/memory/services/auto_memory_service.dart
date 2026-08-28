import 'package:chronos/features/memory/models/memory_item.dart';
import 'package:chronos/features/memory/services/memory_service.dart';

/// 一条记忆操作的执行结果(供 UI 汇报/调试)。
class AutoMemoryOpResult {
  final bool ok;
  final String label; // 简要标签,如「已写入档案」
  final String detail; // 详细内容(内容/新旧对比/失败原因)
  const AutoMemoryOpResult({
    required this.ok,
    required this.label,
    required this.detail,
  });
}

/// Auto Memory:AI 在对话回复正文里输出成对标签,系统截取并自主维护
/// 「关于用户的认知档案」(复用 memories 表,kind=画像/事实/摘要,source='auto')。
///
/// 标签格式(仿 InternalBeyond 思路,仅借鉴接口语义,Dart 重写):
/// - 新增:`<mem_create category="画像" importance="5">内容</mem_create>`
/// - 更新:`<mem_edit id="编号">新内容</mem_edit>`
/// - 删除:`<mem_delete id="编号"/>`
/// 规则:每轮最多执行 3 次;标签在被系统截取后从显示/落库文本中剥离,
/// 不会出现在给用户的正文里;仅允许操作 source='auto' 的档案条目。
class AutoMemoryService {
  AutoMemoryService._();
  static final AutoMemoryService instance = AutoMemoryService._();

  /// 每轮最多执行的记忆操作次数(InternalBeyond 同口径,防刷)。
  static const int maxOpsPerReply = 3;

  MemoryService get _memory => MemoryService.instance;

  /// 注入到对话 system prompt 的指令块:告诉掌柜它可以如何写档案。
  static const String instructionBlock = '【关于用户的长期记忆档案】\n'
      '你可以自主维护一份关于用户的认知档案。在正式回复正文中插入以下标签即可操作,'
      '标签会被系统自动执行并从界面移除(不会显示给用户):\n'
      '- 新增:<mem_create category="画像" importance="5">记忆内容</mem_create>\n'
      '- 更新:<mem_edit id="编号">新内容</mem_edit>\n'
      '- 删除:<mem_delete id="编号"/>\n'
      '参数说明:category 可选 画像/事实/摘要(默认画像);importance 1-10(默认5);'
      'id 为已注入档案的编号(形如 #5)。\n'
      '规则:每条回复最多执行 3 次记忆操作;只记录/修改/删除关于用户本人、长期成立的信息;'
      '过时或被用户纠正的信息要及时修正或删除;标签不要写进给用户看的正文表述里。';

  /// 解析并执行回复正文中的记忆标签。返回:
  /// - cleaned:去掉全部标签后的正文(用于显示与落库);
  /// - results:依次执行的每个操作结果。
  /// 无标签时原样返回(不加额外开销)。
  Future<({String cleaned, List<AutoMemoryOpResult> results})> processReply(
      String text) async {
    if (text.isEmpty) return (cleaned: text, results: <AutoMemoryOpResult>[]);
    // 同时匹配成对标签(create/edit)与自闭合标签(delete)。
    final re = RegExp(
      r'<mem_(create|edit|delete)\b([^>]*?)(/>|>(.*?)</mem_(?:create|edit|delete)>)',
      caseSensitive: false,
      dotAll: true,
    );
    final matches = re.allMatches(text).toList();
    if (matches.isEmpty) {
      return (cleaned: text, results: <AutoMemoryOpResult>[]);
    }

    var ops = 0;
    final results = <AutoMemoryOpResult>[];
    final buf = StringBuffer();
    var last = 0;
    for (final m in matches) {
      final kind = m.group(1)!.toLowerCase();
      final attrs = _attrs(m.group(2) ?? '');
      final content = (m.group(4) ?? '').trim();
      if (ops < maxOpsPerReply) {
        final res = await _execute(kind, attrs, content);
        if (res != null) {
          ops++;
          results.add(res);
        }
      } else {
        results.add(const AutoMemoryOpResult(
            ok: false,
            label: '记忆操作已跳过',
            detail: '每轮最多执行 3 次,多余的未执行'));
      }
      buf.write(text.substring(last, m.start));
      last = m.end;
    }
    buf.write(text.substring(last));
    return (cleaned: buf.toString(), results: results);
  }

  /// 解析标签属性:提取 key="value" 键值对。
  Map<String, String> _attrs(String raw) {
    final m = <String, String>{};
    for (final mm in RegExp(r'(\w+)="([^"]*)"').allMatches(raw)) {
      m[mm.group(1)!] = mm.group(2)!;
    }
    return m;
  }

  Future<AutoMemoryOpResult?> _execute(
      String kind, Map<String, String> attrs, String content) async {
    switch (kind) {
      case 'create':
        return _create(attrs, content);
      case 'edit':
        return _edit(attrs, content);
      case 'delete':
        return _delete(attrs);
    }
    return null;
  }

  Future<AutoMemoryOpResult> _create(
      Map<String, String> attrs, String content) async {
    if (content.isEmpty) {
      return const AutoMemoryOpResult(
          ok: false, label: '记忆写入失败', detail: '内容为空');
    }
    final id = await _memory.add(
      kind: _kindFromCategory(attrs['category']),
      content: content,
      source: 'auto',
      importance: int.tryParse(attrs['importance'] ?? '') ?? 5,
      domain: _blankToNull(attrs['category']),
      tags: _parseTags(attrs['tags'] ?? ''),
    );
    if (id == 0) {
      return const AutoMemoryOpResult(
          ok: false, label: '记忆写入未执行', detail: '内容与已有档案重复');
    }
    return AutoMemoryOpResult(ok: true, label: '已写入档案', detail: content);
  }

  Future<AutoMemoryOpResult> _edit(
      Map<String, String> attrs, String content) async {
    final id = int.tryParse(attrs['id'] ?? '');
    if (id == null) {
      return const AutoMemoryOpResult(
          ok: false, label: '记忆更新失败', detail: '缺少 id');
    }
    if (content.isEmpty) {
      return const AutoMemoryOpResult(
          ok: false, label: '记忆更新失败', detail: '内容为空');
    }
    final target = await _findAuto(id);
    if (target == null) {
      return AutoMemoryOpResult(
          ok: false, label: '记忆更新失败', detail: '未找到该档案(id=$id)');
    }
    await _memory.update(id, content);
    return AutoMemoryOpResult(
        ok: true,
        label: '已更新档案',
        detail: '原:${target.content}\n新:$content');
  }

  Future<AutoMemoryOpResult> _delete(Map<String, String> attrs) async {
    final id = int.tryParse(attrs['id'] ?? '');
    if (id == null) {
      return const AutoMemoryOpResult(
          ok: false, label: '记忆删除失败', detail: '缺少 id');
    }
    final target = await _findAuto(id);
    if (target == null) {
      return AutoMemoryOpResult(
          ok: false, label: '记忆删除失败', detail: '未找到该档案(id=$id)');
    }
    await _memory.delete(id);
    return AutoMemoryOpResult(ok: true, label: '已删除档案', detail: target.content);
  }

  /// 查找一条由 AI 自主维护的档案(id 匹配且 source=='auto',避免误改用户手动/提炼记忆)。
  Future<MemoryItem?> _findAuto(int id) async {
    final items = await _memory.list();
    for (final m in items) {
      if (m.id == id && m.source == 'auto') return m;
    }
    return null;
  }

  /// category → kind:画像/事实/摘要(或英文别名),未知默认画像。
  static String _kindFromCategory(String? category) {
    final c = (category ?? '').trim();
    if (c == '事实' || c == 'fact') return 'fact';
    if (c == '摘要' || c == 'summary') return 'summary';
    return 'profile';
  }

  /// 标签参数(可选):逗号/竖线/空白分隔,去重去空。
  static List<String> _parseTags(String raw) {
    final parts = raw
        .split(RegExp(r'[,，|、\s]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.toSet().toList();
  }

  static String? _blankToNull(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();
}
