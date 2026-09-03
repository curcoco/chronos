import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:chronos/main.dart';
import 'package:chronos/core/services/ai_provider.dart';
import 'package:chronos/core/services/app_info.dart';
import 'package:chronos/core/utils/context_budget.dart';
import 'package:chronos/features/coins/services/coin_service.dart';
import 'package:chronos/features/tasks/services/task_service.dart';
import 'package:chronos/features/tasks/models/student_task.dart';
import 'package:chronos/core/data/daily_content.dart';
import 'package:chronos/core/data/content_store.dart';
import 'package:chronos/core/data/content_updater.dart';
import 'package:chronos/core/utils/dates.dart';
import 'package:chronos/features/chat/tools/tool_registry.dart';
import 'package:chronos/features/chat/services/llm_service.dart';

void main() {
  group('ModelRef 模型引用解析', () {
    test('合法引用解析出提供商与模型', () {
      final r = ModelRef.parse('default|deepseek-chat');
      expect(r?.providerId, 'default');
      expect(r?.modelId, 'deepseek-chat');
    });

    test('空 / 格式错误返回 null', () {
      expect(ModelRef.parse(null), isNull);
      expect(ModelRef.parse(''), isNull);
      expect(ModelRef.parse('nodivider'), isNull);
      expect(ModelRef.parse('|model'), isNull);
      expect(ModelRef.parse('provider|'), isNull);
    });

    test('ref 拼接往返一致(模型 id 可含 / 等字符)', () {
      const r = ModelRef('p1', 'm/1');
      expect(r.ref, 'p1|m/1');
      expect(ModelRef.parse(r.ref)?.modelId, 'm/1');
    });
  });

  group('stepTextScale 全局字号阶梯缩放', () {
    test('最小字号(≤13)保持不变', () {
      expect(stepTextScale(9), 9);
      expect(stepTextScale(10), 10);
      expect(stepTextScale(11), 11);
      expect(stepTextScale(12), 12);
      expect(stepTextScale(13), 13);
    });

    test('正文(14~17)整体略小', () {
      expect(stepTextScale(14), closeTo(13.58, 0.01));
      expect(stepTextScale(15), closeTo(14.1, 0.01));
      expect(stepTextScale(16), closeTo(14.56, 0.01));
      expect(stepTextScale(17), closeTo(14.96, 0.01));
    });

    test('大号(≥18)明显调小 ×0.85', () {
      expect(stepTextScale(18), closeTo(15.3, 0.01));
      expect(stepTextScale(24), closeTo(20.4, 0.01));
      expect(stepTextScale(36), closeTo(30.6, 0.01));
      expect(stepTextScale(46), closeTo(39.1, 0.01));
    });

    test('全区间单调:不会「大字比小字还小」', () {
      for (var i = 9; i <= 60; i++) {
        expect(stepTextScale((i + 1).toDouble()),
            greaterThanOrEqualTo(stepTextScale(i.toDouble())));
      }
    });
  });

  group('AppInfo.compareVersions 版本比较', () {
    test('相等返回 0', () {
      expect(AppInfo.compareVersions('1.6.1', '1.6.1'), 0);
    });

    test('大于返回正、小于返回负', () {
      expect(AppInfo.compareVersions('1.6.2', '1.6.1'), greaterThan(0));
      expect(AppInfo.compareVersions('1.6.0', '1.6.1'), lessThan(0));
      expect(AppInfo.compareVersions('2.0.0', '1.9.9'), greaterThan(0));
    });

    test('位数不同按缺省 0 补齐', () {
      expect(AppInfo.compareVersions('1.6', '1.6.0'), 0);
      expect(AppInfo.compareVersions('1.6.1', '1.6'), greaterThan(0));
    });

    test('非数字段按 0 处理不抛异常', () {
      expect(AppInfo.compareVersions('1.a.0', '1.0.0'), 0);
    });

    test('旧版本能发现更新(核心更新判定语义)', () {
      // installed < remote 才算有更新
      expect(AppInfo.compareVersions('1.6.1', '1.7.0') < 0, isTrue);
      expect(AppInfo.compareVersions('1.7.0', '1.6.1') < 0, isFalse);
    });
  });

  group('dates 日期工具', () {
    test('dateSeed 去横线并转整数', () {
      expect(dateSeed('2026-08-17'), 20260817);
      expect(dateSeed('bad'), 0);
    });

    test('同一天种子稳定、不同天不同', () {
      expect(dateSeed('2026-08-17'), dateSeed('2026-08-17'));
      expect(dateSeed('2026-08-17') == dateSeed('2026-08-18'), isFalse);
    });

    test('weekdayLabel 覆盖周一到周日', () {
      // 2026-08-17 是周一
      expect(weekdayLabel(DateTime(2026, 8, 17)), '星期一');
      expect(weekdayLabel(DateTime(2026, 8, 23)), '星期日');
    });

    test('timeGreeting 按时段分档', () {
      expect(timeGreeting(DateTime(2026, 8, 17, 7)), '晨光熹微');
      expect(timeGreeting(DateTime(2026, 8, 17, 10)), '清风徐来');
      expect(timeGreeting(DateTime(2026, 8, 17, 12)), '日光温柔');
      expect(timeGreeting(DateTime(2026, 8, 17, 15)), '暖阳正好');
      expect(timeGreeting(DateTime(2026, 8, 17, 20)), '华灯初上');
      expect(timeGreeting(DateTime(2026, 8, 17, 2)), '月色温柔');
    });

    test('monthDayLabel / dateKey 格式', () {
      expect(monthDayLabel(DateTime(2026, 8, 5)), '8月5日');
      expect(dateKey(DateTime(2026, 8, 5)), '2026-08-05');
    });
  });

  group('DailyContent 每日内容(确定性)', () {
    test('quoteFor 同一天稳定、且落在池内', () {
      final q1 = DailyContent.quoteFor('2026-08-17');
      final q2 = DailyContent.quoteFor('2026-08-17');
      expect(q1, q2);
      expect(DailyContent.quotes.contains(q1), isTrue);
    });

    test('englishFor 同一天稳定、且落在池内', () {
      final e1 = DailyContent.englishFor(DateTime(2026, 8, 17));
      final e2 = DailyContent.englishFor(DateTime(2026, 8, 17));
      expect(e1, e2);
      expect(DailyContent.english.contains(e1), isTrue);
    });

    test('autoTasksFor 恰好 3 条、无重复、同天稳定', () {
      final t1 = DailyContent.autoTasksFor('2026-08-17');
      final t2 = DailyContent.autoTasksFor('2026-08-17');
      expect(t1.length, 3);
      expect(t1.map((e) => e.title).toSet().length, 3); // 无重复
      expect(t1.map((e) => e.title).toList(),
          t2.map((e) => e.title).toList()); // 稳定
    });

    test('randomAutoTask 尊重排除集合', () {
      final exclude = DailyContent.autoTasks
          .take(DailyContent.autoTasks.length - 1)
          .map((e) => e.title)
          .toSet();
      final picked = DailyContent.randomAutoTask(exclude: exclude);
      // 只剩最后一条候选
      expect(picked.title, DailyContent.autoTasks.last.title);
    });
  });

  group('CoinService.grantable 每日上限发放', () {
    test('额度充足按拟发放数发放', () {
      expect(CoinService.grantable(earned: 0, amount: 1), 1);
      expect(CoinService.grantable(earned: 3, amount: 3), 3);
    });

    test('接近上限时截断到剩余额度', () {
      expect(CoinService.grantable(earned: 9, amount: 2), 1); // 只剩 1
      expect(CoinService.grantable(earned: 10, amount: 3), 0); // 已满
    });

    test('超上限或非正拟发放数发 0', () {
      expect(CoinService.grantable(earned: 11, amount: 1), 0);
      expect(CoinService.grantable(earned: 0, amount: 0), 0);
      expect(CoinService.grantable(earned: 0, amount: -5), 0);
    });

    test('自定义 cap 生效', () {
      expect(CoinService.grantable(earned: 4, amount: 3, cap: 5), 1);
    });

    test('默认 cap 为 10(与需求一致)', () {
      expect(CoinService.dailyCap, 10);
    });
  });

  group('TaskService.sortTasks 排序', () {
    StudentTask task({
      required String title,
      required int priority,
      required bool done,
      required int createdAt,
    }) =>
        StudentTask(
          title: title,
          category: '学习',
          priority: priority,
          done: done,
          date: '2026-08-17',
          auto: false,
          createdAt: createdAt,
        );

    test('未完成排在已完成之前', () {
      final list = [
        task(title: 'done', priority: 1, done: true, createdAt: 1),
        task(title: 'todo', priority: 1, done: false, createdAt: 2),
      ];
      TaskService.sortTasks(list);
      expect(list.first.title, 'todo');
    });

    test('同完成态下高优先级(值小)在前', () {
      final list = [
        task(title: 'low', priority: 2, done: false, createdAt: 1),
        task(title: 'high', priority: 0, done: false, createdAt: 2),
        task(title: 'mid', priority: 1, done: false, createdAt: 3),
      ];
      TaskService.sortTasks(list);
      expect(list.map((e) => e.title).toList(), ['high', 'mid', 'low']);
    });

    test('同完成态同优先级按创建时间升序', () {
      final list = [
        task(title: 'later', priority: 1, done: false, createdAt: 200),
        task(title: 'earlier', priority: 1, done: false, createdAt: 100),
      ];
      TaskService.sortTasks(list);
      expect(list.first.title, 'earlier');
    });
  });

  group('灵感速记提交去抖/换行兜底语义', () {
    // 模拟 AppTextField 的换行兜底 + 去抖:值以换行结尾 → 触发一次提交,
    // 且「提交中」时重复调用被忽略(不重复保存)。
    test('结尾换行触发一次提交并剥离换行', () {
      var submitCount = 0;
      String? committed;
      var text = '';
      void handleChange(String value) {
        if (value.endsWith('\n')) {
          final cleaned = value.substring(0, value.length - 1);
          text = cleaned;
          committed = cleaned;
          submitCount++;
        }
      }

      handleChange('你好\n');
      expect(submitCount, 1);
      expect(text, '你好');
      expect(committed, '你好');
    });

    test('提交中标志阻止重复保存', () async {
      var saving = false;
      var saves = 0;
      Future<void> save() async {
        if (saving) return;
        saving = true;
        try {
          saves++;
          await Future<void>.delayed(const Duration(milliseconds: 1));
        } finally {
          saving = false;
        }
      }

      // 连续两次(如「完成」键 + 换行回调)只应保存一次。
      final f1 = save();
      final f2 = save();
      await Future.wait([f1, f2]);
      expect(saves, 1);
    });
  });

  group('ToolRegistry 工具注册表', () {
    test('定义结构合法(名称/描述/参数齐全)', () {
      for (final def in ToolRegistry.definitions()) {
        final fn = def['function'] as Map<String, dynamic>;
        expect(fn['name'], isNotEmpty, reason: '每个工具必须有名称');
        expect(fn['description'], isNotEmpty, reason: '每个工具必须有描述');
        final params = fn['parameters'] as Map<String, dynamic>;
        expect(params['type'], 'object');
        expect(params['properties'], isA<Map>());
      }
    });

    test('读工具不需要确认,写工具需要确认', () {
      expect(ToolRegistry.needsConfirm('get_weather'), isFalse);
      expect(ToolRegistry.needsConfirm('get_today_tasks'), isFalse);
      expect(ToolRegistry.needsConfirm('get_balance'), isFalse);
      expect(ToolRegistry.needsConfirm('get_wishes'), isFalse);
      expect(ToolRegistry.needsConfirm('add_ledger'), isTrue);
      expect(ToolRegistry.needsConfirm('add_task'), isTrue);
      expect(ToolRegistry.needsConfirm('complete_task'), isTrue);
    });

    test('速记/日记数据没有对应工具(小掌柜无权限访问)', () {
      final names = ToolRegistry.definitions()
          .map((d) => (d['function'] as Map)['name'] as String)
          .toSet();
      expect(names.contains('get_notes'), isTrue); // 速记仅可读
      expect(names.any((n) => n.contains('diary')), isFalse); // 日记无任何工具
      expect(names.any((n) => n.contains('delete')), isFalse); // 无删除类工具
    });

    test('未知工具返回错误文本', () async {
      final r = await ToolRegistry.execute('not_exist', {});
      expect(r, '未知工具:not_exist');
    });

    test('写工具未确认时执行返回待确认提示', () async {
      final r = await ToolRegistry.execute(
        'add_task',
        {'title': '写作业'},
      );
      expect(r, contains('用户需确认'));
    });
  });

  group('远程内容热更(ContentStore 覆盖)', () {
    tearDown(() {
      // 清理覆盖,避免影响其它测试(内置池不变)。
      ContentStore.quotes = null;
      ContentStore.english = null;
      ContentStore.autoTasks = null;
      ContentStore.weekPlans = null;
      ContentStore.longTermGoals = null;
      ContentStore.words = null;
      ContentStore.readings = null;
      ContentStore.writings = null;
      ContentStore.meals = null;
      ContentStore.videos = null;
      ContentStore.wishes = null;
    });

    test('设置覆盖后 quoteFor 从覆盖池取值', () {
      ContentStore.quotes = ['远程金句一', '远程金句二'];
      final q = DailyContent.quoteFor('2026-08-17');
      expect(ContentStore.quotes!.contains(q), isTrue);
    });

    test('覆盖前用内置池、覆盖后切换', () {
      final before = DailyContent.quotePool;
      expect(before, DailyContent.quotes);
      ContentStore.quotes = ['远程金句一'];
      expect(DailyContent.quotePool, isNot(equals(DailyContent.quotes)));
      expect(DailyContent.quotePool.single, '远程金句一');
    });
  });

  group('ContextBudget 上下文「条数 + token」双约束', () {
    ({String role, String content, String? reasoningContent}) msg(String c) =>
        (role: 'user', content: c, reasoningContent: null);

    test('条数上限生效(短消息按条数截)', () {
      final list = [for (var i = 0; i < 100; i++) msg('你好')];
      // token 预算充足,按条数上限截。
      expect(
        ContextBudget.keepCount(list, maxCount: 80, budget: 100000),
        80,
      );
    });

    test('token 预算生效(长消息保留更少)', () {
      final list = [for (var i = 0; i < 50; i++) msg('长' * 500)]; // 每条约 421 token
      final kept = ContextBudget.keepCount(list, maxCount: 800, budget: 2000);
      // 2000 / 421 ≈ 4.7 → 只保留最后 4 条,而不是 50 条。
      expect(kept, 4);
    });

    test('至少保留最后一条(单条超预算也不为空)', () {
      final list = [msg('超长' * 10000), msg('你好')];
      expect(ContextBudget.keepCount(list, maxCount: 800, budget: 100), 1);
    });

    test('空列表返回 0', () {
      expect(ContextBudget.keepCount(const [], maxCount: 80, budget: 1000), 0);
    });

    test('模型档位:1M 上下文 → 预算 100 万、预警 80 万', () {
      expect(ContextBudget.budgetFor(true), 1000000);
      expect(ContextBudget.warnThresholdFor(true), 800000);
      expect(ContextBudget.budgetFor(false), 200000);
      expect(ContextBudget.warnThresholdFor(false), 167000);
    });

    test('预警线低于预算,预留压缩余量', () {
      expect(ContextBudget.warnThresholdFor(true),
          lessThan(ContextBudget.budgetFor(true)));
      expect(ContextBudget.warnThresholdFor(false),
          lessThan(ContextBudget.budgetFor(false)));
    });
  });

  group('LlmService 中转站端点兼容(修复「配置正确但回复为空」)', () {    test('根地址自动补全 /chat/completions', () {
      expect(
        LlmService.endpointFor('https://api.example.com/v1'),
        'https://api.example.com/v1/chat/completions',
      );
      // 末尾带斜杠也不重复拼。
      expect(
        LlmService.endpointFor('https://api.example.com/v1/'),
        'https://api.example.com/v1/chat/completions',
      );
    });

    test('已带完整端点的地址不重复拼接', () {
      expect(
        LlmService.endpointFor('https://api.example.com/v1/chat/completions'),
        'https://api.example.com/v1/chat/completions',
      );
    });

    test('http 明文中转站地址同样支持', () {
      expect(
        LlmService.endpointFor('http://120.76.230.67:18011/v1'),
        'http://120.76.230.67:18011/v1/chat/completions',
      );
    });
  });

  group('生图模型(AiProviders 生图接口兼容 / 参数化)', () {
    test('imageEndpointFor:根地址自动补 /v1 + /images/generations', () {
      expect(
        AiProviders.imageEndpointFor('https://api.example.com'),
        'https://api.example.com/v1/images/generations',
      );
      expect(
        AiProviders.imageEndpointFor('https://api.example.com/v1'),
        'https://api.example.com/v1/images/generations',
      );
      expect(
        AiProviders.imageEndpointFor('https://api.example.com/v1/'),
        'https://api.example.com/v1/images/generations',
      );
    });

    test('imageEndpointFor:已带完整端点或多级版本段不重复拼接', () {
      expect(
        AiProviders.imageEndpointFor(
            'https://api.example.com/v1/images/generations'),
        'https://api.example.com/v1/images/generations',
      );
      expect(
        AiProviders.imageEndpointFor('https://api.example.com/openai/v1'),
        'https://api.example.com/openai/v1/images/generations',
      );
    });

    test('ImageGenOptions.toBody:默认只带必要字段', () {
      final body = const ImageGenOptions(model: 'gpt-image-2', prompt: 'a cat')
          .toBody();
      expect(body['model'], 'gpt-image-2');
      expect(body['prompt'], 'a cat');
      expect(body['n'], 1);
      expect(body['response_format'], 'b64_json');
      expect(body.containsKey('size'), isFalse);
      expect(body.containsKey('quality'), isFalse);
      expect(body.containsKey('image'), isFalse);
    });

    test('ImageGenOptions.toBody:尺寸/清晰度/张数/风格/底图都带上', () {
      final body = const ImageGenOptions(
        model: 'gpt-image-2',
        prompt: 'a cat',
        size: '1792x1024',
        quality: 'hd',
        n: 2,
        style: 'vivid',
        imageBase64: 'aW1n',
      ).toBody();
      expect(body['size'], '1792x1024');
      expect(body['quality'], 'hd');
      expect(body['n'], 2);
      expect(body['style'], 'vivid');
      expect(body['image'], 'aW1n');
    });

    test('mimeForBytes:按图片头字节识别类型,识别不了回退 png', () {
      expect(
        AiProviders.mimeForBytes(
            Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])),
        'image/png',
      );
      expect(
        AiProviders.mimeForBytes(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])),
        'image/jpeg',
      );
      expect(
        AiProviders.mimeForBytes(
            Uint8List.fromList([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50])),
        'image/webp',
      );
      expect(
        AiProviders.mimeForBytes(Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])),
        'image/gif',
      );
      expect(
        AiProviders.mimeForBytes(Uint8List.fromList([1, 2, 3])),
        'image/png',
      );
    });

    test('ImageGenResult.ext:按 mime 推导扩展名', () {
      expect(
        ImageGenResult(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])).ext,
        'jpg',
      );
      expect(
        ImageGenResult(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0])).ext,
        'png',
      );
      expect(
        ImageGenResult(Uint8List.fromList([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])).ext,
        'gif',
      );
    });
  });

  group('ContentUpdater 内容热更地址推导(兼容非 latest.json 更新源)', () {
    test('latest.json 结尾 → 同目录 content.json', () {
      expect(
        ContentUpdater.contentUrlFor('http://120.76.230.67:18011/latest.json'),
        'http://120.76.230.67:18011/content.json',
      );
    });

    test('目录形态更新源 → 末尾补 /content.json', () {
      expect(
        ContentUpdater.contentUrlFor('http://host:8080/updates'),
        'http://host:8080/updates/content.json',
      );
      expect(
        ContentUpdater.contentUrlFor('http://host:8080/updates/'),
        'http://host:8080/updates/content.json',
      );
    });

    test('已带 content.json 不重复拼接', () {
      expect(
        ContentUpdater.contentUrlFor('http://host/x/content.json'),
        'http://host/x/content.json',
      );
    });
  });
}
