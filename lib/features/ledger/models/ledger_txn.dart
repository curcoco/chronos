/// 记账流水
class LedgerTxn {
  final int? id;
  /// income=收入 expense=支出
  final String type;
  final double amount;
  final String category;
  final String note;
  /// 日期 yyyy-MM-dd
  final String date;
  final int createdAt;

  const LedgerTxn({
    this.id,
    required this.type,
    required this.amount,
    required this.category,
    required this.note,
    required this.date,
    required this.createdAt,
  });

  factory LedgerTxn.fromMap(Map<String, Object?> map) => LedgerTxn(
        id: map['id'] as int?,
        type: map['type'] as String,
        amount: (map['amount'] as num).toDouble(),
        category: map['category'] as String,
        note: map['note'] as String,
        date: map['txn_date'] as String,
        createdAt: map['created_at'] as int,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'type': type,
        'amount': amount,
        'category': category,
        'note': note,
        'txn_date': date,
        'created_at': createdAt,
      };
}
