import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// WinPilot mark: four Windows-style panes on a blue-violet gradient tile.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 96, this.animate = false});

  final double size;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: AppColors.electricBlue.withValues(alpha: 0.45),
            blurRadius: size * 0.45,
            spreadRadius: 1,
          ),
        ],
      ),
      padding: EdgeInsets.all(size * 0.22),
      child: Column(
        children: [
          Expanded(child: _row()),
          SizedBox(height: size * 0.05),
          Expanded(child: _row()),
        ],
      ),
    );
    if (!animate) return tile;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOut,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.85 + 0.15 * value, child: child),
      ),
      child: tile,
    );
  }

  Widget _row() => Row(
        children: [
          Expanded(child: _pane()),
          SizedBox(width: size * 0.05),
          Expanded(child: _pane()),
        ],
      );

  Widget _pane() => Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(size * 0.04),
        ),
      );
}

/// Rounded card with a subtle gradient in dark mode and a soft shadow in light.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.glow,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(22);
    final decoration = BoxDecoration(
      gradient: dark ? AppColors.cardGradient : null,
      color: dark ? null : Colors.white,
      borderRadius: radius,
      border: Border.all(
        color: (glow ?? (dark ? AppColors.outline : Colors.black)).withValues(alpha: dark ? 0.45 : 0.06),
      ),
      boxShadow: [
        BoxShadow(
          color: (glow ?? Colors.black).withValues(alpha: dark ? 0.35 : 0.06),
          blurRadius: 24,
          offset: const Offset(0, 10),
        ),
      ],
    );
    final content = Padding(padding: padding, child: child);
    return Container(
      decoration: decoration,
      child: ClipRRect(
        borderRadius: radius,
        child: onTap == null
            ? content
            : Material(
                color: Colors.transparent,
                child: InkWell(onTap: onTap, child: content),
              ),
      ),
    );
  }
}

/// Primary call-to-action with a press-scale micro-interaction.
class GradientButton extends StatefulWidget {
  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.expand = true,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool expand;

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.loading;
    final child = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.loading)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
          )
        else if (widget.icon != null)
          Icon(widget.icon, color: Colors.white, size: 20),
        if (widget.loading || widget.icon != null) const SizedBox(width: 10),
        Flexible(
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
          ),
        ),
      ],
    );
    return AnimatedScale(
      scale: _pressed ? 0.97 : 1,
      duration: const Duration(milliseconds: 120),
      child: AnimatedOpacity(
        opacity: enabled || widget.loading ? 1 : 0.45,
        duration: const Duration(milliseconds: 200),
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                if (enabled)
                  BoxShadow(
                    color: AppColors.electricBlue.withValues(alpha: 0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
              ],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: enabled ? widget.onPressed : null,
              onHighlightChanged: (v) => setState(() => _pressed = v),
              child: Container(
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 5)],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
          ],
        ),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(text,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value, this.valueColor, this.trailing});

  final String label;
  final String value;
  final Color? valueColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted)),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: valueColor ?? theme.colorScheme.onSurface,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 4), trailing!],
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: AppColors.violet.withValues(alpha: 0.3), blurRadius: 24),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 18),
            Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            if (body != null) ...[
              const SizedBox(height: 8),
              Text(body!, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.textMuted)),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Pulsing placeholder used while data loads.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({super.key, this.height = 16, this.width, this.radius = 10});

  final double height;
  final double? width;
  final double radius;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 0.35, end: 0.9).animate(_c),
        child: Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      );
}
