import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

import 'package:chronos/core/services/http_json.dart';
import 'package:chronos/core/services/key_store.dart';

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
    final bytes = await HttpJson.postBytes(
      'https://api.elevenlabs.io/v1/text-to-speech/$voiceId',
      headers: {'xi-api-key': apiKey},
      body: {
        'text': text,
        'voice_settings': {'stability': 0.5, 'similarity_boost': 0.75},
      },
      ioTimeout: const Duration(seconds: 30),
    );
    if (bytes.isEmpty) throw HttpException('语音内容为空');
    await _player.stop();
    await _player.play(BytesSource(Uint8List.fromList(bytes)));
  }

  void stop() => _player.stop();
}
