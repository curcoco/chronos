/// 常用城市(名称 + 心知天气拼音)
class CityOption {
  final String name;
  final String pinyin;
  const CityOption(this.name, this.pinyin);
}

const List<CityOption> commonCities = [
  CityOption('北京', 'beijing'),
  CityOption('上海', 'shanghai'),
  CityOption('广州', 'guangzhou'),
  CityOption('深圳', 'shenzhen'),
  CityOption('杭州', 'hangzhou'),
  CityOption('成都', 'chengdu'),
  CityOption('武汉', 'wuhan'),
  CityOption('西安', 'xian'),
  CityOption('南京', 'nanjing'),
  CityOption('重庆', 'chongqing'),
  CityOption('长沙', 'changsha'),
  CityOption('青岛', 'qingdao'),
  CityOption('苏州', 'suzhou'),
  CityOption('天津', 'tianjin'),
  CityOption('郑州', 'zhengzhou'),
  CityOption('沈阳', 'shenyang'),
  CityOption('大连', 'dalian'),
  CityOption('厦门', 'xiamen'),
  CityOption('昆明', 'kunming'),
  CityOption('哈尔滨', 'haerbin'),
];
