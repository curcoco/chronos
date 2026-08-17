import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'package:student_workbench/features/ledger/models/ledger_txn.dart';
import 'package:student_workbench/core/services/db_helper.dart';

/// 生活记账服务:流水 + 设置(起始余额 / 预算 / 自定义分类),纯本地
class LedgerService {
  LedgerService();
  DbHelper get _db => DbHelper.instance;

  static const List<String> presetExpense =
      ['餐饮', '交通', '购物', '学习', '娱乐', '医疗', '其他'];
  static const List<String> presetIncome = ['零花钱', '兼职', '红包', '其他'];

  // ---------- 流水 ----------
  Future<List<LedgerTxn>> txns() async {
    final db = await _db.database;
    final rows = await db.query('ledger_txns', orderBy: 'created_at DESC');
    return rows.map(LedgerTxn.fromMap).toList();
  }

  Future<void> addTxn({
    required String type,
    required double amount,
    required String category,
    required String note,
    required String date,
  }) async {
    final db = await _db.database;
    await db.insert('ledger_txns', LedgerTxn(
      type: type,
      amount: amount,
      category: category,
      note: note,
      date: date,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    ).toMap());
  }

  // ---------- 设置 ----------
  Future<String?> _get(String key) async {
    final db = await _db.database;
    final rows = await db.query('ledger_settings',
        where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> _set(String key, String value) async {
    final db = await _db.database;
    await db.insert('ledger_settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<double> startBalance() async {
    final v = await _get('start_balance');
    return double.tryParse(v ?? '') ?? 0;
  }

  Future<void> setStartBalance(double v) => _set('start_balance', '$v');

  Future<double> budget() async {
    final v = await _get('budget');
    return double.tryParse(v ?? '') ?? 0;
  }

  Future<void> setBudget(double v) => _set('budget', '$v');

  Future<List<String>> customCats() async {
    final v = await _get('custom_cats');
    if (v == null || v.isEmpty) return [];
    final list = jsonDecode(v);
    return (list as List).cast<String>();
  }

  Future<void> _saveCustomCats(List<String> cats) =>
      _set('custom_cats', jsonEncode(cats));

  Future<void> addCustomCat(String name) async {
    final cats = await customCats();
    if (cats.contains(name)) return;
    cats.add(name);
    await _saveCustomCats(cats);
  }

  Future<void> removeCustomCat(String name) async {
    final cats = await customCats();
    cats.remove(name);
    await _saveCustomCats(cats);
  }

  // ---------- 统计 ----------
  double incomeOf(List<LedgerTxn> list) => list
      .where((t) => t.type == 'income')
      .fold(0, (s, t) => s + t.amount);

  double expenseOf(List<LedgerTxn> list) => list
      .where((t) => t.type == 'expense')
      .fold(0, (s, t) => s + t.amount);

  double balanceOf(List<LedgerTxn> list, double start) =>
      start + incomeOf(list) - expenseOf(list);
}
