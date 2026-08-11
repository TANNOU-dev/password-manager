import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/design/app_theme.dart';
import '../core/design/tokens.dart';
import 'common.dart';

/// Affichage d'une valeur secrète : masquée par défaut, révélée par un
/// dé-floutage.
///
/// Le flou plutôt que des points : la longueur réelle reste perceptible, ce qui
/// aide à reconnaître le bon mot de passe, et la révélation devient un
/// mouvement continu au lieu d'une substitution brutale. Le texte reste en
/// chasse fixe pour qu'un `0` ne se confonde pas avec un `O`.
class SecretField extends StatefulWidget {
  const SecretField({
    super.key,
    required this.label,
    required this.value,
    this.initiallyRevealed = false,
    this.monospace = true,
    this.onCopied,
  });

  final String label;
  final String value;
  final bool initiallyRevealed;
  final bool monospace;

  /// Appelé après la copie, pour laisser l'appelant afficher son retour et
  /// programmer l'effacement du presse-papiers.
  final VoidCallback? onCopied;

  @override
  State<SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<SecretField> {
  late bool _revealed = widget.initiallyRevealed;
  bool _justCopied = false;

  Future<void> _copy() async {
    // Passe par AppFeedback, donc par ClipboardGuard : l'effacement automatique
    // s'applique aussi aux copies faites depuis un champ secret.
    await AppFeedback.copyValue(context, widget.value, widget.label);
    widget.onCopied?.call();
    if (!mounted) return;
    // Retour visuel sur le bouton lui-même : plus lisible qu'un snackbar qui
    // recouvre le bas de l'écran à chaque copie.
    setState(() => _justCopied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (mounted) setState(() => _justCopied = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    final valueStyle = widget.monospace
        ? SecretText.of(context)
        : text.bodyLarge!.copyWith(color: c.textPrimary);

    return Container(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.sm, Gap.md),
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: Radii.all(Radii.md),
        border: Border.all(color: c.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.label.toUpperCase(), style: text.labelSmall),
                const SizedBox(height: Gap.xs),
                _BlurReveal(
                  revealed: _revealed,
                  child: Text(
                    widget.value.isEmpty ? '—' : widget.value,
                    style: valueStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: _revealed ? 'Masquer' : 'Révéler',
            onPressed: () => setState(() => _revealed = !_revealed),
            icon: Icon(
              _revealed
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 20,
            ),
          ),
          IconButton(
            tooltip: 'Copier',
            onPressed: widget.value.isEmpty ? null : _copy,
            icon: AnimatedSwitcher(
              duration: Motion.fast,
              child: _justCopied
                  ? Icon(Icons.check_rounded, size: 20, color: c.success)
                  : const Icon(Icons.content_copy_outlined, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

/// Floute son enfant, et retire le flou en douceur à la révélation.
class _BlurReveal extends StatelessWidget {
  const _BlurReveal({required this.revealed, required this.child});

  final bool revealed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: revealed ? 0 : 6),
      duration: Motion.normal,
      curve: Motion.standard,
      builder: (context, sigma, child) {
        // En dessous du seuil, on retire complètement le filtre : appliquer un
        // ImageFilter de sigma nul coûte une passe de composition pour rien.
        if (sigma < 0.05) return child!;
        return ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.decal,
          ),
          child: child,
        );
      },
      child: child,
    );
  }
}
