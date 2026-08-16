import 'package:flutter_test/flutter_test.dart';
import 'package:student_workbench/services/app_info.dart';
import 'package:student_workbench/services/coin_service.dart';
import 'package:student_workbench/services/task_service.dart';
import 'package:student_workbench/models/student_task.dart';
import 'package:student_workbench/data/daily_content.dart';
import 'package:student_workbench/utils/dates.dart';

void main() {
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
}
