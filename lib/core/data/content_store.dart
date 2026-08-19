/// 远程内容覆盖池(内存态)。
///
/// 各 data 类(每日内容/英文/健康/心愿)的取值方法优先使用这里的覆盖池,
/// 未覆盖时回退到内置 const 池。覆盖数据由 [ContentUpdater] 从远程
/// content.json 拉取(小更新不换包即可更新文案/词库/食谱等内容)。
class ContentStore {
  ContentStore._();

  static List<String>? quotes;
  static List<({String en, String zh})>? english;
  static List<({String title, String category})>? autoTasks;
  static List<({String title, String detail})>? weekPlans;
  static List<({String title, String detail})>? longTermGoals;

  static List<({String w, String p, String m})>? words;
  static List<({String title, String text})>? readings;
  static List<String>? writings;

  static List<({String name, int kcal, double cost})>? meals;
  static List<({String title, int min})>? videos;

  static List<({String title, int cost})>? wishes;

  /// 是否已有任何远程内容覆盖。
  static bool get hasOverrides =>
      quotes != null ||
      english != null ||
      autoTasks != null ||
      weekPlans != null ||
      longTermGoals != null ||
      words != null ||
      readings != null ||
      writings != null ||
      meals != null ||
      videos != null ||
      wishes != null;
}
