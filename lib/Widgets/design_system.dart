import 'package:flutter/material.dart';

// --- COLOR PALETTE (UI/UX PRO MAX - Premium Minimalist) ---
const kAccent = Color(0xFF22C55E); // Emerald Green (Friendlier)
const kAccentLight = Color(0xFF4ADE80);
const kAccentDark = Color(0xFF166534);
const kBackground = Color(0xFF020617); // Dark Navy
const kSurface = Color(0xFF0F172A); // Slate
const kSurfaceElevated = Color(0xFF1E293B); // Lighter Slate
const kForeground = Color(0xFFF8FAFC); // High Emphasis
const kForegroundMuted = Color(0xFF94A3B8); // Medium Emphasis
const kForegroundDisabled = Color(0xFF475569); // Low Emphasis
const kError = Color(0xFFEF4444);
const kSuccess = Color(0xFF22C55E);
const kWarning = Color(0xFFF59E0B);
const kInfo = Color(0xFF3B82F6);
const kBorder = Color(0xFF334155);

// --- DESIGN TOKENS ---
const kRadius = 16.0;
const kRadiusLarge = 24.0;
const kRadiusSmall = 12.0;
const kPadding = 16.0;
const kPaddingLarge = 24.0;
const kPaddingSmall = 8.0;

// --- ELEVATION ---
const List<BoxShadow> kCardShadow = [
  BoxShadow(
    color: Color(0x28000000),
    blurRadius: 10,
    spreadRadius: 0,
    offset: Offset(0, 3),
  ),
];

// --- TYPOGRAPHY (Clean & Friendly) ---
class AppTypography {
  static const TextStyle h1 = TextStyle(
    color: kForeground,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
  );

  static const TextStyle h2 = TextStyle(
    color: kForeground,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );

  static const TextStyle h3 = TextStyle(
    color: kForeground,
    fontSize: 18,
    fontWeight: FontWeight.w600,
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

  static const TextStyle label = TextStyle(
    color: kForegroundMuted,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );

  static const TextStyle overline = TextStyle(
    color: kForegroundMuted,
    fontSize: 10,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.2,
  );
}

// --- COMPONENTS ---

class AppBackground extends StatelessWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: kBackground,
        gradient: RadialGradient(
          center: Alignment(-0.8, -0.6),
          radius: 1.5,
          colors: [
            Color(0xFF0F172A),
            kBackground,
          ],
        ),
      ),
      child: child,
    );
  }
}

class TechnicalGridBackground extends StatelessWidget {
  const TechnicalGridBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _GridPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = kBorder.withValues(alpha: 0.05)
      ..strokeWidth = 1.0;

    const step = 32.0;

    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final double? radius;
  final Border? border;
  final List<BoxShadow>? boxShadow;

  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.color,
    this.radius,
    this.border,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding ?? const EdgeInsets.all(kPadding),
      decoration: BoxDecoration(
        color: color ?? kSurface,
        borderRadius: BorderRadius.circular(radius ?? kRadius),
        border: border ?? Border.all(color: kBorder.withValues(alpha: 0.5)),
        boxShadow: boxShadow ?? kCardShadow,
      ),
      child: child,
    );
  }
}

class AppButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isLoading;
  final Color color;
  final Color textColor;
  final IconData? icon;
  final bool isSecondary;
  final bool isFullWidth;

  const AppButton({
    super.key,
    required this.label,
    this.onTap,
    this.isLoading = false,
    this.color = kAccent,
    this.textColor = Colors.white,
    this.icon,
    this.isSecondary = false,
    this.isFullWidth = true,
  });

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final finalColor = widget.isSecondary ? Colors.transparent : widget.color;
    final finalTextColor = widget.isSecondary ? kForeground : widget.textColor;
    final isDisabled = widget.onTap == null;

    return GestureDetector(
      onTapDown: (_) { if (!isDisabled && !widget.isLoading) setState(() => _pressed = true); },
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: isDisabled ? 0.5 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: Material(
            color: isDisabled ? kForegroundDisabled.withValues(alpha: 0.3) : finalColor,
            borderRadius: BorderRadius.circular(kRadiusLarge),
            child: InkWell(
              onTap: (widget.isLoading || isDisabled) ? null : widget.onTap,
              borderRadius: BorderRadius.circular(kRadiusLarge),
              splashColor: Colors.white.withValues(alpha: 0.1),
              highlightColor: Colors.white.withValues(alpha: 0.05),
              child: Container(
                width: widget.isFullWidth ? double.infinity : null,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(kRadiusLarge),
                  border: widget.isSecondary ? Border.all(color: kBorder) : null,
                ),
                child: Center(
                  child: widget.isLoading
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
                            if (widget.icon != null) ...[
                              Icon(widget.icon, size: 20, color: finalTextColor),
                              const SizedBox(width: 12),
                            ],
                            Text(
                              widget.label,
                              style: TextStyle(
                                color: finalTextColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
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
  final int? maxLines;
  final TextAlign textAlign;
  final IconData? icon;

  const AppTextField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    this.isObscure = false,
    this.keyboardType = TextInputType.text,
    this.validator,
    this.maxLines = 1,
    this.textAlign = TextAlign.start,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(label, style: AppTypography.label),
        ),
        TextFormField(
          controller: controller,
          obscureText: isObscure,
          keyboardType: keyboardType,
          validator: validator,
          maxLines: maxLines,
          textAlign: textAlign,
          style: AppTypography.bodyLg,
          decoration: InputDecoration(
            prefixIcon: icon != null ? Icon(icon, size: 20, color: kForegroundMuted) : null,
            hintText: hint,
            hintStyle: TextStyle(color: kForegroundMuted.withValues(alpha: 0.5)),
            filled: true,
            fillColor: kSurfaceElevated.withValues(alpha: 0.5),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kRadius),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kRadius),
              borderSide: const BorderSide(color: kBorder, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kRadius),
              borderSide: const BorderSide(color: kAccent, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(kRadius),
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
              Text(title, style: AppTypography.h2),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(kRadiusSmall),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        label[0].toUpperCase() + label.substring(1),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

