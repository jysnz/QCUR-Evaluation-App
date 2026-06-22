import 'package:flutter/material.dart';
import 'package:qcur_evaluation/Pages/Auth/auth_widgets.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';

class ForgotPasswordPage extends StatelessWidget {
  const ForgotPasswordPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          const AuthBackground(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                child: ResponsiveContainer(
                  maxWidth: kMaxWidthForm,
                  child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: kAccent.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: kAccent.withValues(alpha: 0.2)),
                      ),
                      child: const Icon(Icons.construction_rounded, size: 64, color: kAccent),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'Coming Soon',
                      textAlign: TextAlign.center,
                      style: AppTypography.h1,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'This feature is currently under development. Please check back later.',
                      textAlign: TextAlign.center,
                      style: AppTypography.body.copyWith(color: kForegroundMuted),
                    ),
                    const SizedBox(height: 48),
                    AuthGlassCard(
                      child: Column(
                        children: [
                          Text(
                            'Status',
                            style: AppTypography.label.copyWith(color: kAccent),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Working on it',
                            style: AppTypography.h3,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    AppButton(
                      label: 'Back to Sign In',
                      isSecondary: true,
                      onTap: () => Navigator.of(context).pop(),
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
