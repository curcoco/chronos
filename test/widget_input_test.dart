import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:chronos/core/widgets/app_text_field.dart';

/// AppTextField 的交互语义测试(交互层回归防护):
/// 1) submitOnEnter=true(如首页速记):结尾换行 → 触发一次提交并剥离换行。
/// 2) submitOnEnter=false(如灵感速记页/日记):回车正常换行,不触发提交。
void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('submitOnEnter=true:结尾换行触发提交并剥离换行', (tester) async {
    final controller = TextEditingController();
    var submitCount = 0;
    // 用多行框:单行框会在 onChanged 前吞掉 \n,无法观察换行兜底。
    await tester.pumpWidget(host(AppTextField(
      controller: controller,
      submitOnEnter: true,
      maxLines: 3,
      onSubmit: () => submitCount++,
    )));

    // 模拟输入法把「完成」当换行插入(不触发 onSubmitted 的场景)
    await tester.enterText(find.byType(TextField), '早起背单词\n');
    await tester.pump();

    expect(submitCount, 1, reason: '换行兜底应触发且仅触发一次提交');
    expect(controller.text, '早起背单词', reason: '结尾换行应被剥离');
  });

  testWidgets('submitOnEnter=false:回车保留为换行,不触发提交', (tester) async {
    final controller = TextEditingController();
    var submitCount = 0;
    await tester.pumpWidget(host(AppTextField(
      controller: controller,
      submitOnEnter: false,
      maxLines: 5,
      onSubmit: () => submitCount++,
    )));

    await tester.enterText(find.byType(TextField), '第一行\n第二行');
    await tester.pump();

    expect(submitCount, 0, reason: '换行框不应因回车提交');
    expect(controller.text, '第一行\n第二行', reason: '换行应原样保留');
  });

  testWidgets('未提供 onSubmit 时回车不报错且不触发提交', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(host(AppTextField(
      controller: controller,
      maxLines: 3,
    )));
    await tester.enterText(find.byType(TextField), '随手写\n下一行');
    await tester.pump();
    // 无 onSubmit:换行兜底不触发,文本原样保留(含换行)
    expect(controller.text, '随手写\n下一行');
  });
}
