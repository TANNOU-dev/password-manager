import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:password_manager/core/design/tokens.dart';

/// Lisibilité de la palette, mesurée plutôt que jugée à l'œil.
///
/// Une palette se choisit sur écran, mais se vérifie au calcul : le ratio de
/// contraste de la WCAG dit si un texte reste lisible, et il ne dépend ni de
/// l'écran ni de l'humeur. C'est particulièrement utile ici parce que le thème
/// sombre pose du texte **foncé** sur le bleu d'accent — l'inverse du réflexe
/// habituel, et une erreur invisible tant qu'on ne mesure pas.
///
/// Seuils de la WCAG 2.1 :
///   * 4,5:1 pour un texte courant (AA) ;
///   * 3:1 pour un grand texte et pour les éléments d'interface.

/// Luminance relative, formule WCAG 2.1.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

/// Aplatit une couleur semi-transparente sur son fond, sans quoi on mesurerait
/// le contraste d'un pixel qui n'existe pas.
Color _over(Color foreground, Color background) {
  final a = foreground.a;
  return Color.from(
    alpha: 1,
    red: foreground.r * a + background.r * (1 - a),
    green: foreground.g * a + background.g * (1 - a),
    blue: foreground.b * a + background.b * (1 - a),
  );
}

void main() {
  for (final entry in {'sombre': AppColors.dark, 'clair': AppColors.light}
      .entries) {
    final theme = entry.key;
    final c = entry.value;

    group('thème $theme', () {
      test('le texte courant est lisible sur chaque surface', () {
        for (final surface in {
          'fond': c.background,
          'surface': c.surface,
          'surface surélevée': c.surfaceRaised,
          'surface creusée': c.surfaceSunken,
        }.entries) {
          expect(
            _contrast(c.textPrimary, surface.value),
            greaterThanOrEqualTo(4.5),
            reason: 'texte principal sur ${surface.key}',
          );
        }
      });

      test('le texte secondaire tient le seuil du texte courant', () {
        expect(_contrast(c.textSecondary, c.background),
            greaterThanOrEqualTo(4.5));
        expect(_contrast(c.textSecondary, c.surface),
            greaterThanOrEqualTo(4.5));
      });

      test('le texte tertiaire tient au moins le seuil des grands textes', () {
        // Il ne sert qu'aux mentions d'appoint, jamais à un contenu qu'on doit
        // lire pour agir.
        expect(_contrast(c.textTertiary, c.background),
            greaterThanOrEqualTo(3.0));
      });

      test('le texte des boutons pleins est lisible sur l’accent', () {
        // Le cas qui justifie ce fichier. En thème sombre l'accent est clair,
        // donc `onPrimary` est foncé ; un blanc y tomberait sous 2:1.
        expect(
          _contrast(c.onPrimary, c.primary),
          greaterThanOrEqualTo(4.5),
          reason: 'onPrimary sur primary',
        );
      });

      test('les couleurs d’état se détachent du fond', () {
        for (final state in {
          'succès': c.success,
          'avertissement': c.warning,
          'danger': c.danger,
          'accent': c.accent,
        }.entries) {
          expect(
            _contrast(state.value, c.background),
            greaterThanOrEqualTo(3.0),
            reason: '${state.key} sur le fond',
          );
        }
      });

      test('les liserés restent visibles une fois aplatis', () {
        // Ils portent toute la profondeur de l'interface : il n'y a pas
        // d'ombres portées pour prendre le relais s'ils disparaissent.
        final hairline = _over(c.hairline, c.surface);
        expect(_contrast(hairline, c.surface), greaterThan(1.03),
            reason: 'un liseré invisible ne dessine plus le bord des cartes');
      });
    });
  }

  test('les deux thèmes ne partagent aucune couleur de fond', () {
    // Garde-fou contre un copier-coller entre les deux blocs : c'est arrivé.
    expect(AppColors.dark.background, isNot(AppColors.light.background));
    expect(AppColors.dark.textPrimary, isNot(AppColors.light.textPrimary));
    expect(AppColors.dark.primary, isNot(AppColors.light.primary));
  });
}
