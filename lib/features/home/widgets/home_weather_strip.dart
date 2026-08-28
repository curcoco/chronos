import 'package:flutter/material.dart';

import 'package:chronos/core/theme.dart';

/// 首页天气条(点击选择城市;下拉刷新也会更新天气)。
class HomeWeatherStrip extends StatelessWidget {
  final String city;
  final String text;
  final String temp;
  final VoidCallback onTap;

  const HomeWeatherStrip({
    super.key,
    required this.city,
    required this.text,
    required this.temp,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            const Icon(Icons.wb_sunny_rounded,
                size: 18, color: Color(0xFFFFB300)),
            const SizedBox(width: 8),
            Text(city, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 10),
            Text(text,
                style: TextStyle(fontSize: 13, color: AppColors.textSub)),
            const Spacer(),
            Text(
              '$temp℃',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryDark),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down_rounded,
                size: 18, color: AppColors.textSub),
          ],
        ),
      ),
    );
  }
}
