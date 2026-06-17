import 'package:flutter/material.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';

class AuthBackground extends StatelessWidget {
  const AuthBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const TechnicalGridBackground();
  }
}

class AuthGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  const AuthGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.radius = kRadius,
  });

  @override
  Widget build(BuildContext context) {
    return TechnicalCard(
      padding: padding,
      child: child,
    );
  }
}

class AuthTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final TextInputType keyboardType;
  final bool enabled;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.icon,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      enabled: enabled,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: enabled ? kForeground : kForegroundMuted,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label.toUpperCase(),
        labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: kForegroundMuted,
          letterSpacing: 1.0,
        ),
        prefixIcon: Icon(icon, color: kAccent.withValues(alpha: 0.7), size: 20),
        filled: true,
        fillColor: kBackground.withValues(alpha: 0.5),
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadius),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadius),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadius),
          borderSide: const BorderSide(color: kAccent, width: 1.5),
        ),
      ),
    );
  }
}

class AuthButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool isLoading;
  final Color color;

  const AuthButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.color = kAccent,
  });

  @override
  Widget build(BuildContext context) {
    return TechnicalButton(
      label: label,
      onTap: onPressed,
      isLoading: isLoading,
      color: color,
    );
  }
}
