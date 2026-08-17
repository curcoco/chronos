import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import 'package:student_workbench/core/services/key_store.dart';

/// 零时闲话铺 · 语音朗读(elevenlabs TTS;Key/语音 ID 存本地)
class ElevenService {
  ElevenService._();
  static final ElevenService instance = ElevenService._();
  final AudioPlayer _player = AudioPlayer();

  Future<bool> isConfigured() async {
    final s = KeyStore.instance;
    return (await s.get(KeyStore.elevenApiKey)).isNotEmpty &&
        (await s.get(KeyStore.elevenVoiceId)).isNotEmpty;
  }

  /// 合成语音并播放;失败抛异常
  Future<void> speak(String text) async {
    final s = KeyStore.instance;
    final apiKey = await s.get(KeyStore.elevenApiKey);
    final voiceId = await s.get(KeyStore.elevenVoiceId);
    if (apiKey.isEmpty || voiceId.isEmpty) throw StateError('未配置语音服务');
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final uri = Uri.parse(
          'https://api.elevenlabs.io/v1/text-to-speech/$voiceId');
      final req = await client
          .postUrl(uri)
          .timeout(const Duration(seconds: 10));
      req.headers.contentType = ContentType.json;
      req.headers.set('xi-api-key', apiKey);
      req.write(jsonEncode({
        'text': text,
        'voice_settings': {'stability': 0.5, 'similarity_boost': 0.75},
      }));
      final res = await req.close().timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw HttpException('语音服务返回 ${res.statusCode}');
      }
      final bytes = <int>[];
      await for (final chunk in res) {
        bytes.addAll(chunk);
      }
      if (bytes.isEmpty) throw HttpException('语音内容为空');
      await _player.stop();
      await _player.play(BytesSource(Uint8List.fromList(bytes)));
    } finally {
      client.close(force: true);
    }
  }

  void stop() => _player.stop();
}
