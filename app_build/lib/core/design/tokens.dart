import 'package:flutter/widgets.dart';

/// Jetons de design de Coffort.
///
/// Une seule source pour les couleurs, les espacements, les rayons et les
/// durées. Les écrans ne doivent jamais écrire une valeur littérale : c'est ce
/// qui produisait l'incohérence de l'ancienne interface, où l'on trouvait des
/// rayons de 8, 10, 12, 16 et 20 sans logique.

/// Palette. La profondeur vient de surfaces empilées et d'un liseré interne de
/// 1 px, pas d'ombres portées : sur un fond très sombre une ombre ne se voit
/// pas, alors qu'un liseré clair dessine nettement le bord d'une carte.
class AppColors {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.hairline,
    required this.hairlineStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.primary,
    required this.primaryHover,
    required this.onPrimary,
    required this.primaryWash,
    required this.accent,
    required this.success,
    required this.warning,
    required this.danger,
    required this.dangerWash,
    required this.overlay,
  });

  final Color background;
  final Color surface;
  final Color surfaceRaised;

  /// Plus sombre que la surface : sert aux zones creusées (champ de saisie,
  /// bloc de mot de passe) pour signaler « ici on lit ou on écrit une donnée ».
  final Color surfaceSunken;

  final Color hairline;
  final Color hairlineStrong;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  final Color primary;
  final Color primaryHover;
  final Color onPrimary;

  /// Fond très dilué de la couleur d'accent, pour les pastilles et les états
  /// sélectionnés.
  final Color primaryWash;

  final Color accent;
  final Color success;
  final Color warning;
  final Color danger;
  final Color dangerWash;

  /// Voile posé derrière les feuilles et les boîtes de dialogue.
  final Color overlay;

  /// Thème sombre, aligné sur la palette de Bitwarden.
  ///
  /// Le gris y est franchement bleuté (#121A27 plutôt qu'un noir neutre), ce
  /// qui réchauffe l'ensemble et fait ressortir le bleu d'accent sans qu'il ait
  /// besoin d'être saturé.
  ///
  /// Le choix le moins évident est `onPrimary` : le bleu d'accent est *clair*,
  /// donc le texte posé dessus est sombre. C'est l'inverse du réflexe habituel
  /// (accent sombre, texte blanc), et c'est ce qui donne aux boutons pleins leur
  /// aspect reconnaissable. Un blanc sur ce bleu tomberait à 1,9:1 de contraste,
  /// très en dessous du seuil lisible.
  static const AppColors dark = AppColors(
    background: Color(0xFF121A27),
    surface: Color(0xFF202733),
    surfaceRaised: Color(0xFF303946),
    surfaceSunken: Color(0xFF171E2B),
    hairline: Color(0x1AFFFFFF),
    hairlineStrong: Color(0x2EFFFFFF),
    textPrimary: Color(0xFFF3F6F9),
    textSecondary: Color(0xFF96A3BB),
    textTertiary: Color(0xFF7A8699),
    primary: Color(0xFF65ABFF),
    primaryHover: Color(0xFF8FC3FF),
    onPrimary: Color(0xFF202733),
    primaryWash: Color(0x2665ABFF),
    accent: Color(0xFF65ABFF),
    success: Color(0xFF6BF178),
    warning: Color(0xFFFFBF00),
    danger: Color(0xFFFF4E63),
    dangerWash: Color(0x26FF4E63),
    overlay: Color(0x66000000),
  );

  /// Thème clair. Ici le bleu s'assombrit (#175DDC) et redevient un fond à
  /// texte blanc : c'est la contrainte de contraste qui commande, pas le goût.
  static const AppColors light = AppColors(
    background: Color(0xFFF3F6F9),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFEEF3F9),
    hairline: Color(0x1A1B2029),
    hairlineStrong: Color(0x2E1B2029),
    textPrimary: Color(0xFF1B2029),
    textSecondary: Color(0xFF5A6D91),
    textTertiary: Color(0xFF79808E),
    primary: Color(0xFF175DDC),
    primaryHover: Color(0xFF1A41AC),
    onPrimary: Color(0xFFFFFFFF),
    primaryWash: Color(0x1A175DDC),
    accent: Color(0xFF175DDC),
    success: Color(0xFF0C8018),
    warning: Color(0xFFAC5800),
    danger: Color(0xFFCB263A),
    dangerWash: Color(0x1ACB263A),
    overlay: Color(0x661B2029),
  );
}

/// Échelle d'espacement en multiples de 4. Utiliser ces constantes et rien
/// d'autre garantit un rythme vertical régulier d'un écran à l'autre.
abstract final class Gap {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double huge = 40;
  static const double giant = 48;
}

abstract final class Radii {
  /// Puces, badges.
  static const double xs = 6;

  /// Champs, petits boutons.
  static const double sm = 10;

  /// Boutons, pastilles d'icône.
  static const double md = 14;

  /// Cartes.
  static const double lg = 18;

  /// Feuilles modales.
  static const double xl = 28;

  static const Radius pill = Radius.circular(999);

  static BorderRadius all(double r) => BorderRadius.circular(r);
  static const BorderRadius sheet =
      BorderRadius.vertical(top: Radius.circular(xl));
}

/// Durées et courbes. Une animation d'interface dépasse rarement 300 ms : au
/// delà elle est perçue comme de la lenteur, pas comme de la fluidité.
abstract final class Motion {
  static const Duration instant = Duration(milliseconds: 90);
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration normal = Duration(milliseconds: 240);
  static const Duration slow = Duration(milliseconds: 360);

  /// Entrée d'un élément : démarre vite, finit en douceur.
  static const Curve enter = Curves.easeOutCubic;

  /// Sortie : l'inverse, pour que l'élément « parte » franchement.
  static const Curve exit = Curves.easeInCubic;

  /// Transition d'état sur place.
  static const Curve standard = Curves.easeInOutCubic;

  /// Courbe appuyée pour les mouvements marquants (ouverture d'un détail).
  static const Cubic emphasized = Cubic(0.2, 0, 0, 1);

  /// Décalage entre deux éléments d'une liste qui apparaît en cascade.
  static const Duration stagger = Duration(milliseconds: 35);
}

/// Tailles de zone tactile. 48 dp est le minimum recommandé ; l'ancienne
/// interface descendait sous les 32 dp sur certains boutons d'icône.
abstract final class TouchTarget {
  static const double minimum = 48;
  static const double comfortable = 56;
}
