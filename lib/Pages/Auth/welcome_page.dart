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
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
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
                      child: const Icon(Icons.rocket_launch_outlined, size: 48, color: kAccent),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'Welcome!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Your account is ready. You can now start using the app.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 48),
                    AuthButton(
                      label: 'Go to Dashboard',
                      onPressed: onGoToDashboard ?? () {},
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
