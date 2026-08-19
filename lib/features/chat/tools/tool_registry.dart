import 'package:student_workbench/features/chat/tools/chat_tool.dart';
import 'package:student_workbench/features/coins/services/coin_service.dart';
import 'package:student_workbench/features/coins/services/wish_service.dart';
import 'package:student_workbench/features/ledger/services/ledger_service.dart';
import 'package:student_workbench/features/notes/services/note_service.dart';
import 'package:student_workbench/features/tasks/services/task_service.dart';
import 'package:student_workbench/core/services/weather_service.dart';
import 'package:student_workbench/core/utils/dates.dart';

/// 工具注册表:集中管理闲话铺可用工具(定义 + 执行器)。
///
/// 原则:
/// - 速记/日记等隐私数据**不注册**工具 → 小掌柜天然无权限访问;
/// - 写操作(记账/加任务/完成任务)标记 [ChatTool.requireConfirm] = true,
///   聊天页调用前弹用户确认,防止 AI 乱写数据;
/// - 新增工具只需在 [all] 里加一个条目。
class ToolRegistry {
  ToolRegistry._();

  /// 全部工具(按名称索引)
  static final Map<String, ChatTool> _byName = {
    for (final t in _build())
      (t.definition['function'] as Map)['name'] as String: t,
  };

  static List<ChatTool> _build() => [
        // ---------- 只读 ----------
        ChatTool(
          name: 'get_weather',
          definition: {
            'type': 'function',
            'function': {
              'name': 'get_weather',
              'description': '查询指定城市的当前天气',
              'parameters': {
                'type': 'object',
                'properties': {
                  'city': {
                    'type': 'string',
                    'description': '城市拼音,如 beijing / hangzhou',
                  },
                },
                'required': ['city'],
              },
            },
          },
          execute: (args) async {
            final city = (args['city'] as String?)?.trim() ?? '';
            if (city.isEmpty) return '缺少城市参数';
            if (!await WeatherService.instance.isConfigured()) {
              return '天气服务未配置(API 配置页未填心知天气 Key)';
            }
            try {
              final w = await WeatherService.instance.fetchCity(city);
              return '${w.city} 当前 ${w.text},${w.temp}℃';
            } catch (e) {
              return '天气查询失败:$e';
            }
          },
        ),
        ChatTool(
          name: 'get_today_tasks',
          definition: {
            'type': 'function',
            'function': {
              'name': 'get_today_tasks',
              'description': '查询今天的学习任务列表',
              'parameters': {'type': 'object', 'properties': {}},
            },
          },
          execute: (args) async {
            final tasks = await TaskService().todayTasks(todayStr());
            if (tasks.isEmpty) return '今天没有任务';
            return tasks
                .map((t) =>
                    '${t.done ? "[已完成]" : "[待完成]"} ${t.title}(${t.category})')
                .join('\n');
          },
        ),
        ChatTool(
          name: 'get_balance',
          definition: {
            'type': 'function',
            'function': {
              'name': 'get_balance',
              'description': '查询当前记账余额、本月收支与金币余额',
              'parameters': {'type': 'object', 'properties': {}},
            },
          },
          execute: (args) async {
            final ledger = LedgerService();
            final txns = await ledger.txns();
            final start = await ledger.startBalance();
            final balance = ledger.balanceOf(txns, start);
            final coin = await CoinService.instance.balance();
            final budget = await ledger.budget();
            final today = todayStr();
            final todayExpense =
                txns.where((t) => t.type == 'expense' && t.date == today).fold(
                    0.0, (s, t) => s + t.amount);
            final todayIncome =
                txns.where((t) => t.type == 'income' && t.date == today).fold(
                    0.0, (s, t) => s + t.amount);
            final buf = StringBuffer('记账余额:¥${balance.toStringAsFixed(2)}');
            if (budget > 0) buf.write(',月度预算:¥${budget.toStringAsFixed(2)}');
            buf.write('\n今日:收入 ¥${todayIncome.toStringAsFixed(2)},'
                '支出 ¥${todayExpense.toStringAsFixed(2)}');
            buf.write('\n金币余额:$coin 枚');
            return buf.toString();
          },
        ),
        ChatTool(
          name: 'get_wishes',
          definition: {
            'type': 'function',
            'function': {
              'name': 'get_wishes',
              'description': '查询心愿清单',
              'parameters': {'type': 'object', 'properties': {}},
            },
          },
          execute: (args) async {
            final wishes = await WishService().wishes();
            if (wishes.isEmpty) return '心愿清单是空的';
            return wishes
                .map((w) =>
                    '${w.redeemed ? "[已兑换]" : "[待兑换]"} ${w.title}(${w.cost}金币)')
                .join('\n');
          },
        ),
        ChatTool(
          name: 'get_notes',
          definition: {
            'type': 'function',
            'function': {
              'name': 'get_notes',
              'description': '查询最近的灵感速记记录(仅限用户主动询问时)',
              'parameters': {'type': 'object', 'properties': {}},
            },
          },
          execute: (args) async {
            final notes = await NoteService().notes();
            if (notes.isEmpty) return '还没有灵感记录';
            return notes.take(5).map((n) => n.content).join('\n');
          },
        ),
        // ---------- 写操作(需用户确认) ----------
        ChatTool(
          name: 'add_ledger',
          requireConfirm: true,
          definition: {
            'type': 'function',
            'function': {
              'name': 'add_ledger',
              'description': '记一笔账(支出或收入)',
              'parameters': {
                'type': 'object',
                'properties': {
                  'type': {
                    'type': 'string',
                    'enum': ['expense', 'income'],
                    'description': 'expense=支出 income=收入',
                  },
                  'amount': {
                    'type': 'number',
                    'description': '金额(元)',
                  },
                  'category': {
                    'type': 'string',
                    'description': '分类:餐饮/交通/购物/学习/娱乐/医疗/其他(支出);零花钱/兼职/红包/其他(收入)',
                  },
                  'note': {
                    'type': 'string',
                    'description': '备注(可选)',
                  },
                },
                'required': ['type', 'amount', 'category'],
              },
            },
          },
          // 未确认前:只展示意图。
          execute: (args) async =>
              '用户需确认后才能记账:${_describeLedger(args)}。请等待用户确认。',
          executeConfirmed: (args) async {
            final type = (args['type'] as String?) ?? 'expense';
            final amount = (args['amount'] as num?)?.toDouble() ?? 0;
            final category = (args['category'] as String?) ?? '其他';
            final note = (args['note'] as String?)?.trim() ?? '';
            if (amount <= 0) return '金额无效';
            await LedgerService().addTxn(
              type: type,
              amount: amount,
              category: category,
              note: note,
              date: todayStr(),
            );
            final ok = await CoinService.instance.rewardLedgerCheckin(todayStr());
            return '已记账:${_describeLedger(args)}${ok > 0 ? '(记账打卡,金币 +$ok)' : ''}';
          },
        ),
        ChatTool(
          name: 'add_task',
          requireConfirm: true,
          definition: {
            'type': 'function',
            'function': {
              'name': 'add_task',
              'description': '给今日清单添加一个学习任务',
              'parameters': {
                'type': 'object',
                'properties': {
                  'title': {'type': 'string', 'description': '任务内容'},
                  'category': {'type': 'string', 'description': '分类,如 学习'},
                  'priority': {
                    'type': 'integer',
                    'enum': [0, 1, 2],
                    'description': '0=高 1=中 2=低',
                  },
                },
                'required': ['title'],
              },
            },
          },
          execute: (args) async =>
              '用户需确认后才能加任务:「${args['title']}」。请等待用户确认。',
          executeConfirmed: (args) async {
            final title = (args['title'] as String?)?.trim() ?? '';
            if (title.isEmpty) return '任务内容为空';
            await TaskService().addTask(
              title: title,
              category: (args['category'] as String?) ?? '学习',
              priority: (args['priority'] as num?)?.toInt() ?? 1,
              date: todayStr(),
            );
            return '已添加任务:「$title」';
          },
        ),
        ChatTool(
          name: 'complete_task',
          requireConfirm: true,
          definition: {
            'type': 'function',
            'function': {
              'name': 'complete_task',
              'description': '把今日清单中指定标题的任务标记为完成(可领金币)',
              'parameters': {
                'type': 'object',
                'properties': {
                  'title': {'type': 'string', 'description': '要完成的任务标题'},
                },
                'required': ['title'],
              },
            },
          },
          execute: (args) async =>
              '用户需确认后才能完成任务:「${args['title']}」。请等待用户确认。',
          executeConfirmed: (args) async {
            final title = (args['title'] as String?)?.trim() ?? '';
            final service = TaskService();
            final tasks = await service.todayTasks(todayStr());
            final match = tasks
                .where((t) => !t.done && t.title == title)
                .toList();
            if (match.isEmpty) return '今天没有未完成的同名任务:「$title」';
            final r = await service.toggleTask(match.first, todayStr());
            return '已完成任务「$title」${r.total > 0 ? ',金币 +${r.total}' : ''}';
          },
        ),
      ];

  /// 全部工具定义(发给模型)
  static List<Map<String, dynamic>> definitions() =>
      [for (final t in _byName.values) t.definition];

  /// 按名称取工具;不存在返回 null
  static ChatTool? byName(String name) => _byName[name];

  /// 执行工具(调用方需先处理确认逻辑):
  /// 对 [ChatTool.requireConfirm] 的工具,若 [confirmed] 为 true 走确认执行,
  /// 否则返回待确认提示。
  static Future<String> execute(
    String name,
    Map<String, dynamic> args, {
    bool confirmed = false,
  }) async {
    final tool = _byName[name];
    if (tool == null) return '未知工具:$name';
    if (tool.requireConfirm && !confirmed && tool.executeConfirmed != null) {
      return tool.execute(args);
    }
    if (confirmed && tool.executeConfirmed != null) {
      return tool.executeConfirmed!(args);
    }
    return tool.execute(args);
  }

  /// 工具是否要求用户确认
  static bool needsConfirm(String name) => _byName[name]?.requireConfirm ?? false;

  static String _describeLedger(Map<String, dynamic> args) {
    final type = (args['type'] as String?) ?? 'expense';
    final amount = (args['amount'] as num?)?.toDouble() ?? 0;
    final category = (args['category'] as String?) ?? '其他';
    final note = (args['note'] as String?)?.trim() ?? '';
    final kind = type == 'income' ? '收入' : '支出';
    final buf = StringBuffer('$kind ¥${amount.toStringAsFixed(2)}($category)');
    if (note.isNotEmpty) buf.write(' $note');
    return buf.toString();
  }
}
