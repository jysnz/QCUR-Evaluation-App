import 'package:flutter/material.dart';
import 'package:qcur_evaluation/Pages/Auth/auth_widgets.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';

class WelcomePage extends StatelessWidget {
  final VoidCallback? onGoToDashboard;

  const WelcomePage({super.key, this.onGoToDashboard});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      body: Stack(
        children: [
          const AuthBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: kPadding,
                  vertical: kPaddingLarge,
                ),
                child: ResponsiveContainer(
                  maxWidth: kMaxWidthForm,
                  child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _SuccessBadge(),
                    const SizedBox(height: 28),
                    Text(
                      'You\'re all set!',
                      textAlign: TextAlign.center,
                      style: AppTypography.h1,
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Your account is ready. Start tracking your training activities right away.',
                        textAlign: TextAlign.center,
                        style: AppTypography.body.copyWith(
                          color: kForegroundMuted,
                          height: 1.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    AuthGlassCard(
                      padding: const EdgeInsets.all(kPaddingLarge),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: const [
                          _CheckItem(
                            icon: Icons.person_rounded,
                            label: 'Profile created successfully',
                          ),
                          _CheckDivider(),
                          _CheckItem(
                            icon: Icons.insights_rounded,
                            label: 'Ready to track training activities',
                          ),
                          _CheckDivider(),
                          _CheckItem(
                            icon: Icons.dashboard_rounded,
                            label: 'Access your dashboard anytime',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    AppButton(
                      label: 'Go to Dashboard',
                      onTap: onGoToDashboard,
                      icon: Icons.arrow_forward_rounded,
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

/// Layered, glowing checkmark badge that animates in for a polished
/// success moment. Replaces the old logo image.
class _SuccessBadge extends StatelessWidget {
  const _SuccessBadge();

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Center(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: reduceMotion ? 1.0 : 0.0, end: 1.0),
        duration: const Duration(milliseconds: 600),
        curve: Curves.elasticOut,
        builder: (context, value, child) {
          return Transform.scale(
            scale: value.clamp(0.0, 1.0),
            child: child,
          );
        },
        child: Container(
          width: 132,
          height: 132,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: kAccent.withValues(alpha: 0.06),
          ),
          child: Container(
            width: 100,
            height: 100,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: kAccent.withValues(alpha: 0.12),
              border: Border.all(
                color: kAccent.withValues(alpha: 0.25),
                width: 1.5,
              ),
            ),
            child: Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [kAccentLight, kAccentDark],
                ),
                boxShadow: [
                  BoxShadow(
                    color: kAccent.withValues(alpha: 0.4),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 40,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _CheckItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: kAccent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(kRadiusSmall),
          ),
          child: Icon(icon, size: 18, color: kAccent),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            label,
            style: AppTypography.body.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
        Icon(
          Icons.check_circle_rounded,
          size: 18,
          color: kAccent.withValues(alpha: 0.8),
        ),
      ],
    );
  }
}

class _CheckDivider extends StatelessWidget {
  const _CheckDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Divider(
        height: 1,
        thickness: 1,
        color: kBorder.withValues(alpha: 0.3),
      ),
    );
  }
}
