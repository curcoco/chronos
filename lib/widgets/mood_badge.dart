import 'package:flutter/material.dart';

/// 心情定义:happy=开心 calm=平静 sad=难过
const Map<String, ({String label, Color fg, Color bg})> moodDefs = {
  'happy': (label: '开心', fg: Color(0xFF2E7D32), bg: Color(0xFFE8F5E9)),
  'calm': (label: '平静', fg: Color(0xFF0288D1), bg: Color(0xFFE3F0FA)),
  'sad': (label: '难过', fg: Color(0xFF7B1FA2), bg: Color(0xFFF3E5F5)),
};

/// 心情小标签(mood 为 null 时隐藏)
class MoodBadge extends StatelessWidget {
  final String? mood;
  const MoodBadge({super.key, this.mood});

  @override
  Widget build(BuildContext context) {
    if (mood == null) return const SizedBox.shrink();
    final d = moodDefs[mood];
    if (d == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: d.bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        d.label,
        style: TextStyle(fontSize: 10, color: d.fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}
