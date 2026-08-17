import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:student_workbench/core/data/daily_content.dart';
import 'package:student_workbench/core/data/english_content.dart';
import 'package:student_workbench/features/english/models/english_fav.dart';
import 'package:student_workbench/features/coins/services/coin_service.dart';
import 'package:student_workbench/features/english/services/english_service.dart';
import 'package:student_workbench/core/theme.dart';
import 'package:student_workbench/core/utils/dates.dart';
import 'package:student_workbench/core/widgets/frosted_snack.dart';

/// 英文积累:每日一句 / 每日单词 / 每日阅读 / 每日写作提示 + 收藏 + 学习打卡领金币
class EnglishPage extends StatefulWidget {
  const EnglishPage({super.key});

  @override
  State<EnglishPage> createState() => _EnglishPageState();
}

class _EnglishPageState extends State<EnglishPage> {
  final EnglishService _service = EnglishService();
  final FlutterTts _tts = FlutterTts();
  final String _date = todayStr();

  late ({String en, String zh}) _quote;
  List<({String w, String p, String m})> _words = [];
  late ({String title, String text}) _reading;
  late String _writing;

  List<EnglishFav> _favs = [];
  Set<String> _favKeys = {}; // 'type:content' 快速判断
  bool _loading = true;
  bool _checkinDone = false;

  @override
  void initState() {
    super.initState();
    _init();
    _initTts();
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.5);
    } catch (_) {}
  }

  Future<void> _speak(String text) async {
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> _init() async {
    final favs = await _service.favs();
    final checkin = await CoinService.instance.earnedOfType(_date, 'english');
    if (!mounted) return;
    setState(() {
      _quote = DailyContent.englishFor(DateTime.now());
      _words = EnglishContent.wordsFor(_date);
      _reading = EnglishContent.readingFor(_date);
      _writing = EnglishContent.writingFor(_date);
      _favs = favs;
      _favKeys = favs.map((f) => '${f.type}:${f.content}').toSet();
      _checkinDone = checkin > 0;
      _loading = false;
    });
  }

  Future<void> _toggle(String type, String title, String content) async {
    final nowFav = await _service.toggle(type, title, content);
    if (!mounted) return;
    final key = '$type:$content';
    setState(() {
      if (nowFav) {
        _favKeys.add(key);
        _favs.insert(
            0,
            EnglishFav(
                type: type,
                title: title,
                content: content,
                createdAt: DateTime.now().millisecondsSinceEpoch));
      } else {
        _favKeys.remove(key);
        _favs.removeWhere((f) => f.type == type && f.content == content);
      }
    });
    _showSnack(nowFav ? '已收藏' : '已取消收藏');
  }

  Future<void> _checkin() async {
    if (_checkinDone) {
      _showSnack('今日已打卡,明天再来吧');
      return;
    }
    final coin = await CoinService.instance.rewardEnglish(_date);
    if (!mounted) return;
    if (coin > 0) {
      setState(() => _checkinDone = true);
      _showSnack('学习打卡成功,金币 +$coin');
    } else {
      _showSnack('今日已达金币上限,已记录打卡');
      setState(() => _checkinDone = true);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    showFrostedSnack(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('英文积累'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '今日'),
              Tab(text: '收藏'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [_buildToday(), _buildFavs()],
              ),
      ),
    );
  }

  // ---------- 今日 ----------
  Widget _buildToday() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        _sectionCard(
          title: '每日一句',
          onStar: () => _toggle('quote', '每日一句', _quote.en),
          onSpeak: () => _speak(_quote.en),
          starred: _favKeys.contains('quote:${_quote.en}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _quote.en,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, height: 1.5),
              ),
              const SizedBox(height: 6),
              Text(
                _quote.zh,
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSub),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          title: '每日单词',
          onStar: null,
          starred: false,
          child: Column(
            children: [
              for (final w in _words)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${w.w}  ${w.p}',
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              w.m,
                              style: TextStyle(
                                  fontSize: 12, color: AppColors.textSub),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => _speak(w.w),
                        icon: Icon(Icons.volume_up_rounded,
                            size: 20, color: AppColors.textSub),
                        tooltip: '朗读',
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        onPressed: () =>
                            _toggle('word', w.w, '${w.w} ${w.m}'),
                        icon: Icon(
                          _favKeys.contains('word:${w.w} ${w.m}')
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 20,
                          color: _favKeys.contains('word:${w.w} ${w.m}')
                              ? const Color(0xFFF9A825)
                              : AppColors.textSub,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          title: '每日阅读',
          onStar: () => _toggle('read', _reading.title, _reading.text),
          starred: _favKeys.contains('read:${_reading.text}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _reading.title,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                _reading.text,
                style: TextStyle(
                    fontSize: 13, color: AppColors.textSub, height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          title: '每日写作提示',
          onStar: () => _toggle('write', '每日写作提示', _writing),
          starred: _favKeys.contains('write:$_writing'),
          child: Text(
            _writing,
            style: const TextStyle(fontSize: 13, height: 1.6),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _checkin,
          icon: Icon(
              _checkinDone
                  ? Icons.check_circle_rounded
                  : Icons.task_alt_rounded,
              size: 20),
          label: Text(_checkinDone ? '今日已打卡' : '今日学习完成打卡'),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            '完成打卡 +2 金币,每日一次',
            style: TextStyle(fontSize: 12, color: AppColors.textSub),
          ),
        ),
      ],
    );
  }

  // ---------- 收藏 ----------
  Widget _buildFavs() {
    if (_favs.isEmpty) {
      return Center(
        child: Text('还没有收藏内容,去「今日」收藏优质内容吧',
            style: TextStyle(color: AppColors.textSub)),
      );
    }
    const typeLabels = {
      'quote': '每日一句',
      'word': '单词',
      'read': '每日阅读',
      'write': '写作提示',
    };
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      itemCount: _favs.length,
      itemBuilder: (context, i) {
        final f = _favs[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        typeLabels[f.type] ?? f.type,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSub),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        f.type == 'word'
                            ? '${f.title}  ${f.content}'
                            : f.title.isEmpty
                                ? f.content
                                : '${f.title}\n${f.content}',
                        style: const TextStyle(fontSize: 13, height: 1.5),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () =>
                      _toggle(f.type, f.title, f.content),
                  icon: const Icon(Icons.star_rounded,
                      size: 20, color: Color(0xFFF9A825)),
                  tooltip: '取消收藏',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------- 组件 ----------
  Widget _sectionCard({
    required String title,
    required Widget child,
    VoidCallback? onStar,
    VoidCallback? onSpeak,
    required bool starred,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMain),
                  ),
                ),
                if (onSpeak != null)
                  IconButton(
                    onPressed: onSpeak,
                    icon: Icon(Icons.volume_up_rounded,
                        size: 20, color: AppColors.textSub),
                    tooltip: '朗读',
                    visualDensity: VisualDensity.compact,
                  ),
                if (onStar != null)
                  IconButton(
                    onPressed: onStar,
                    icon: Icon(
                      starred
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      size: 20,
                      color: starred
                          ? const Color(0xFFF9A825)
                          : AppColors.textSub,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            child,
          ],
        ),
      ),
    );
  }
}
