import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/design/app_theme.dart';
import '../core/design/tokens.dart';
import '../core/lock/clipboard_guard.dart';

/// Petits composants partagés par les écrans.

/// Étiquette de section : petites capitales espacées.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Carte à liseré. Le conteneur de base de tous les écrans.
class HairlineCard extends StatelessWidget {
  const HairlineCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Gap.lg),
    this.onTap,
    this.sunken = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool sunken;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final decorated = Container(
      decoration: BoxDecoration(
        borderRadius: Radii.all(Radii.lg),
        border: Border.all(color: c.hairline),
      ),
      padding: padding,
      child: child,
    );

    return Material(
      color: sunken ? c.surfaceSunken : c.surface,
      borderRadius: Radii.all(Radii.lg),
      child: onTap == null
          ? decorated
          : InkWell(
              onTap: onTap,
              borderRadius: Radii.all(Radii.lg),
              child: decorated,
            ),
    );
  }
}

/// État vide. Toujours une explication et une action, jamais une icône seule.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.xxxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: c.surface,
                shape: BoxShape.circle,
                border: Border.all(color: c.hairline),
              ),
              child: Icon(icon, size: 30, color: c.textTertiary),
            ),
            const SizedBox(height: Gap.xl),
            Text(title, style: text.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: Gap.sm),
            Text(
              message,
              style: text.bodyMedium?.copyWith(color: c.textTertiary),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: Gap.xxl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Bandeau d'erreur en ligne. Pour ce qui doit rester visible, contrairement à
/// un snackbar qui disparaît avant d'être lu.
class InlineError extends StatelessWidget {
  const InlineError({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: c.dangerWash,
        borderRadius: Radii.all(Radii.md),
        border: Border.all(color: c.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 18, color: c.danger),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Text(
              message,
              style: text.bodySmall?.copyWith(color: c.danger),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Réessayer'),
            ),
        ],
      ),
    );
  }
}

/// Retours utilisateur. Centralisés pour que la copie d'un secret ait toujours
/// la même forme et la même durée.
abstract final class AppFeedback {
  static void show(
    BuildContext context,
    String message, {
    IconData? icon,
    Color? tint,
  }) {
    final c = context.palette;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: tint ?? c.success),
              const SizedBox(width: Gap.md),
            ],
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }

  static void copied(BuildContext context, String what) {
    show(context, '$what copié', icon: Icons.check_rounded);
  }

  static void failure(BuildContext context, String message) {
    show(
      context,
      message,
      icon: Icons.error_outline_rounded,
      tint: context.palette.danger,
    );
  }

  /// Copie et confirme, avec un retour haptique léger : sur mobile, le geste le
  /// plus fréquent mérite une confirmation qu'on sent sans regarder.
  ///
  /// Passe par `ClipboardGuard`, qui programme l'effacement automatique. Tous les
  /// écrans copient par ici, donc aucun n'a à y penser. Le repli direct sur
  /// `Clipboard` sert aux tests de rendu, qui ne montent pas les providers.
  static Future<void> copyValue(
    BuildContext context,
    String value,
    String what,
  ) async {
    ClipboardGuard? guard;
    try {
      guard = context.read<ClipboardGuard>();
    } on ProviderNotFoundException {
      guard = null;
    }

    if (guard != null) {
      await guard.copy(value);
    } else {
      await Clipboard.setData(ClipboardData(text: value));
    }
    await HapticFeedback.selectionClick();
    if (context.mounted) copied(context, what);
  }
}

/// Ligne d'information en lecture seule, avec copie optionnelle.
class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.label,
    required this.value,
    this.monospace = false,
    this.copyable = false,
    this.copyLabel,
  });

  final String label;
  final String value;
  final bool monospace;
  final bool copyable;
  final String? copyLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    if (value.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: text.labelSmall),
                const SizedBox(height: Gap.xs),
                Text(
                  value,
                  style: monospace
                      ? SecretText.of(context, size: 14)
                      : text.bodyLarge,
                ),
              ],
            ),
          ),
          if (copyable)
            IconButton(
              tooltip: 'Copier',
              onPressed: () => AppFeedback.copyValue(
                context,
                value,
                copyLabel ?? label,
              ),
              icon: Icon(
                Icons.content_copy_outlined,
                size: 18,
                color: c.textTertiary,
              ),
            ),
        ],
      ),
    );
  }
}

/// Fait apparaître ses enfants en cascade. Utilisé à l'ouverture d'une liste.
class StaggeredEntrance extends StatelessWidget {
  const StaggeredEntrance({
    super.key,
    required this.index,
    required this.child,
    this.maxIndex = 12,
  });

  final int index;
  final Widget child;

  /// Au-delà, on n'anime plus : décaler le centième élément d'une liste
  /// n'apporte rien et retarde son affichage.
  final int maxIndex;

  @override
  Widget build(BuildContext context) {
    if (index > maxIndex) return child;
    final delay = Motion.stagger * index;
    final total = Motion.normal + delay;

    // Pas de contrôleur par élément : on allonge la durée du délai voulu et on
    // reste immobile sur la première fraction de la course via un Interval.
    // Un `Interval` obtient le même décalage pour un widget sans état.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(
        (delay.inMilliseconds / total.inMilliseconds).clamp(0.0, 0.9),
        1,
        curve: Motion.enter,
      ),
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, 10 * (1 - t)), child: child),
      ),
      child: child,
    );
  }
}
