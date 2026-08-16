import 'package:flutter/material.dart';

import '../data/wish_content.dart';
import '../models/coin_record.dart';
import '../models/wish.dart';
import '../services/coin_service.dart';
import '../services/wish_service.dart';
import '../theme.dart';
import '../utils/dates.dart';
import '../widgets/frosted_snack.dart';

/// 金币中心:心愿清单兑换 + 收支历史
class CoinCenterPage extends StatelessWidget {
  const CoinCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('金币中心'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '心愿清单'),
              Tab(text: '收支记录'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _WishTab(),
            _RecordTab(),
          ],
        ),
      ),
    );
  }
}

/// 心愿清单
class _WishTab extends StatefulWidget {
  const _WishTab();

  @override
  State<_WishTab> createState() => _WishTabState();
}

class _WishTabState extends State<_WishTab> {
  final WishService _wishService = WishService();

  bool _loading = true;
  List<Wish> _wishes = [];
  int _balance = 0;
  int _todayEarned = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final date = todayStr();
    final results = await Future.wait<Object>([
      _wishService.wishes(),
      CoinService.instance.balance(),
      CoinService.instance.earnedToday(date),
    ]);
    if (!mounted) return;
    setState(() {
      _wishes = results[0] as List<Wish>;
      _balance = results[1] as int;
      _todayEarned = results[2] as int;
      _loading = false;
    });
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    showFrostedSnack(context, msg);
  }

  Future<void> _addWish() async {
    final titleCtrl = TextEditingController();
    final costCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加心愿'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              autofocus: true,
              maxLength: 20,
              decoration: const InputDecoration(
                labelText: '心愿名称',
                hintText: '想要什么?',
                counterText: '',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: costCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '需要金币(枚)',
                hintText: '如 10',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (result != true || !mounted) return;
    final title = titleCtrl.text.trim();
    final cost = int.tryParse(costCtrl.text.trim());
    if (title.isEmpty || cost == null || cost <= 0) {
      _showSnack('请填写心愿名称和有效金币数');
      return;
    }
    await _wishService.addWish(title: title, cost: cost);
    await _load();
  }

  /// 随机添加一个系统心愿(排除已许过的)
  Future<void> _addRandomWish() async {
    final existing = _wishes.map((w) => w.title).toSet();
    final pick = WishContent.randomWish(existing);
    if (pick == null) {
      _showSnack('心愿池都许过啦,试试自定义添加');
      return;
    }
    await _wishService.addWish(title: pick.title, cost: pick.cost);
    await _load();
    _showSnack('已添加随机心愿:${pick.title}');
  }

  Future<void> _redeem(Wish wish) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认兑换'),
        content: Text('用 ${wish.cost} 枚金币兑换「${wish.title}」?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('再想想'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认兑换'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final ok = await CoinService.instance.redeemWish(wish, todayStr());
    await _load();
    if (ok) {
      _showSnack('兑换成功!');
    } else {
      _showSnack('金币不足,继续加油攒金币吧~');
    }
  }

  /// 删除心愿:删除前二次确认(避免误删)
  Future<void> _deleteWish(Wish wish) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除心愿'),
        content: Text('确定删除「${wish.title}」?删除后不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFE53935)),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await _wishService.deleteWish(wish.id!);
    await _load();
    _showSnack('已删除心愿');
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primaryLight, AppColors.primary],
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.stars_rounded,
                        color: Colors.white, size: 34),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('当前金币余额',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFFE3F4FF))),
                        Text(
                          '$_balance 枚',
                          style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Colors.white),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      '今日已赚 $_todayEarned/${CoinService.dailyCap}',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFFE3F4FF)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: AppColors.card,
                        foregroundColor: AppColors.primaryDark,
                        side: BorderSide(color: AppColors.primary),
                      ),
                      onPressed: _addWish,
                      icon: const Icon(Icons.add_rounded, size: 20),
                      label: const Text('添加心愿'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: AppColors.card,
                        foregroundColor: AppColors.primaryDark,
                        side: BorderSide(color: AppColors.primary),
                      ),
                      onPressed: _addRandomWish,
                      icon: const Icon(Icons.casino_rounded, size: 20),
                      label: const Text('随机心愿'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_wishes.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: Text('还没有心愿,许一个愿吧~',
                        style: TextStyle(color: AppColors.textSub)),
                  ),
                )
              else
                for (final wish in _wishes) _wishTile(wish),
            ],
          );
  }

  Widget _wishTile(Wish wish) {
    final enough = _balance >= wish.cost;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3D6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.redeem_rounded,
                  color: Color(0xFFFFB300), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    wish.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: wish.redeemed
                          ? AppColors.textSub
                          : AppColors.textMain,
                      decoration:
                          wish.redeemed ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '需要 ${wish.cost} 金币',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSub),
                  ),
                ],
              ),
            ),
            if (wish.redeemed)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F6EC),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('已兑换',
                    style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF2E9E5B),
                        fontWeight: FontWeight.w600)),
              )
            else
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(72, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  backgroundColor:
                      enough ? AppColors.primary : const Color(0xFFCBD8E3),
                ),
                onPressed: enough ? () => _redeem(wish) : null,
                child: const Text('兑换'),
              ),
            IconButton(
              onPressed: () => _deleteWish(wish),
              icon: Icon(Icons.delete_outline_rounded,
                  size: 20, color: AppColors.textSub),
              tooltip: '删除心愿',
            ),
          ],
        ),
      ),
    );
  }
}

/// 收支记录
class _RecordTab extends StatefulWidget {
  const _RecordTab();

  @override
  State<_RecordTab> createState() => _RecordTabState();
}

class _RecordTabState extends State<_RecordTab> {
  List<CoinRecord> _records = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final records = await CoinService.instance.records();
    if (!mounted) return;
    setState(() {
      _records = records;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : _records.isEmpty
            ? Center(
                child: Text('还没有收支记录,快去完成今日任务吧~',
                    style: TextStyle(color: AppColors.textSub)),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                itemCount: _records.length,
                itemBuilder: (context, i) {
                  final r = _records[i];
                  final (icon, color) = switch (r.type) {
                    'task' => (Icons.task_alt_rounded, const Color(0xFF2E9E5B)),
                    'bonus' => (Icons.celebration_rounded, const Color(0xFFFF9800)),
                    'redeem' => (Icons.redeem_rounded, const Color(0xFFEF5350)),
                    _ => (Icons.stars_rounded, AppColors.primary),
                  };
                  final positive = r.amount > 0;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(icon, color: color, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.reason,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  dateTimeLabel(r.createdAt),
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textSub),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${positive ? '+' : ''}${r.amount}',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: positive
                                  ? const Color(0xFF2E9E5B)
                                  : const Color(0xFFEF5350),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
  }
}
