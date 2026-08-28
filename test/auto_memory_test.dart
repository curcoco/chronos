import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:chronos/core/services/db_helper.dart';
import 'package:chronos/features/memory/services/auto_memory_service.dart';
import 'package:chronos/features/memory/services/memory_service.dart';

/// Auto Memory:AI 在回复里输出 `<mem_create/edit/delete>` 标签,系统截取执行、
/// 标签从正文剥离。用 sqflite_common_ffi 在真实 SQLite 上跑(依赖 MemoryService)。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // 每个测试用全新库:关闭单例连接并删除 db(含 wal/shm),避免残留。
    await DbHelper.instance.close();
    final dir = await databaseFactory.getDatabasesPath();
    for (final name in [
      'student_workbench.db',
      'student_workbench.db-wal',
      'student_workbench.db-shm',
    ]) {
      final f = File(p.join(dir, name));
      if (await f.exists()) await f.delete();
    }
  });

  final auto = AutoMemoryService.instance;
  final memory = MemoryService.instance;

  test('create:执行 <mem_create> 并写入档案(source=auto)', () async {
    await DbHelper.instance.database; // 建表
    final r = await auto.processReply(
        '<mem_create category="画像" importance="8">用户喜欢深夜写代码</mem_create>');
    expect(r.cleaned, isEmpty); // 纯标签,剥离后无正文
    expect(r.results.length, 1);
    expect(r.results.first.ok, isTrue);
    expect(r.results.first.label, '已写入档案');
    final items = await memory.list();
    expect(items.length, 1);
    final m = items.first;
    expect(m.kind, 'profile');
    expect(m.source, 'auto');
    expect(m.importance, 8);
    expect(m.content, '用户喜欢深夜写代码');
  });

  test('strip:标签从混合正文剥离,正文保留', () async {
    await DbHelper.instance.database;
    final r = await auto.processReply(
        '好的,我记住了。<mem_create category="事实">用户养了一只橘猫</mem_create>下次聊到宠物我再提。');
    expect(r.cleaned, contains('好的,我记住了。'));
    expect(r.cleaned, isNot(contains('mem_create')));
    expect(r.cleaned, isNot(contains('用户养了一只橘猫')));
    expect(r.results.first.ok, isTrue);
  });

  test('edit + delete:按 id 更新/删除档案', () async {
    await DbHelper.instance.database;
    await auto.processReply(
        '<mem_create category="画像">用户喜欢喝美式</mem_create>');
    final id = (await memory.list()).first.id!;

    final up = await auto.processReply('<mem_edit id="$id">用户改喝拿铁</mem_edit>');
    expect(up.results.first.ok, isTrue);
    expect((await memory.list()).first.content, '用户改喝拿铁');

    final del =
        await auto.processReply('<mem_delete id="$id"/>');
    expect(del.results.first.ok, isTrue);
    expect(await memory.list(), isEmpty);
  });

  test('上限:同一条回复最多执行 3 次,多余的操作被跳过', () async {
    await DbHelper.instance.database;
    final text = [
      for (var i = 1; i <= 4; i++) '<mem_create category="事实">记忆$i</mem_create>',
    ].join('');
    final r = await auto.processReply(text);
    expect(r.results.length, 4); // 3 次执行 + (第 4 次) 跳过
    expect(r.results.where((x) => x.ok).length, 3);
    expect(r.results.where((x) => !x.ok).length, 1);
    expect((await memory.list()).length, 3);
  });

  test('去重:内容与已有档案重复时写入未执行', () async {
    await DbHelper.instance.database;
    await auto.processReply('<mem_create category="画像">用户喜欢听爵士</mem_create>');
    final r = await auto.processReply('<mem_create category="画像">用户喜欢听爵士</mem_create>');
    expect(r.results.first.ok, isFalse);
    expect(r.results.first.label, '记忆写入未执行');
    expect((await memory.list()).length, 1);
  });
}
