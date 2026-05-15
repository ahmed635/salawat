import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/user_controller.dart';
import '../../theme/colors.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  String _value = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSubmit => _value.trim().length >= 2;

  /// Mirrors the validator wired into the TextFormField. Returns null when
  /// the value is acceptable, otherwise the Arabic message to display
  /// underneath the field.
  String? _validateName(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return 'الاسم مطلوب';
    if (s.length < 2) return 'يجب أن يكون الاسم حرفين على الأقل';
    return null;
  }

  Future<void> _submit() async {
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;
    await ref.read(userNameControllerProvider.notifier).save(_value);
  }

  @override
  Widget build(BuildContext context) {
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  elevation: 24,
                  shadowColor: Colors.black.withValues(alpha: 0.4),
                  child: Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      border: const Border(
                        top: BorderSide(color: AppColors.emerald400, width: 4),
                      ),
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          buildLogo(),
                          const SizedBox(height: 24),
                          buildTitle(),
                          const SizedBox(height: 12),
                          buildTitleDescription(),
                          const SizedBox(height: 28),
                          buildNameTextField(),
                          const SizedBox(height: 16),
                          buildOkeyButton(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Container buildLogo() {
    return Container(
      width: 96,
      height: 96,
      decoration: const BoxDecoration(
        color: Color(0xFFECFDF5), // emerald-50
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.brightness_2,
        size: 48,
        color: AppColors.emerald600,
      ),
    );
  }

  Text buildTitleDescription() {
    return const Text(
      'شارك في أعظم تحدي يومي. سجل اسمك وانضم لآلاف الذاكرين.',
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 13,
        color: AppColors.slate500,
        height: 1.6,
      ),
    );
  }

  Text buildTitle() {
    return const Text(
      'صلوا عليه',
      style: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w900,
        color: AppColors.slate800,
        letterSpacing: -0.5,
      ),
    );
  }

  TextFormField buildNameTextField() {
    return TextFormField(
      controller: _controller,
      textAlign: TextAlign.center,
      textInputAction: TextInputAction.done,
      onChanged: (v) => setState(() => _value = v),
      onFieldSubmitted: (_) => _submit(),
      // Show validation errors as soon as the user starts typing,
      // rather than only after the first submit attempt.
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: _validateName,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.slate800,
      ),
      decoration: InputDecoration(
        hintText: 'اكتب اسمك للوحة الشرف...',
        hintStyle: const TextStyle(
          color: AppColors.slate400,
          fontWeight: FontWeight.w500,
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.all(16),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: Color(0xFFD1FAE5), // emerald-100
            width: 2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: AppColors.emerald500,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.red500, width: 2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.red500, width: 2),
        ),
      ),
    );
  }

  SizedBox buildOkeyButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.emerald600,
          disabledBackgroundColor: const Color(0xFF6EE7B7),
          // emerald-300
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        onPressed: _canSubmit ? _submit : null,
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('توكلنا على الله'),
            SizedBox(width: 8),
            Icon(Icons.chevron_left, size: 20),
          ],
        ),
      ),
    );
  }
}
