import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/arabic_numbers.dart';
import '../../../data/global_count_repository.dart';
import '../../../theme/colors.dart';
import '../../../theme/gold_mode.dart';

class GlobalGoalCard extends ConsumerWidget {
  const GlobalGoalCard({super.key, required this.goal});

  final int goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final goldMode = ref.watch(goldModeProvider);
    // This card owns the global-count subscription so a new snapshot (polled
    // ~every 60s) rebuilds only this card — not the whole HomeScreen (which
    // would needlessly rebuild the TapButton and its animations).
    final snapshot = ref.watch(globalCountStreamProvider).valueOrNull;
    final current = snapshot?.count ?? 0;
    final isOffline = snapshot?.isOffline ?? false;
    final progress = (current / goal).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: isDark
            ? const LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [AppColors.slate800, Color(0xCC1E293B)],
              )
            : LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: goldMode
                    ? const [Color(0xFFFEF3C7), Color(0xFFFEF9C3)]
                    : const [Color(0xFFECFDF5), Color(0xFFF0FDFA)],
              ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? AppColors.slate700
              : (goldMode
                  ? const Color(0x80FDE68A)
                  : const Color(0x80D1FAE5)),
        ),
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            end: -16,
            top: -16,
            child: Opacity(
              opacity: 0.2,
              child: Transform.rotate(
                angle: 0.21,
                child: Icon(
                  Icons.groups,
                  size: 96,
                  color: isDark
                      ? AppColors.slate700
                      : (goldMode
                          ? const Color(0xFFFDE68A)
                          : const Color(0xFFD1FAE5)),
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'الهدف الجماعي للأمة',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? (goldMode
                              ? AppColors.amber300
                              : const Color(0xFF6EE7B7))
                          : (goldMode
                              ? AppColors.amber900
                              : AppColors.emerald900),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.slate900 : Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Text(
                      formatArabic(goal),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: isDark
                            ? (goldMode
                                ? AppColors.amber400
                                : const Color(0xFF34D399))
                            : (goldMode
                                ? AppColors.amber600
                                : AppColors.emerald600),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 14,
                  backgroundColor: isDark ? AppColors.slate900 : Colors.white,
                  valueColor: AlwaysStoppedAnimation(
                    goldMode ? AppColors.amber500 : const Color(0xFF14B8A6),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'تم جمع:',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isDark ? AppColors.slate400 : AppColors.slate500,
                    ),
                  ),
                  Row(
                    children: [
                      _PingDot(isOffline: isOffline, goldMode: goldMode),
                      const SizedBox(width: 6),
                      Text(
                        '${formatArabic(current)} صلاة',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? (goldMode
                                  ? AppColors.amber400
                                  : const Color(0xFF34D399))
                              : (goldMode
                                  ? AppColors.amber700
                                  : AppColors.emerald700),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _ChallengeCountdown(isDark: isDark, goldMode: goldMode),
            ],
          ),
        ],
      ),
    );
  }
}

/// Live ticking countdown to the next global-counter reset.
///
/// The server zeros `globalShards` at 00:00 Asia/Riyadh (UTC+3 fixed —
/// see `functions/src/_dates.ts`). This widget shows how long until that
/// happens regardless of where the user is — same instant for everyone.
/// Updates once a second.
class _ChallengeCountdown extends StatefulWidget {
  const _ChallengeCountdown({required this.isDark, required this.goldMode});

  final bool isDark;
  final bool goldMode;

  @override
  State<_ChallengeCountdown> createState() => _ChallengeCountdownState();
}

class _ChallengeCountdownState extends State<_ChallengeCountdown> {
  // Asia/Riyadh is fixed UTC+3 — no DST, no transition headaches.
  static const _resetTzOffset = Duration(hours: 3);

  late Timer _ticker;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _recompute();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(_recompute);
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  void _recompute() {
    final nowUtc = DateTime.now().toUtc();
    // Walk into the Riyadh timezone, find the next 00:00 there, walk back
    // to UTC. The difference from `now` is how long until reset.
    final riyadhNow = nowUtc.add(_resetTzOffset);
    final nextRiyadhMidnight =
        DateTime.utc(riyadhNow.year, riyadhNow.month, riyadhNow.day + 1);
    final nextResetUtc = nextRiyadhMidnight.subtract(_resetTzOffset);
    final diff = nextResetUtc.difference(nowUtc);
    _remaining = diff.isNegative ? Duration.zero : diff;
  }

  @override
  Widget build(BuildContext context) {
    final h = _remaining.inHours.toString().padLeft(2, '0');
    final m = (_remaining.inMinutes % 60).toString().padLeft(2, '0');
    final s = (_remaining.inSeconds % 60).toString().padLeft(2, '0');
    // Arabic-Indic digits, monospaced visual via FontWeight + letterSpacing.
    final timeText = arabizeDigits('$h:$m:$s');

    final accentLight = widget.goldMode
        ? AppColors.amber700
        : AppColors.emerald700;
    final accentDark = widget.goldMode
        ? AppColors.amber400
        : const Color(0xFF34D399);
    final labelColor =
        widget.isDark ? AppColors.slate400 : AppColors.slate500;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'ينتهي التحدي خلال:',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: labelColor,
          ),
        ),
        Text(
          timeText,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: widget.isDark ? accentDark : accentLight,
          ),
        ),
      ],
    );
  }
}

class _PingDot extends StatefulWidget {
  const _PingDot({this.isOffline = false, this.goldMode = false});

  final bool isOffline;
  final bool goldMode;

  @override
  State<_PingDot> createState() => _PingDotState();
}

class _PingDotState extends State<_PingDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final haloColor = widget.isOffline
        ? AppColors.red400
        : (widget.goldMode ? AppColors.amber400 : AppColors.emerald400);
    final coreColor = widget.isOffline
        ? AppColors.red500
        : (widget.goldMode ? AppColors.amber500 : AppColors.emerald500);
    return SizedBox(
      width: 12,
      height: 12,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (_, __) {
              final t = _controller.value;
              return Opacity(
                opacity: 0.75 * (1 - t),
                child: Transform.scale(
                  scale: 1 + t * 1.5,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: haloColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              );
            },
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: coreColor,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}
