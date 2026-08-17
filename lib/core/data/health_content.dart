import 'dart:math';

/// 健康模块离线内容池:食谱菜品 / 跟练视频(全部内置)
class HealthContent {
  HealthContent._();

  static const List<({String name, int kcal, double cost})> meals = [
    (name: '番茄炒蛋', kcal: 180, cost: 8),
    (name: '清炒西兰花', kcal: 120, cost: 6),
    (name: '米饭(150g)', kcal: 170, cost: 1.5),
    (name: '水煮蛋(2个)', kcal: 150, cost: 2),
    (name: '牛奶(250ml)', kcal: 135, cost: 3),
    (name: '燕麦粥', kcal: 180, cost: 2),
    (name: '鸡胸肉沙拉', kcal: 280, cost: 10),
    (name: '紫薯(1个)', kcal: 110, cost: 3),
    (name: '苹果(1个)', kcal: 95, cost: 2.5),
    (name: '全麦面包(2片)', kcal: 160, cost: 3),
    (name: '香蕉(1根)', kcal: 90, cost: 1.5),
    (name: '酸奶(1杯)', kcal: 120, cost: 4),
  ];

  static const List<String> mealTags = ['早餐', '午餐', '晚餐', '加餐'];

  /// 随机取一份菜品
  static ({String name, int kcal, double cost}) randomMeal() =>
      meals[Random().nextInt(meals.length)];

  static const List<({String title, int min})> videos = [
    (title: '晨间 10 分钟拉伸', min: 10),
    (title: '15 分钟燃脂操', min: 15),
    (title: '瑜伽基础入门 20 分钟', min: 20),
    (title: '睡前放松跟练', min: 12),
  ];

  static const List<String> workoutTypes = ['跑步', '散步', '跳绳', '瑜伽', '骑行', '力量'];
  static const List<String> kitchenCats = ['菜品', '食材', '调料', '教程'];
}
