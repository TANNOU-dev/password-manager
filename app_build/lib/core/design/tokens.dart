import 'package:flutter/widgets.dart';

/// Jetons de design de PassVault.
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

  /// Thème sombre : noir bleuté plutôt que gris neutre, pour que l'indigo de
  /// l'accent ne paraisse pas délavé.
  static const AppColors dark = AppColors(
    background: Color(0xFF0B0D12),
    surface: Color(0xFF14171F),
    surfaceRaised: Color(0xFF1B1F29),
    surfaceSunken: Color(0xFF0F1218),
    hairline: Color(0x14FFFFFF),
    hairlineStrong: Color(0x24FFFFFF),
    textPrimary: Color(0xFFF2F4F8),
    textSecondary: Color(0xFF9BA3B4),
    textTertiary: Color(0xFF6B7385),
    primary: Color(0xFF6D5DF6),
    primaryHover: Color(0xFF8B7DFF),
    onPrimary: Color(0xFFFFFFFF),
    primaryWash: Color(0x266D5DF6),
    accent: Color(0xFF22D3EE),
    success: Color(0xFF34D399),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFF87171),
    dangerWash: Color(0x26F87171),
    overlay: Color(0xB3000000),
  );

  static const AppColors light = AppColors(
    background: Color(0xFFF6F7FA),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFF1F3F7),
    hairline: Color(0x14101322),
    hairlineStrong: Color(0x24101322),
    textPrimary: Color(0xFF101322),
    textSecondary: Color(0xFF5A6478),
    textTertiary: Color(0xFF8A93A6),
    primary: Color(0xFF5849E0),
    primaryHover: Color(0xFF4737C7),
    onPrimary: Color(0xFFFFFFFF),
    primaryWash: Color(0x1A5849E0),
    accent: Color(0xFF0E9BB5),
    success: Color(0xFF0F9D6E),
    warning: Color(0xFFB45309),
    danger: Color(0xFFDC2626),
    dangerWash: Color(0x1ADC2626),
    overlay: Color(0x66101322),
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
