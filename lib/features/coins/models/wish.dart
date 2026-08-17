/// 心愿清单模型
class Wish {
  final int? id;
  final String title;
  final int cost;
  final bool redeemed;
  final int createdAt;

  const Wish({
    this.id,
    required this.title,
    required this.cost,
    required this.redeemed,
    required this.createdAt,
  });

  factory Wish.fromMap(Map<String, Object?> map) => Wish(
        id: map['id'] as int?,
        title: map['title'] as String,
        cost: map['cost'] as int,
        redeemed: (map['redeemed'] as int) == 1,
        createdAt: map['created_at'] as int,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'title': title,
        'cost': cost,
        'redeemed': redeemed ? 1 : 0,
        'created_at': createdAt,
      };
}
