/// 厨房秘籍条目
class KitchenItem {
  final int? id;
  final String cat;
  final String name;
  final int cal;
  final double price;
  final String link;
  final int createdAt;

  const KitchenItem({
    this.id,
    required this.cat,
    required this.name,
    required this.cal,
    required this.price,
    required this.link,
    required this.createdAt,
  });

  factory KitchenItem.fromMap(Map<String, Object?> map) => KitchenItem(
        id: map['id'] as int?,
        cat: map['cat'] as String,
        name: map['name'] as String,
        cal: map['cal'] as int,
        price: (map['price'] as num).toDouble(),
        link: map['link'] as String,
        createdAt: map['created_at'] as int,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'cat': cat,
        'name': name,
        'cal': cal,
        'price': price,
        'link': link,
        'created_at': createdAt,
      };
}
