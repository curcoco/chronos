import 'dart:convert';
import 'dart:io';

import '../models/memory_item.dart';
import 'key_store.dart';

/// 长期记忆 · 云端同步(Supabase REST,匿名 anon key;URL/Key 存本地)
/// 需先在 Supabase 建表并开 RLS,见项目根目录 `supabase-记忆表.sql`
class SupabaseSyncService {
  SupabaseSyncService._();
  static final SupabaseSyncService instance = SupabaseSyncService._();

  Future<bool> isConfigured() async {
    final s = KeyStore.instance;
    return (await s.get(KeyStore.supabaseUrl)).isNotEmpty &&
        (await s.get(KeyStore.supabaseAnonKey)).isNotEmpty;
  }

  /// 上传一条记忆;失败抛异常
  Future<void> push(MemoryItem item) async {
    final s = KeyStore.instance;
    final url = await s.get(KeyStore.supabaseUrl);
    final anonKey = await s.get(KeyStore.supabaseAnonKey);
    if (url.isEmpty || anonKey.isEmpty) throw StateError('未配置 Supabase');
    final base =
        '${url.replaceAll(RegExp(r'/$'), '')}/rest/v1';
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client
          .postUrl(Uri.parse('$base/memories'))
          .timeout(const Duration(seconds: 10));
      req.headers.contentType = ContentType.json;
      req.headers.set('apikey', anonKey);
      req.headers
          .set(HttpHeaders.authorizationHeader, 'Bearer $anonKey');
      req.headers.set('Prefer', 'return=minimal');
      req.write(jsonEncode({
        'kind': item.kind,
        'content': item.content,
        'source': item.source,
        'created_at': DateTime.fromMillisecondsSinceEpoch(item.createdAt)
            .toUtc()
            .toIso8601String(),
      }));
      final res = await req.close().timeout(const Duration(seconds: 15));
      if (res.statusCode != 201 && res.statusCode != 200) {
        await res.drain<void>();
        throw HttpException('同步返回 ${res.statusCode}');
      }
      await res.drain<void>();
    } finally {
      client.close(force: true);
    }
  }
}
