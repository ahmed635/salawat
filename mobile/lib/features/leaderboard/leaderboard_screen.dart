import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/auth_repository.dart';
import '../../data/leaderboard_repository.dart';
import '../../theme/colors.dart';
import 'widgets/rank_row.dart';
import 'widgets/sticky_my_rank.dart';

class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final topAsync = ref.watch(leaderboardTopProvider);
    final myRankAsync = ref.watch(myRankProvider);
    final myUid = ref.watch(authStateProvider).valueOrNull?.uid;

    return Stack(
      children: [
        RefreshIndicator(
          color: AppColors.emerald600,
          onRefresh: () async {
            ref.invalidate(leaderboardTopProvider);
            ref.invalidate(myRankProvider);
            // Give the streams a moment to re-emit before letting the spinner go.
            await Future<void>.delayed(const Duration(milliseconds: 600));
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            child: Column(
              children: [
                _Header(isDark: isDark),
                const SizedBox(height: 16),
                _Card(
                  isDark: isDark,
                  child: topAsync.when(
                    loading: () => const _EmptyState(text: 'جاري تحميل البيانات...'),
                    error: (e, _) => _EmptyState(text: 'تعذر تحميل البيانات.\n$e'),
                    data: (entries) {
                      if (entries.isEmpty) {
                        return const _EmptyState(text: 'كن أول من يبدأ. صَلِّ الآن.');
                      }
                      return Column(
                        children: [
                          for (var i = 0; i < entries.length; i++)
                            RankRow(
                              entry: entries[i],
                              position: i + 1,
                              isMe: entries[i].uid == myUid,
                              isLast: i == entries.length - 1,
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        // Sticky bottom rank bar — only when user is outside the top list.
        myRankAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (mine) {
            if (mine == null || mine.isInTopList) return const SizedBox.shrink();
            return Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: StickyMyRank(myRank: mine),
            );
          },
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.isDark});
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.yellow500.withValues(alpha: 0.15)
                : const Color(0xFFFEF9C3),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(
            Icons.emoji_events,
            color: AppColors.yellow500,
            size: 36,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'المتنافسون',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: isDark ? Colors.white : AppColors.slate800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'وفي ذلك فليتنافس المتنافسون',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? AppColors.slate400 : AppColors.slate500,
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.isDark, required this.child});
  final bool isDark;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.slate800 : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark ? AppColors.slate700 : AppColors.slate100,
        ),
        boxShadow: const [
          BoxShadow(color: Color(0x0A000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.slate400,
            fontSize: 13,
            height: 1.5,
          ),
        ),
      ),
    );
  }
}
