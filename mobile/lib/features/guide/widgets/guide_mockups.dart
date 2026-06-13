// Lightweight, stylized mini-previews of each app screen, shown inside a phone
// frame on the how-to-use guide. These are illustrations built from widgets —
// not live screens — so they never need assets or a running backend. Kept
// deliberately simple; they only need to be *recognizable*, not pixel-exact.
import 'package:flutter/material.dart';

import '../../../theme/colors.dart';

/// A small phone bezel that frames a mock screen. Fixed aspect so every guide
/// page lines up.
class PhoneFrame extends StatelessWidget {
  const PhoneFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: AspectRatio(
        aspectRatio: 9 / 17,
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: isDark ? AppColors.slate950 : AppColors.slate800,
            borderRadius: BorderRadius.circular(34),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x33000000), blurRadius: 20, offset: Offset(0, 10)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(27),
            child: ColoredBox(
              color: isDark ? AppColors.slate900 : AppColors.slate50,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Mini emerald header that mimics the real app header, so each mock reads as
/// "a screen of this app".
class _MiniHeader extends StatelessWidget {
  const _MiniHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topEnd,
          end: AlignmentDirectional.bottomStart,
          colors: [AppColors.emerald600, AppColors.teal700],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 11,
            backgroundColor: Colors.white24,
            child: Icon(Icons.brightness_2, size: 12, color: Colors.white),
          ),
          const SizedBox(width: 6),
          const Text(
            'صلوا عليه',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          Icon(Icons.dark_mode, size: 12, color: Colors.white.withValues(alpha: 0.8)),
          const SizedBox(width: 6),
          Icon(Icons.share, size: 12, color: Colors.white.withValues(alpha: 0.8)),
        ],
      ),
    );
  }
}

/// A short grey bar standing in for a line of text in the mocks. Pass
/// [widthFactor] inside a bounded box (Column-stretch / Expanded), or a fixed
/// [width] when it sits directly in a Row (unbounded width — a fraction there
/// would force infinite width).
class _Bar extends StatelessWidget {
  const _Bar({this.widthFactor, this.width, this.height = 5})
      : assert(widthFactor != null || width != null);
  final double? widthFactor;
  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bar = Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: isDark ? AppColors.slate700 : AppColors.slate200,
        borderRadius: BorderRadius.circular(99),
      ),
    );
    if (widthFactor == null) return bar;
    return FractionallySizedBox(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: widthFactor,
      child: bar,
    );
  }
}

class _MockScaffold extends StatelessWidget {
  const _MockScaffold({required this.body});
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _MiniHeader(),
        Expanded(child: Padding(padding: const EdgeInsets.all(10), child: body)),
      ],
    );
  }
}

/// الرئيسية — goal card, big tap button, daily count.
class HomeMock extends StatelessWidget {
  const HomeMock({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _MockScaffold(
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.emerald600, AppColors.teal700],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('الهدف اليومي',
                    style: TextStyle(color: Colors.white, fontSize: 9)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: const LinearProgressIndicator(
                    value: 0.62,
                    minHeight: 5,
                    backgroundColor: Colors.white24,
                    valueColor: AlwaysStoppedAnimation(AppColors.amber300),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Container(
            width: 96,
            height: 96,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.emerald500, AppColors.emerald700],
              ),
              boxShadow: [
                BoxShadow(
                    color: Color(0x4D059669), blurRadius: 16, offset: Offset(0, 6)),
              ],
            ),
            child: const Text('صلِّ',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900)),
          ),
          const SizedBox(height: 12),
          Text('١٢٤',
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: isDark ? Colors.white : AppColors.slate800)),
          Text('صلاة اليوم',
              style: TextStyle(
                  fontSize: 9,
                  color: isDark ? AppColors.slate400 : AppColors.slate500)),
          const Spacer(),
        ],
      ),
    );
  }
}

/// صيغ الصلاة — numbered cards with colored source badges.
class SalawatMock extends StatelessWidget {
  const SalawatMock({super.key});

  @override
  Widget build(BuildContext context) {
    return _MockScaffold(
      body: Column(
        children: [
          for (final (n, badge, color, bg) in const [
            (1, 'متفق عليه', AppColors.emerald800, Color(0xFFD1FAE5)),
            (2, 'رواه البخاري', AppColors.amber800, Color(0xFFFEF3C7)),
            (3, 'رواه مسلم', AppColors.amber800, Color(0xFFFEF3C7)),
          ]) ...[
            _SalawatCardMock(number: n, badge: badge, badgeFg: color, badgeBg: bg),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _SalawatCardMock extends StatelessWidget {
  const _SalawatCardMock({
    required this.number,
    required this.badge,
    required this.badgeFg,
    required this.badgeBg,
  });

  final int number;
  final String badge;
  final Color badgeFg;
  final Color badgeBg;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? AppColors.slate800 : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: isDark ? AppColors.slate700 : AppColors.slate200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                    color: AppColors.emerald900, shape: BoxShape.circle),
                child: Text('$number',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900)),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                    color: badgeBg, borderRadius: BorderRadius.circular(6)),
                child: Text(badge,
                    style: TextStyle(
                        color: badgeFg,
                        fontSize: 8,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const _Bar(widthFactor: 1),
          const SizedBox(height: 5),
          const _Bar(widthFactor: 0.75),
        ],
      ),
    );
  }
}

/// لوحة الشرف — ranked rows, the user's row highlighted.
class LeaderboardMock extends StatelessWidget {
  const LeaderboardMock({super.key});

  @override
  Widget build(BuildContext context) {
    return _MockScaffold(
      body: Column(
        children: [
          const Icon(Icons.emoji_events, color: AppColors.yellow500, size: 30),
          const SizedBox(height: 10),
          for (final (rank, me) in const [(1, false), (2, true), (3, false), (4, false)]) ...[
            _RankRowMock(rank: rank, isMe: me),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _RankRowMock extends StatelessWidget {
  const _RankRowMock({required this.rank, required this.isMe});
  final int rank;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isMe
        ? (isDark ? AppColors.emerald900 : const Color(0xFFD1FAE5))
        : (isDark ? AppColors.slate800 : Colors.white);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
            color: isDark ? AppColors.slate700 : AppColors.slate200),
      ),
      child: Row(
        children: [
          Text('$rank',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  color: isDark ? AppColors.slate300 : AppColors.slate600)),
          const SizedBox(width: 8),
          const CircleAvatar(radius: 8, backgroundColor: AppColors.emerald400),
          const SizedBox(width: 8),
          const Expanded(child: _Bar(widthFactor: 0.6)),
          const SizedBox(width: 8),
          const _Bar(width: 18, height: 5),
        ],
      ),
    );
  }
}

/// إنجازاتي — profile header and a grid of badges.
class ProfileMock extends StatelessWidget {
  const ProfileMock({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _MockScaffold(
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.emerald600, AppColors.teal700],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.white24,
                  child: Icon(Icons.person, size: 16, color: Colors.white),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text('اسمك',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800)),
                    SizedBox(height: 4),
                    Text('٣٬٤٠٠ صلاة',
                        style: TextStyle(color: Colors.white70, fontSize: 9)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (final (icon, on) in const [
                  (Icons.star, true),
                  (Icons.military_tech, true),
                  (Icons.workspace_premium, true),
                  (Icons.emoji_events, false),
                  (Icons.diamond, false),
                  (Icons.auto_awesome, false),
                ])
                  Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: on
                          ? (isDark
                              ? AppColors.emerald900
                              : const Color(0xFFD1FAE5))
                          : (isDark ? AppColors.slate800 : Colors.white),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color:
                              isDark ? AppColors.slate700 : AppColors.slate200),
                    ),
                    child: Icon(icon,
                        size: 18,
                        color: on
                            ? AppColors.amber500
                            : (isDark
                                ? AppColors.slate600
                                : AppColors.slate300)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
