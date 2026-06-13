import 'package:flutter/material.dart';

import '../../models/supplication.dart';
import '../../theme/colors.dart';
import 'widgets/supplication_card.dart';

/// "صيغ الصلاة" — a read-only feed of the authentic forms of salah upon the
/// Prophet ﷺ (see [supplications]). Static content; no providers needed.
/// Adapts the "Daily Supplications" Stitch reference (gradient hero, numbered
/// cards, source badges, hadith banner, closing quote) to the app's palette so
/// it stays theme-aware in light/dark.
class SupplicationsScreen extends StatelessWidget {
  const SupplicationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final children = <Widget>[
      _Hero(isDark: isDark),
      const SizedBox(height: 20),
    ];

    for (var i = 0; i < supplications.length; i++) {
      children
          .add(SupplicationCard(supplication: supplications[i], number: i + 1));
      children.add(const SizedBox(height: 14));
      // The hadith banner sits after the 4th form, as in the reference.
      if (i == 3) {
        children
          ..add(const _HadithBanner())
          ..add(const SizedBox(height: 14));
      }
    }

    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: children,
      ),
    );
  }
}

/// Deep-emerald gradient banner with the screen title — the reference's hero.
class _Hero extends StatelessWidget {
  const _Hero({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.emerald900, AppColors.emerald800],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [
          BoxShadow(
              color: Color(0x1A000000), blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.amber300,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 10,
                    offset: Offset(0, 4)),
              ],
            ),
            child: const Icon(Icons.spa, color: AppColors.emerald900, size: 30),
          ),
          const SizedBox(height: 14),
          const Text(
            'كيف نصلي على النبي ﷺ ؟',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'هدي النبي ﷺ في الصلاة عليه',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

/// The «من صلَّى عليَّ واحدةً…» hadith, as a gradient call-out (the reference
/// uses a mosque photo here; we keep it offline-friendly with a gradient).
class _HadithBanner extends StatelessWidget {
  const _HadithBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.emerald900, AppColors.emerald800],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
              color: Color(0x1A000000), blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'عن أبي هريرة رضي الله عنه',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '«مَن صلَّى عليَّ واحدةً صلَّى اللهُ عليه عشرًا»',
            style: TextStyle(
              fontSize: 18,
              height: 1.6,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
