import 'package:flutter/material.dart';

import '../../../core/arabic_numbers.dart';
import '../../../theme/colors.dart';

/// The big interactive Salawat button. Mirrors the React source:
/// 256×256 emerald→teal gradient circle, rotating decorative rings,
/// expanding ripple on tap, count + label + dhikr text.
class TapButton extends StatefulWidget {
  const TapButton({
    super.key,
    required this.count,
    required this.onTap,
  });

  final int count;
  final Future<void> Function(Offset localPosition) onTap;

  @override
  State<TapButton> createState() => _TapButtonState();
}

class _TapButtonState extends State<TapButton> with TickerProviderStateMixin {
  late final AnimationController _ringSlow = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  )..repeat();
  late final AnimationController _ringFast = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 15),
  )..repeat(reverse: true);

  final List<_Ripple> _ripples = [];

  @override
  void dispose() {
    _ringSlow.dispose();
    _ringFast.dispose();
    for (final r in _ripples) {
      r.controller.dispose();
    }
    super.dispose();
  }

  void _spawnRipple(Offset position) {
    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    final ripple = _Ripple(position: position, controller: controller);
    setState(() => _ripples.add(ripple));
    controller.forward().whenComplete(() {
      controller.dispose();
      if (mounted) setState(() => _ripples.remove(ripple));
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 320,
      height: 320,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _RotatingRing(
            controller: _ringSlow,
            size: 288,
            color: isDark ? AppColors.slate800 : const Color(0xFFD1FAE5),
            strokeWidth: 2,
          ),
          _RotatingRing(
            controller: _ringFast,
            size: 320,
            color: isDark
                ? AppColors.slate800.withValues(alpha: 0.5)
                : const Color(0xFFCCFBF1),
            strokeWidth: 1,
          ),
          GestureDetector(
            onTapDown: (details) {
              _spawnRipple(details.localPosition);
              widget.onTap(details.localPosition);
            },
            child: AnimatedScale(
              scale: 1.0,
              duration: const Duration(milliseconds: 100),
              child: Container(
                width: 256,
                height: 256,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: isDark
                        ? const [AppColors.emerald600, AppColors.teal800]
                        : const [AppColors.emerald400, AppColors.teal600],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.emerald500.withValues(
                        alpha: isDark ? 0.2 : 0.5,
                      ),
                      blurRadius: 50,
                      spreadRadius: -15,
                      offset: const Offset(0, 20),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Color(0x33000000), Color(0x00000000)],
                          ),
                        ),
                      ),
                      ..._ripples.map((r) => _RippleWidget(ripple: r)),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            formatArabic(widget.count),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 56,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -1,
                              shadows: [
                                Shadow(
                                  color: Color(0x66000000),
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'صلاة اليوم',
                            style: TextStyle(
                              color: Color(0xE6ECFDF5),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Container(
                            width: 64,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            alignment: Alignment.centerRight,
                            child: Container(
                              width: 32,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'صَلِّ عَلَيْهِ',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 4,
                              shadows: [
                                Shadow(
                                  color: Color(0x66000000),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Ripple {
  _Ripple({required this.position, required this.controller});
  final Offset position;
  final AnimationController controller;
}

class _RippleWidget extends StatelessWidget {
  const _RippleWidget({required this.ripple});
  final _Ripple ripple;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ripple.controller,
      builder: (_, __) {
        final t = ripple.controller.value;
        // Position relative to the 256×256 inner circle. The button center is
        // at (128,128); ripple.position is relative to that same coordinate
        // space because GestureDetector wraps the circle.
        final dx = ripple.position.dx - 128;
        final dy = ripple.position.dy - 128;
        return Positioned(
          left: 128 + dx - 10,
          top: 128 + dy - 10,
          child: Opacity(
            opacity: 0.4 * (1 - t),
            child: Transform.scale(
              scale: 1 + t * 1.5,
              child: Container(
                width: 20,
                height: 20,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RotatingRing extends StatelessWidget {
  const _RotatingRing({
    required this.controller,
    required this.size,
    required this.color,
    required this.strokeWidth,
  });

  final AnimationController controller;
  final double size;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        return Transform.rotate(
          angle: controller.value * 2 * 3.14159,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.5), width: strokeWidth),
            ),
          ),
        );
      },
    );
  }
}
