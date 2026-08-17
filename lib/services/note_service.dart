import '../models/note.dart';
import 'base_dao.dart';

/// 灵感速记服务(同步到「灵感专区」)。CRUD 复用 [BaseDao]。
class NoteService extends BaseDao<Note> {
  NoteService();

  @override
  String get table => 'notes';

  @override
  Note fromMap(Map<String, Object?> map) => Note.fromMap(map);

  @override
  Map<String, Object?> toMap(Note entity) => entity.toMap();

  @override
  String get defaultOrderBy => 'created_at DESC';

  Future<void> addNote(String content, {String? mood}) async {
    final text = content.trim();
    if (text.isEmpty) return;
    await insert(Note(
      content: text,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      mood: mood,
    ));
  }

  /// 直接插入一条 Note(用于「撤销删除」恢复原记录),返回新行 id
  Future<int> restore(Note note) => insert(note);

  /// 最新在前
  Future<List<Note>> notes() => queryAll();

  Future<void> deleteNote(int id) => deleteById(id);

  /// 批量删除
  Future<void> deleteNotes(List<int> ids) => deleteByIds(ids);

  /// 收藏 / 取消收藏
  Future<void> setFavorite(int id, bool favorite) =>
      updateById(id, {'favorite': favorite ? 1 : 0});
}
