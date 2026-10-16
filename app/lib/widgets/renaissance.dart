import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Page scaffold: the "silk" gradient background, a phone-width column, a
/// scrolling body and an optional footer pinned to the bottom (used for the
/// primary action, like the sticky buttons in the Lovable design).
class Screen extends StatelessWidget {
  const Screen({
    super.key,
    required this.child,
    this.footer,
    this.background,
    this.onRefresh,
    this.center = false,
    this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 24),
  });

  final Widget child;
  final Widget? footer;

  /// Decorative layer drawn between the gradient and the content.
  final Widget? background;
  final Future<void> Function()? onRefresh;
  final bool center;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    Widget body = LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Padding(
            padding: padding,
            child: center ? Center(child: child) : Align(alignment: Alignment.topCenter, child: child),
          ),
        ),
      ),
    );
    if (onRefresh != null) {
      body = RefreshIndicator(color: c.primary, backgroundColor: c.card, onRefresh: onRefresh!, child: body);
    }

    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: const Alignment(-0.3, -1),
                  end: const Alignment(0.3, 1),
                  colors: [c.silkTop, c.silkBottom],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.6, -1),
                  radius: 1.1,
                  colors: [c.silkGlow.withValues(alpha: 0.7), Colors.transparent],
                ),
              ),
            ),
          ),
          if (background != null) Positioned.fill(child: IgnorePointer(child: background)),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 448),
                child: Column(
                  children: [
                    Expanded(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOut,
                        builder: (context, t, child) => Opacity(
                          opacity: t,
                          child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child),
                        ),
                        child: body,
                      ),
                    ),
                    if (footer != null) Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 16), child: footer),
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

/// Text filled with the parchment-to-gold-to-terracotta gradient.
class GoldText extends StatelessWidget {
  const GoldText(this.text, {super.key, required this.style, this.textAlign = TextAlign.center});

  final String text;
  final TextStyle style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [c.parchment, c.primary, c.accent],
        stops: const [0, 0.6, 1],
      ).createShader(rect),
      child: Text(text, textAlign: textAlign, style: style.copyWith(color: Colors.white)),
    );
  }
}

class Ornament extends StatelessWidget {
  const Ornament({super.key, this.padding = const EdgeInsets.symmetric(vertical: 16)});

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors.primary;
    Widget line(bool fadeLeft) => Container(
          width: 48,
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: fadeLeft ? [Colors.transparent, c] : [c, Colors.transparent],
            ),
          ),
        );
    return Padding(
      padding: padding,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          line(true),
          const SizedBox(width: 12),
          CustomPaint(size: const Size(18, 18), painter: _StarPainter(c)),
          const SizedBox(width: 12),
          line(false),
        ],
      ),
    );
  }
}

class _StarPainter extends CustomPainter {
  const _StarPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final path = Path()
      ..moveTo(12 * s, 2 * s)
      ..lineTo(14.5 * s, 9.5 * s)
      ..lineTo(22 * s, 12 * s)
      ..lineTo(14.5 * s, 14.5 * s)
      ..lineTo(12 * s, 22 * s)
      ..lineTo(9.5 * s, 14.5 * s)
      ..lineTo(2 * s, 12 * s)
      ..lineTo(9.5 * s, 9.5 * s)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.color != color;
}

enum GoldVariant { solid, outline, ghost }

class GoldButton extends StatefulWidget {
  const GoldButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = GoldVariant.solid,
    this.glow = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final GoldVariant variant;
  final bool glow;
  final bool busy;

  @override
  State<GoldButton> createState() => _GoldButtonState();
}

class _GoldButtonState extends State<GoldButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final solid = widget.variant == GoldVariant.solid;
    final fg = solid
        ? c.onPrimary
        : widget.variant == GoldVariant.outline
            ? c.primary
            : c.mutedForeground;

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      child: ExcludeSemantics(
        child: Opacity(
          opacity: widget.onPressed == null ? 0.4 : 1,
          child: AnimatedScale(
            scale: _pressed && _enabled ? 0.97 : 1,
            duration: const Duration(milliseconds: 100),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => setState(() => _pressed = true),
              onTapUp: (_) => setState(() => _pressed = false),
              onTapCancel: () => setState(() => _pressed = false),
              onTap: _enabled ? widget.onPressed : null,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
                decoration: BoxDecoration(
                  color: solid ? c.primary : null,
                  border: widget.variant == GoldVariant.outline ? Border.all(color: c.primary) : null,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: widget.glow && solid ? c.glow : null,
                ),
                alignment: Alignment.center,
                child: widget.busy
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: fg),
                      )
                    : Text(
                        widget.label.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: Typo.display(13, color: fg, letterSpacing: 2.6),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: c.card.withValues(alpha: 0.8),
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(2),
      ),
      child: child,
    );
  }
}

class TopBar extends StatelessWidget {
  const TopBar({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Semantics(
                button: true,
                label: 'Back',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => context.canPop() ? context.pop() : context.go('/home'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.arrow_back, size: 14, color: c.mutedForeground),
                        const SizedBox(width: 6),
                        Text('BACK', style: Typo.display(12, color: c.mutedForeground, letterSpacing: 2.4)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              title.toUpperCase(),
              textAlign: TextAlign.center,
              style: Typo.display(12, color: c.primary, letterSpacing: 3.6),
            ),
          ),
          SizedBox(width: 84, child: Align(alignment: Alignment.centerRight, child: trailing)),
        ],
      ),
    );
  }
}

class AuroraSwitch extends StatelessWidget {
  const AuroraSwitch({super.key, required this.value, required this.onChanged, required this.label});

  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      toggled: value,
      label: label,
      onTap: () => onChanged(!value),
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(!value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 44,
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              color: value ? c.primary.withValues(alpha: 0.25) : c.muted,
              border: Border.all(color: value ? c.primary : c.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 180),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(color: value ? c.primary : c.mutedForeground, shape: BoxShape.circle),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuroraChip extends StatelessWidget {
  const AuroraChip({super.key, required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: active,
      label: label,
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: active ? c.primary.withValues(alpha: 0.15) : null,
              border: Border.all(color: active ? c.primary : c.border),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Typo.sans(14, color: active ? c.primary : c.mutedForeground),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of chips that share the width equally (difficulty, challenge type).
class ChipRow extends StatelessWidget {
  const ChipRow({super.key, required this.options, required this.value, required this.onChanged, this.labelFor});

  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;
  final String Function(String)? labelFor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: AuroraChip(
              label: labelFor?.call(options[i]) ?? options[i],
              active: value == options[i],
              onTap: () => onChanged(options[i]),
            ),
          ),
        ],
      ],
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(text.toUpperCase(), style: Typo.display(12, color: context.colors.primary, letterSpacing: 3.6)),
    );
  }
}

/// Inline error and hint text in the serif italic voice of the design.
class InlineMessage extends StatelessWidget {
  const InlineMessage(this.text, {super.key, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Text(
      text,
      textAlign: TextAlign.center,
      style: Typo.serif(18, italic: true, color: isError ? c.accent : c.mutedForeground),
    );
  }
}

/// Underline-style text field decoration used by forms.
InputDecoration auroraInput(BuildContext context, {String? hint, bool box = false}) {
  final c = context.colors;
  final border = box
      ? OutlineInputBorder(borderRadius: BorderRadius.circular(2), borderSide: BorderSide(color: c.border))
      : UnderlineInputBorder(borderSide: BorderSide(color: c.border));
  final focused = box
      ? OutlineInputBorder(borderRadius: BorderRadius.circular(2), borderSide: BorderSide(color: c.primary))
      : UnderlineInputBorder(borderSide: BorderSide(color: c.primary));
  return InputDecoration(
    hintText: hint,
    hintStyle: Typo.sans(15, color: c.mutedForeground.withValues(alpha: 0.7)),
    isDense: true,
    contentPadding: EdgeInsets.symmetric(vertical: box ? 14 : 10, horizontal: box ? 12 : 0),
    enabledBorder: border,
    focusedBorder: focused,
  );
}

Future<bool> showConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final c = context.colors;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title.toUpperCase()),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text('Cancel', style: Typo.sans(14, color: c.mutedForeground)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel, style: Typo.sans(14, color: c.accent, weight: FontWeight.w600)),
        ),
      ],
    ),
  );
  return ok ?? false;
}
