import '../models/diary_entry.dart';
import 'base_dao.dart';

/// 日记服务(一天可多篇,无上限;本地存储)。CRUD 复用 [BaseDao]。
class DiaryService extends BaseDao<DiaryEntry> {
  DiaryService._();
  static final DiaryService instance = DiaryService._();

  @override
  String get table => 'diary_entries';

  @override
  DiaryEntry fromMap(Map<String, Object?> map) => DiaryEntry.fromMap(map);

  @override
  Map<String, Object?> toMap(DiaryEntry entity) => entity.toMap();

  @override
  String get defaultOrderBy => 'created_at DESC';

  /// 新增一篇日记(一天可多篇,始终追加),返回新行 id
  Future<int> add(
    String date, {
    required String content,
    String? mood,
  }) async {
    final text = content.trim();
    if (text.isEmpty) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    return insert(DiaryEntry(
      content: text,
      mood: mood,
      date: date,
      createdAt: now,
      updatedAt: now,
    ));
  }

  /// 直接插入一篇(用于「撤销删除」恢复原记录),返回新行 id
  Future<int> restore(DiaryEntry entry) => insert(entry);

  /// 全部日记,按创建时间倒序(最新在前)
  Future<List<DiaryEntry>> all() => queryAll();
}
