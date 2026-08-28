import 'package:flutter/material.dart';

/// 统一的应用文本输入框。
///
/// 收敛全 App `TextField` 的提交行为,解决两个反复出现的问题:
/// 1) 部分中文输入法在多行/默认键盘下,「完成」键被当作换行插入,
///    不触发 [TextField.onSubmitted];这里用 [onChanged] 侦测结尾换行兜底,
///    统一转成「提交」语义。
/// 2) 快速点击/回车导致重复提交:提交回调交由上层配合「提交中」态去抖。
///
/// 用法:提供 [onSubmit] 即启用「回车/完成 = 提交」;需要多行长文本编辑
/// (如日记正文)时把 [submitOnEnter] 设为 false,回车即正常换行。
class AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String? hintText;
  final int minLines;
  final int? maxLines;
  final int? maxLength;
  final bool autofocus;
  final bool showCounter;
  final InputBorder? border;
  final TextStyle? style;

  /// 密码/密钥输入(掩码显示)。
  final bool obscureText;

  /// 「回车/完成」时触发。为 null 时不启用提交语义。
  final VoidCallback? onSubmit;

  /// 提交是否被锁定(如提交中防重):锁定时回车/完成键不触发 [onSubmit]。
  final bool submitLocked;

  /// 文本变化回调(在换行兜底处理之后回传纯文本)。
  final ValueChanged<String>? onChanged;

  /// 是否把回车/完成视为提交(默认 true)。长文本编辑设为 false。
  final bool submitOnEnter;

  const AppTextField({
    super.key,
    required this.controller,
    this.focusNode,
    this.hintText,
    this.minLines = 1,
    this.maxLines = 1,
    this.maxLength,
    this.autofocus = false,
    this.showCounter = false,
    this.border,
    this.style,
    this.obscureText = false,
    this.onSubmit,
    this.submitLocked = false,
    this.onChanged,
    this.submitOnEnter = true,
  });

  void _handleChanged(String value) {
    // 兜底:侦测到结尾换行 → 视为「完成」,剥掉换行并提交。
    if (submitOnEnter &&
        onSubmit != null &&
        !submitLocked &&
        value.endsWith('\n')) {
      final cleaned = value.substring(0, value.length - 1);
      if (controller.text != cleaned) {
        controller.text = cleaned;
        controller.selection =
            TextSelection.collapsed(offset: cleaned.length);
      }
      onChanged?.call(cleaned);
      onSubmit!.call();
      return;
    }
    onChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final enableSubmit = submitOnEnter && onSubmit != null;
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      obscureText: obscureText,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
      // 显式 text 键盘:避免多行时动作键变成换行而吞掉「完成」。
      keyboardType: enableSubmit ? TextInputType.text : TextInputType.multiline,
      textInputAction:
          enableSubmit ? TextInputAction.done : TextInputAction.newline,
      onChanged: _handleChanged,
      onSubmitted: enableSubmit && !submitLocked
          ? (_) => onSubmit!.call()
          : null,
      style: style,
      decoration: InputDecoration(
        hintText: hintText,
        counterText: showCounter ? null : '',
        border: border,
      ),
    );
  }
}
