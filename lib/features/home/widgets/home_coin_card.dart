import 'package:flutter/material.dart';

import 'package:chronos/features/coins/services/coin_service.dart';
import 'package:chronos/core/theme.dart';

/// 首页金币卡:余额 + 今日已赚 + 心愿兑换入口。
class HomeCoinCard extends StatelessWidget {
  final int coin;
  final int todayEarned;
  final VoidCallback onTap;

  const HomeCoinCard({
    super.key,
    required this.coin,
    required this.todayEarned,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.primaryLight, AppColors.primarySoft],
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.stars_rounded,
                  color: Color(0xFFFFB300), size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '金币余额',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppColors.onPrimarySoft,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$coin 枚',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.onPrimarySoft,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '今日已赚 $todayEarned/${CoinService.dailyCap}',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.onPrimarySoft),
                ),
                const SizedBox(height: 4),
                Text(
                  '心愿兑换 ›',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.onPrimarySoft,
                      fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
