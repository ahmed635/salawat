import 'package:flutter/material.dart';

import '../../theme/colors.dart';

/// Branded launch splash with an entrance animation (logo fade + scale) and a
/// looping three-dot loader. `_AuthGate` keeps this on screen for a minimum
/// duration so the animation always plays, even when sign-in resolves instantly.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Plays once: logo + text ease in.
  late final AnimationController _entrance;
  // Loops: drives the three-dot loader.
  late final AnimationController _dots;
  // Loops (reversing): gentle "breathing" pulse + glow on the logo.
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
    _dots = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _entrance.dispose();
    _dots.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    final scale = Tween(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _entrance, curve: Curves.easeOutBack),
    );

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [AppColors.teal600, AppColors.emerald900],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FadeTransition(
                  opacity: fade,
                  child: ScaleTransition(
                    scale: scale,
                    // Continuous breathing pulse + glow once the logo is in.
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, child) {
                        final t = Curves.easeInOut.transform(_pulse.value);
                        return Transform.scale(
                          scale: 1.0 + 0.05 * t,
                          child: Container(
                            width: 130,
                            height: 130,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 30,
                                  offset: const Offset(0, 12),
                                ),
                                // Pulsing emerald halo.
                                BoxShadow(
                                  color: AppColors.emerald400
                                      .withValues(alpha: 0.25 + 0.35 * t),
                                  blurRadius: 24 + 26 * t,
                                  spreadRadius: 2 + 6 * t,
                                ),
                              ],
                            ),
                            child: child,
                          ),
                        );
                      },
                      child: ClipOval(
                        child: Image.asset(
                          'assets/icon/app_icon_circle.png',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                FadeTransition(
                  opacity: fade,
                  child: const Text(
                    'صلوا عليه',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                FadeTransition(
                  opacity: fade,
                  child: Text(
                    'اللهم صلِّ وسلِّم على نبينا محمد',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 44),
                _DotsLoader(controller: _dots),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Three dots that pulse (scale + fade) in a staggered wave.
class _DotsLoader extends StatelessWidget {
  const _DotsLoader({required this.controller});
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            // Each dot is phase-shifted by 0.2 of the cycle. The triangle
            // wave (1 - |2t-1|) gives a smooth up-then-down pulse.
            final t = (controller.value - i * 0.2) % 1.0;
            final pulse = (1 - (t * 2 - 1).abs()).clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Opacity(
                opacity: 0.4 + 0.6 * pulse,
                child: Transform.scale(
                  scale: 0.6 + 0.4 * pulse,
                  child: Container(
                    width: 10,
                    height: 10,
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
      }),
    );
  }
}
