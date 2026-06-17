import 'package:flutter/material.dart';

// --- COLOR PALETTE (UI/UX PRO MAX - Professional Dark Theme) ---
const kAccent = Color(0xFF00FFD1); // Primary Brand Color
const kAccentDark = Color(0xFF00BFA5);
const kBackground = Color(0xFF0A0A0B); // Deep Dark
const kSurface = Color(0xFF161618); // Elevated Surface
const kSurfaceElevated = Color(0xFF1F1F22); // More Elevation
const kForeground = Color(0xFFFFFFFF); // High Emphasis Text
const kForegroundMuted = Color(0xFF8E8E93); // Medium Emphasis
const kForegroundDisabled = Color(0xFF48484A); // Low Emphasis
const kError = Color(0xFFFF453A);
const kSuccess = Color(0xFF32D74B);
const kWarning = Color(0xFFFF9F0A);
const kInfo = Color(0xFF0A84FF);

// --- DESIGN TOKENS ---
const kRadius = 12.0;
const kRadiusSmall = 8.0;
const kPadding = 16.0;
const kPaddingLarge = 24.0;
const kPaddingSmall = 8.0;

// --- TYPOGRAPHY (Professional Scale) ---
class AppTypography {
  static const TextStyle h1 = TextStyle(
    color: kForeground,
    fontSize: 24,
    fontWeight: FontWeight.w900,
    letterSpacing: -0.5,
  );

  static const TextStyle h2 = TextStyle(
    color: kForeground,
    fontSize: 20,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.2,
  );

  static const TextStyle h3 = TextStyle(
    color: kForeground,
    fontSize: 16,
    fontWeight: FontWeight.w800,
  );

  static const TextStyle bodyLg = TextStyle(
    color: kForeground,
    fontSize: 16,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle body = TextStyle(
    color: kForeground,
    fontSize: 14,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle caption = TextStyle(
    color: kForegroundMuted,
    fontSize: 12,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle overline = TextStyle(
    color: kAccent,
    fontSize: 10,
    fontWeight: FontWeight.w900,
    letterSpacing: 2.0,
  );
}

// --- COMPONENTS ---

class TechnicalGridBackground extends StatelessWidget {
  const TechnicalGridBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: kBackground,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: GridPainter(),
            ),
          ),
        ],
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = kAccent.withValues(alpha: 0.03)
      ..strokeWidth = 1.0;

    const spacing = 32.0; // Standard 8dp multiple
    for (double i = 0; i < size.width; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += spacing) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class TechnicalCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  final double? radius;
  final Border? border;

  const TechnicalCard({
    super.key,
    required this.child,
    this.padding,
    this.color,
    this.radius,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(kPadding),
      decoration: BoxDecoration(
        color: color ?? kSurface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(radius ?? kRadius),
        border: border ?? Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: child,
    );
  }
}

class TechnicalButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isLoading;
  final Color color;
  final Color textColor;
  final IconData? icon;
  final bool isSecondary;

  const TechnicalButton({
    super.key,
    required this.label,
    this.onTap,
    this.isLoading = false,
    this.color = kAccent,
    this.textColor = Colors.black,
    this.icon,
    this.isSecondary = false,
  });

  @override
  Widget build(BuildContext context) {
    final finalColor = isSecondary ? kSurface : color;
    final finalTextColor = isSecondary ? kForeground : textColor;

    return Material(
      color: onTap == null ? kForegroundDisabled : finalColor,
      borderRadius: BorderRadius.circular(kRadius),
      child: InkWell(
        onTap: (isLoading || onTap == null) ? null : onTap,
        borderRadius: BorderRadius.circular(kRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          child: Center(
            child: isLoading
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: finalTextColor,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 20, color: finalTextColor),
                        const SizedBox(width: 12),
                      ],
                      Text(
                        label.toUpperCase(),
                        style: TextStyle(
                          color: finalTextColor,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class AppTextField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final bool isObscure;
  final TextInputType keyboardType;
  final String? Function(String?)? validator;

  const AppTextField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    this.isObscure = false,
    this.keyboardType = TextInputType.text,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: AppTypography.overline),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: isObscure,
          keyboardType: keyboardType,
          validator: validator,
          style: AppTypography.bodyLg.copyWith(fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: kForeground.withValues(alpha: 0.2)),
            filled: true,
            fillColor: kSurfaceElevated,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kRadiusSmall),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kRadiusSmall),
              borderSide: const BorderSide(color: Colors.white10),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kRadiusSmall),
              borderSide: const BorderSide(color: kAccent, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kRadiusSmall),
              borderSide: const BorderSide(color: kError, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title.toUpperCase(), style: AppTypography.h2),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: AppTypography.caption),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class AppStatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const AppStatusBadge({
    super.key,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
