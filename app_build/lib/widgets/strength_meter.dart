import 'package:flutter/material.dart';

import '../core/design/app_theme.dart';
import '../core/design/tokens.dart';
import '../core/utils/password_strength.dart';

/// Jauge de robustesse. Segmentée plutôt que continue : cinq paliers se lisent
/// d'un coup d'œil, là où une barre lisse invite à comparer des nuances qui
/// n'ont pas de sens.
class StrengthMeter extends StatelessWidget {
  const StrengthMeter({
    super.key,
    required this.strength,
    this.showLabel = true,
    this.showWarnings = true,
  });

  final PasswordStrength strength;
  final bool showLabel;
  final bool showWarnings;

  static const int _segments = 5;

  Color _colorFor(AppColors c) => switch (strength.level) {
        StrengthLevel.empty => c.hairlineStrong,
        StrengthLevel.veryWeak || StrengthLevel.weak => c.danger,
        StrengthLevel.fair => c.warning,
        StrengthLevel.strong || StrengthLevel.veryStrong => c.success,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    final color = _colorFor(c);
    final filled = (strength.level.fraction * _segments).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            for (var i = 0; i < _segments; i++) ...[
              if (i > 0) const SizedBox(width: Gap.xs),
              Expanded(
                child: _Segment(
                  color: i < filled ? color : c.surfaceSunken,
                ),
              ),
            ],
          ],
        ),
        if (showLabel) ...[
          const SizedBox(height: Gap.sm),
          Row(
            children: [
              // L'information est portée deux fois, par la teinte et par le mot :
              // la jauge reste lisible en cas de daltonisme.
              AnimatedDefaultTextStyle(
                duration: Motion.fast,
                style: text.labelMedium!.copyWith(
                  color: strength.level == StrengthLevel.empty
                      ? c.textTertiary
                      : color,
                ),
                child: Text(strength.level.label),
              ),
              const Spacer(),
              if (strength.entropyBits > 0)
                Text(
                  '${strength.entropyBits.round()} bits',
                  style: AppFonts.mono(
                    text.bodySmall!.copyWith(color: c.textTertiary, fontSize: 12),
                  ),
                ),
            ],
          ),
        ],
        if (showWarnings && strength.warnings.isNotEmpty) ...[
          const SizedBox(height: Gap.sm),
          for (final warning in strength.warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.info_outline_rounded,
                      size: 14,
                      color: c.textTertiary,
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(
                      warning,
                      style: text.bodySmall
                          ?.copyWith(color: c.textTertiary, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

/// Un segment de la jauge. La transition de couleur évite que la barre
/// clignote à chaque frappe.
class _Segment extends StatelessWidget {
  const _Segment({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.standard,
      height: 5,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
