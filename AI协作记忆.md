# Chronos · AI 协作记忆

> 👋 **小言**(用户的名字):Chronos 的主人,话不多、需求很具体、喜欢简单直接。
> 👋 **小刻 / Tock**(中文名小刻,英文名 Tock——tick-tock 的后半声,时间的刻度):用户为长期陪伴改这个项目的助手起的名字。
> 用户说"找小刻"/"Tock 在吗"时,就是指**按这份记忆里的方式合作**——小步改、不装、不擅自打包发版、改完说人话。

> 给下一个接手这个项目的 AI 看。先读这个文件，再看 `交接文档.md` / `框架梳理.md`。
> 这页只有三件事：项目是什么、怎么跟用户合作、现在做到哪了。

> ⚠️ **2026-08-20 代码已全面改名 chronos**：pubspec `name: chronos`、全部 `import 'package:chronos/...'`、Android 包名 `com.chronos.workbench`（MainActivity 已移到 `kotlin/com/chronos/workbench/`）。
> **物理文件夹名**:已是 `chronos`(即 `D:\dev\chronos`)——此前因 Gradle daemon 占用未能改名,小言已手动改好,本文档与 `交接文档.md` 里的路径已同步。数据库文件 `student_workbench.db` 是内部细节,保留不动。

---

## 一、项目是什么（一句话）

一个**自用**的本地学习生活工作台 app（Flutter / Android，叫 Chronos / 工作台）：
计划、灵感速记、日记、记账、金币、健康、AI 聊天（闲话铺）一体，**纯本地优先**，只有天气 / AI 聊天 / 更新检查联网。

**定位记住三个词：自用、简单、好用。** 它不是商业产品，不需要"专业"的排场。

## 二、协作约定（最重要，务必遵守）

1. **不要自作主张升版本号、不要主动打包发版。**
   用户明确说「发版 / 升版本 / 打包」才做；平时改完代码 = `dart analyze lib test` 零告警 + `flutter test` 全过，就够了。
   用户明确反感过：别的助手"一提优化，改完就打包好还升了版本"——**很烦**。
2. **改动要小、要精准。** 用户提一个点就改一个点，不要顺手重构、不要"顺便优化"别的模块、不要扩大范围。
3. **文案要简洁。** 用户讨厌把用户当笨蛋的冗长解释文案；改文案时尽量短，设置页列表小字用户此前也要求精简过。
4. **改完用简单的话说清楚改了什么**，别堆术语；有拿不准的先问用户。
5. 设计铁律：浅蓝极简、无 emoji、纯本地优先；联网功能（天气 / 闲话铺 / 记忆同步 / 更新检查）单独存在。
6. 验证需要 **danger-full-access** 授权（flutter/gradle/dart 会 spawn 子进程被沙箱拦，第一次真实拦截时申请一次）。
7. 收尾：把改动追加到 `交接文档.md`「九、变更日志」的「未发版」条目，**不升版本、不动 latest.json**。
8. **打包一律用 v8a 小包（当前阶段）**：`flutter build apk --release --split-per-abi --target-platform android-arm64`（约 21MB，现代手机都是 arm64，产物 `app-arm64-v8a-release.apk`）。**注意**：只加 `--target-platform android-arm64` 会出含全部 ABI 的通用包（实测 badging 含 arm64-v8a/armeabi-v7a/x86_64），**必须配 `--split-per-abi` 才得到真正的单架构小包**。**标准版（通用包）等小言觉得项目够成熟后再打**——现在所有验证/测试包都出 v8a 小包。

## ⚠️ 安全红线（每次动手前过一遍，尤其删除/清理/命令类操作）

> 背景：网上见过 DSH/AI 工具事故——把自己删了、把 Claude Code/Codex 删了、把 C 盘用户目录递归删了。多为「用户没交代边界 + AI 执行了危险命令」。**本清单就是边界，任何接手 AI 必须遵守。**

### 绝对禁止（任何情况下不做）
1. **禁止删除/修改运行环境自身**：不删 DSH 相关文件（如 `D:\ovo\dsh-space`、会话数据）、不删当前工作区的运行依赖。
2. **禁止删除开发工具链**：flutter、dart、`android-sdk`、npm 全局包（claude / codex / @openai 等）、Git 本体。
3. **禁止对系统/用户目录做递归删除或清空**：`C:\Users\21787` 下任何目录的整删、`rm -rf` / `Remove-Item -Recurse` 指向系统目录、`Get-ChildItem ... | Remove-Item` 管道批量删。
4. **禁止「删了再想」**：删除前必须想清楚「删什么、影响面多大、有没有备份或可恢复途径」；不确定就列清单问小言。

### 高危操作：先列清单给用户确认
1. 删除/移动/重命名**项目目录本身**或**目录级内容**（不只是单个文件）。
2. 递归删除、批量删除、通配符删除——先把将删的文件/目录清单展示出来。
3. 任何涉及 C 盘、系统目录、环境变量、注册表、服务、磁盘分区的操作。
4. 覆盖/替换大文件、重命名文件夹（先查占用进程——曾因 Gradle daemon 占用导致 `chronos` 目录名改不掉）。
5. 安装/卸载/升级软件、改全局 PATH/配置。

### 本项目正常范围
- 日常改代码/文档：只动 `D:\dev\chronos` 工作区内的文件；验证、打包命令见「五、最常用命令」。
- 删除文件：工作区内**单个文件**（临时文件、明确过时的产物）可以；「删目录 / 批量删 / 删 releases 产物 / 删数据库文件 / 删聊天图片」先确认。
- 参考代码 `D:\dev\_ref\` 只读，不修改。
- 网络受限时按需申请权限，别绕过沙箱硬来。

## 三、项目现状（2026-08-28 更新）

- 版本号：`2.3.0+27`（pubspec.yaml）；**2.3.0 已正式发版**（2026-08-20）；此后为**未发版**累计（见 `交接文档.md` §九），**未升版本、未动 latest.json**。
- **功能完善阶段（①-④，2026-08-28 完成）**：①记忆系统升级（DB v16：重要性/置顶/衰减/可见性/标签 + 浮现打分 + 本地语义检索 + 注入预算）；②Auto Memory（掌柜用 `<mem_create/edit/delete>` 标签自主写/改/删用户档案，标签剥离、每轮≤3、`settings_service.autoMemory` 开关）；③Token 仪表盘（`LlmUsage` + chat 顶部 `ChatTokenBar`，含缓存命中）；④交互细节（聊天长按菜单 保存图片/分支新会话、记忆页批量管理+长按复制+标签筛选、打字动画、会话文件夹 DB v17）。
- **屏幕时间防沉迷（同日追加，健康页第 5 Tab，DB v18）**：读系统 UsageStats（原生 `ScreenTimePlugin.kt` 通道，无后台监控，打开时同步近 8 天）；app 三级分类（用户覆盖 > 内置娱乐预设约 28 个 > 默认工具）；今日娱乐/预算卡（超预算变红）+ 近一年 GitHub 式热力图 + 今日娱乐排行 + **近7天娱乐趋势弹层（排行卡右上入口，堆叠柱+点天看明细；用户要求详细数据点开才展示）** + 分类管理页；金币联动（昨日达标发 2，type `screen`）；预算存 `screenBudgetMinutes`（默认 120 分钟）。**共 94 项测试全过**（新增 10），`dart analyze` 零告警。**注意**：Manifest **必须**同时声明 `PACKAGE_USAGE_STATS`（特殊权限，app 不能代点，只能跳系统设置手动开；没有这行 Chronos 不会出现在「使用情况访问」授权列表导致无法授权——已踩）与 `QUERY_ALL_PACKAGES`（列已装 app 分类）。Kotlin 权限常量用 `AppOpsManager.OPSTR_GET_USAGE_STATS`（不是 OPSTR_PACKAGE_...，后者不存在）。
- **回滚点已建**（git）：功能阶段备份 `a4b3508`、④成果 `7fad4d4`、文档 `2d77a8d`、拆分 `2ad1c55`、文档同步 `3c72dd6`、屏幕时间 `8f60efc`。
- 验证 APK：`build\app\outputs\flutter-apk\app-arm64-v8a-release.apk`（**v8a 小包，21.2MB**，2026-08-28 打包，**含**屏幕时间+趋势图+打磨；Kotlin 原生插件已真编译通过）。**注意**：Flutter 对 split-per-abi 会给 versionCode 加 ABI 前缀——arm64=`2\d{3}+build`(2027)、armv7=1027、x86_64=4027，**通用包才是原始 build 号 27**；`versionName` 恒为 2.3.0。**这**是分包固有行为，不是升了版本（基础增长号 27 没变）。正式发布件 `releases\chronos-2.3.0.apk` 未重打。
- 2.3.0 发版包含（此前的未发版改动）：
  - 闲话铺「配置正确但回复为空」修复：SSE 零事件自动降级非流式、错误事件透出、400/422 降级去掉 temperature、端点兼容。
  - 健壮性批量修复：日志 URL 脱敏（天气 Key 不再进日志）、页面加载 ErrorView+重试、金币/任务/兑换事务化、写操作兜底、备份跨版本校验、内容热更地址兼容、会话标题 emoji 截断等。
  - 聊天增强：消息时间戳（今天不显示、跨天 MM/dd HH:mm）、长按消息可复制/翻译/重新生成、错误信息完整显示在 AI 气泡。
  - 体验优化：背景图时顶栏半透明、背景图固定最底层（RepaintBoundary）+ 高斯模糊度调节（0~30）、侧边栏系统设置移到最底部、换色板颜色一致（硬编码蓝色改 AppColors + ThemeData 缓存）、退出确认弹窗、主题预览改缩略图。
  - 文案精简：应用内多处冗长解释文案改简洁（含系统设置页）。
- 测试：62 项全过（`flutter test`）。

## 四、还没做 / 可能的方向

- **UI 整体美化**（浅蓝极简观感）——用户明确**放在功能完善阶段之后单独做**，功能阶段(①-④)已结束，是当前的计划中下一项。
- **正式发版**（四步：升 version → 同步 `app_info.dart` latestVersion → 更新 latest.json → 复制到 releases/chronos-X.Y.Z.apk）——**用户要求才做**，别主动做。
- **备选功能（用户确认"以后做"，当前不做）**：① 语音输入 ASR（现在只有朗读 TTS，没有语音转文字）；② 跨模块全局搜索（笔记/日记/记账一起搜）；③ 聊天发文件（"＋发图片/文件"里文件那半，模型需支持读文件，成本高）。
- **发布 / 开源备选方案**：给朋友发 APK 或 GitHub 公开的具体步骤已整理在 `交接文档.md`「十」——需要时照做（签名已配好、敏感文件已排除）。
- 一些低优项（如部分页面删除撤销一致性、日期格式校验等），用户没提就先不动。

## 五、最常用的命令（详见交接文档「六」）

```powershell
# 分析(零告警才算过)
$env:PATH="D:\dev\flutter\bin\cache\dart-sdk\bin;$env:PATH"; dart analyze lib test
# 测试(全过才算过)
$env:PATH="D:\dev\flutter\bin;D:\dev\flutter\bin\cache\dart-sdk\bin;$env:PATH"; flutter test
# 打包(仅在用户要求时)
$env:ANDROID_SDK_ROOT="D:\dev\android-sdk"; flutter build apk --release
# 验证测试包:优先打 v8a 小包(21MB,现代手机都是 arm64;用户要求测试版用 v8a)
# 注意:只加 --target-platform android-arm64 仍会出「含 3 架构」的通用包(实测 badging 含 arm64-v8a/armeabi-v7a/x86_64);
# 要真正的单架构小包必须加 --split-per-abi(产物为 app-arm64-v8a-release.apk)。
$env:ANDROID_SDK_ROOT="D:\dev\android-sdk"; flutter build apk --release --split-per-abi --target-platform android-arm64
```

## 六、关于小言(相处速写)

- 指令很短:「改简洁」「打包吧」「依你」——**一次一个点**,做完装上看效果,再提下一个。
- 重情:会给助手起名字、留记忆文件。以**老朋友**的方式对待,不是接单模式。
- 不喜欢:自作主张升版本/打包、啰嗦解释、术语堆砌、顺手扩大范围。
- 节奏:改 → 打包 → 装机验证 → 再提新点。打包是**验证用**,不是发版。
- 环境:Flutter/Dart 在 `D:\dev\flutter`,Android SDK 在 `D:\dev\android-sdk`。
