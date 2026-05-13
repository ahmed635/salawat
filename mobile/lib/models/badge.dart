import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// One rung on the gamification ladder. Ported 1:1 from the React source.
class Badge {
  const Badge({
    required this.id,
    required this.title,
    required this.requirement,
    required this.icon,
    required this.color,
    required this.bgLight,
    required this.bgDark,
  });

  final int id;
  final String title;
  final int requirement;
  final IconData icon;
  final Color color;
  final Color bgLight;
  final Color bgDark;

  Color bg(Brightness b) => b == Brightness.dark ? bgDark : bgLight;
}

const badges = <Badge>[
  Badge(
    id: 1,
    title: 'مبتدئ',
    requirement: 10,
    icon: Icons.star,
    color: Color(0xFF3B82F6), // blue-500
    bgLight: Color(0xFFDBEAFE), // blue-100
    bgDark: Color(0x661E3A8A), // blue-900/40
  ),
  Badge(
    id: 2,
    title: 'مداوم',
    requirement: 100,
    icon: Icons.favorite,
    color: Color(0xFFEC4899), // pink-500
    bgLight: Color(0xFFFCE7F3),
    bgDark: Color(0x66831843),
  ),
  Badge(
    id: 3,
    title: 'ذاكر لله',
    requirement: 500,
    icon: Icons.shield,
    color: AppColors.slate500,
    bgLight: AppColors.slate200,
    bgDark: AppColors.slate700,
  ),
  Badge(
    id: 4,
    title: 'نور القلوب',
    requirement: 1000,
    icon: Icons.wb_sunny,
    color: AppColors.amber500,
    bgLight: Color(0xFFFEF3C7),
    bgDark: Color(0x66713F12),
  ),
  Badge(
    id: 5,
    title: 'محب للنبي',
    requirement: 5000,
    icon: Icons.military_tech,
    color: AppColors.emerald500,
    bgLight: Color(0xFFD1FAE5),
    bgDark: Color(0x66064E3B),
  ),
  Badge(
    id: 6,
    title: 'تاج الوقار',
    requirement: 10000,
    icon: Icons.workspace_premium,
    color: Color(0xFFA855F7), // purple-500
    bgLight: Color(0xFFF3E8FF),
    bgDark: Color(0x66581C87),
  ),
  Badge(
    id: 7,
    title: 'رفيق الدرب',
    requirement: 50000,
    icon: Icons.groups,
    color: Color(0xFF6366F1), // indigo-500
    bgLight: Color(0xFFE0E7FF),
    bgDark: Color(0x66312E81),
  ),
  Badge(
    id: 8,
    title: 'الشفاعة المرجوة',
    requirement: 100000,
    icon: Icons.emoji_events,
    color: AppColors.yellow500,
    bgLight: Color(0xFFFEF9C3),
    bgDark: Color(0x66713F12),
  ),
  Badge(
    id: 9,
    title: 'نور الأمة',
    requirement: 250000,
    icon: Icons.auto_awesome,
    color: Color(0xFF06B6D4), // cyan-500
    bgLight: Color(0xFFCFFAFE),
    bgDark: Color(0x66155E75),
  ),
  Badge(
    id: 10,
    title: 'سراج المحبين',
    requirement: 500000,
    icon: Icons.local_fire_department,
    color: Color(0xFFF43F5E), // rose-500
    bgLight: Color(0xFFFFE4E6),
    bgDark: Color(0x669F1239),
  ),
  Badge(
    id: 11,
    title: 'مليون صلاة',
    requirement: 1000000,
    icon: Icons.celebration,
    color: Color(0xFFF97316), // orange-500
    bgLight: Color(0xFFFFEDD5),
    bgDark: Color(0x669A3412),
  ),
];

/// Badge that unlocks at exactly [count], or null.
Badge? badgeUnlockedAt(int count) {
  for (final b in badges) {
    if (b.requirement == count) return b;
  }
  return null;
}

/// Next badge above [count], or the last badge if all are unlocked.
Badge nextBadgeFor(int count) {
  for (final b in badges) {
    if (b.requirement > count) return b;
  }
  return badges.last;
}

/// Requirement of the highest badge already unlocked, or 0.
int previousBadgeRequirement(int count) {
  var prev = 0;
  for (final b in badges) {
    if (b.requirement <= count) {
      prev = b.requirement;
    } else {
      break;
    }
  }
  return prev;
}
