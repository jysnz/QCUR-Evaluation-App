import 'package:flutter/material.dart';

const kAccent = Color(0xFF00FFD1);
const kBackground = Color(0xFF0A0A0B);
const kSurface = Color(0xFF161618);
const kForeground = Color(0xFFFFFFFF);
const kForegroundMuted = Color(0xFF888888);
const kRadius = 12.0;
const kPadding = 16.0;

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
      ..color = kAccent.withValues(alpha: 0.05)
      ..strokeWidth = 1.0;

    const spacing = 30.0;
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

  const TechnicalCard({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: kSurface.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(kRadius),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: child,
    );
  }
}

class TechnicalButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isLoading;
  final Color color;
  final IconData? icon;

  const TechnicalButton({
    super.key,
    required this.label,
    required this.onTap,
    this.isLoading = false,
    this.color = kAccent,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(kRadius),
      child: InkWell(
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(kRadius),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 20, color: Colors.black),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        label.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
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
