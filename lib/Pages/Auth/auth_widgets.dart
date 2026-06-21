import 'package:flutter/material.dart';
import 'package:qcur_evaluation/Widgets/design_system.dart';

class AuthBackground extends StatelessWidget {
  const AuthBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppBackground(child: SizedBox.expand());
  }
}

class AuthGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const AuthGlassCard({
    super.key,
    required this.child,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: padding ?? const EdgeInsets.all(kPaddingLarge),
      child: child,
    );
  }
}

class AuthTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType keyboardType;
  final bool enabled;
  final bool dense;

  const AuthTextField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.enabled = true,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: controller,
      label: label,
      hint: hint,
      icon: icon,
      isObscure: obscureText,
      keyboardType: keyboardType,
      dense: dense,
    );
  }
}

class AuthButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final bool isLoading;
  final Color color;
  final IconData? icon;
  final bool dense;

  const AuthButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.color = kAccent,
    this.icon,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: label,
      onTap: onPressed,
      isLoading: isLoading,
      color: color,
      icon: icon,
      dense: dense,
    );
  }
}

