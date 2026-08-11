import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// Rend la palette accessible depuis n'importe quel widget via
/// `context.palette`, sans la passer de main en main.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette(this.colors);

  final AppColors colors;

  @override
  AppPalette copyWith({AppColors? colors}) => AppPalette(colors ?? this.colors);

  // Les couleurs ne s'interpolent pas champ par champ : on bascule à mi-chemin.
  // Un dégradé de 20 couleurs pendant un changement de thème n'apporte rien et
  // produit des teintes intermédiaires laides.
  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return t < 0.5 ? this : other;
  }
}

extension PaletteAccess on BuildContext {
  AppColors get palette =>
      Theme.of(this).extension<AppPalette>()?.colors ?? AppColors.dark;
}

/// Typographie.
///
/// Trois rôles, trois familles, et surtout : les trois sont réellement chargées.
/// L'ancien thème déclarait `fontFamily: 'JetBrains Mono'` sans jamais charger
/// la police, donc tous les mots de passe s'affichaient dans la police par
/// défaut — un `0` et un `O` y sont indiscernables, ce qui est précisément le
/// problème qu'une police à chasse fixe résout.
abstract final class AppFonts {
  /// Titres : plus de caractère qu'Inter, sans être excentrique.
  static TextStyle display([TextStyle? base]) =>
      GoogleFonts.plusJakartaSans(textStyle: base);

  /// Corps de l'interface.
  static TextStyle ui([TextStyle? base]) => GoogleFonts.inter(textStyle: base);

  /// Secrets : mots de passe, codes TOTP, clés. Chasse fixe obligatoire pour
  /// qu'on puisse lire un mot de passe caractère par caractère.
  static TextStyle mono([TextStyle? base]) =>
      GoogleFonts.jetBrainsMono(textStyle: base);
}

abstract final class AppTheme {
  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);
  static ThemeData light() => _build(AppColors.light, Brightness.light);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final textTheme = _textTheme(c);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      extensions: [AppPalette(c)],

      colorScheme: ColorScheme(
        brightness: brightness,
        primary: c.primary,
        onPrimary: c.onPrimary,
        primaryContainer: c.primaryWash,
        onPrimaryContainer: c.primary,
        secondary: c.accent,
        onSecondary: c.background,
        surface: c.surface,
        onSurface: c.textPrimary,
        surfaceContainerHighest: c.surfaceRaised,
        surfaceContainerLow: c.surfaceSunken,
        onSurfaceVariant: c.textSecondary,
        outline: c.hairlineStrong,
        outlineVariant: c.hairline,
        error: c.danger,
        onError: c.onPrimary,
        errorContainer: c.dangerWash,
        onErrorContainer: c.danger,
        scrim: c.overlay,
      ),

      textTheme: textTheme,
      fontFamily: AppFonts.ui().fontFamily,

      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: c.textSecondary, size: 22),
      ),

      cardTheme: CardThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.all(Radii.lg),
          side: BorderSide(color: c.hairline),
        ),
      ),

      // Champs creusés, sans bordure au repos : le contraste de fond suffit à
      // signaler la zone de saisie, et la bordure n'apparaît qu'au focus.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceSunken,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Gap.lg,
          vertical: Gap.lg,
        ),
        border: OutlineInputBorder(
          borderRadius: Radii.all(Radii.md),
          borderSide: BorderSide(color: c.hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: Radii.all(Radii.md),
          borderSide: BorderSide(color: c.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.all(Radii.md),
          borderSide: BorderSide(color: c.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: Radii.all(Radii.md),
          borderSide: BorderSide(color: c.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: Radii.all(Radii.md),
          borderSide: BorderSide(color: c.danger, width: 1.6),
        ),
        labelStyle: textTheme.labelLarge?.copyWith(color: c.textSecondary),
        floatingLabelStyle: textTheme.labelLarge?.copyWith(color: c.primary),
        hintStyle: textTheme.bodyMedium?.copyWith(color: c.textTertiary),
        prefixIconColor: c.textTertiary,
        suffixIconColor: c.textTertiary,
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          disabledBackgroundColor: c.primary.withValues(alpha: 0.32),
          disabledForegroundColor: c.onPrimary.withValues(alpha: 0.6),
          minimumSize: const Size(0, TouchTarget.comfortable),
          padding: const EdgeInsets.symmetric(horizontal: Gap.xxl),
          shape: RoundedRectangleBorder(borderRadius: Radii.all(Radii.md)),
          textStyle: textTheme.labelLarge,
          elevation: 0,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          side: BorderSide(color: c.hairlineStrong),
          minimumSize: const Size(0, TouchTarget.comfortable),
          padding: const EdgeInsets.symmetric(horizontal: Gap.xxl),
          shape: RoundedRectangleBorder(borderRadius: Radii.all(Radii.md)),
          textStyle: textTheme.labelLarge,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primary,
          minimumSize: const Size(0, TouchTarget.minimum),
          textStyle: textTheme.labelLarge,
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: c.textSecondary,
          minimumSize: const Size(TouchTarget.minimum, TouchTarget.minimum),
          shape: RoundedRectangleBorder(borderRadius: Radii.all(Radii.sm)),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.all(Radii.xl),
          side: BorderSide(color: c.hairline),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalBarrierColor: c.overlay,
        shape: const RoundedRectangleBorder(borderRadius: Radii.sheet),
        showDragHandle: true,
        dragHandleColor: c.textTertiary,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surfaceRaised,
        contentTextStyle: textTheme.bodyMedium,
        actionTextColor: c.primary,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.all(Radii.md),
          side: BorderSide(color: c.hairline),
        ),
      ),

      dividerTheme: DividerThemeData(
        color: c.hairline,
        thickness: 1,
        space: 1,
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.onPrimary
              : c.textTertiary,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? c.primary
              : c.surfaceSunken,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : c.hairlineStrong,
        ),
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: c.primary,
        inactiveTrackColor: c.surfaceSunken,
        thumbColor: c.primary,
        overlayColor: c.primaryWash,
        trackHeight: 6,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceSunken,
        selectedColor: c.primaryWash,
        side: BorderSide(color: c.hairline),
        labelStyle: textTheme.labelMedium,
        shape: RoundedRectangleBorder(borderRadius: Radii.all(Radii.xs)),
        padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.xs),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: c.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.all(Radii.md),
          side: BorderSide(color: c.hairline),
        ),
        textStyle: textTheme.bodyMedium,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.primary,
        linearTrackColor: c.surfaceSunken,
        circularTrackColor: c.surfaceSunken,
      ),

      listTileTheme: ListTileThemeData(
        iconColor: c.textSecondary,
        titleTextStyle: textTheme.bodyLarge,
        subtitleTextStyle: textTheme.bodySmall,
        shape: RoundedRectangleBorder(borderRadius: Radii.all(Radii.md)),
      ),

      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );
  }

  static TextTheme _textTheme(AppColors c) {
    // Interlignes serrés sur les grands corps, aérés sur le texte courant :
    // c'est ce contraste qui donne une hiérarchie lisible.
    return TextTheme(
      displaySmall: AppFonts.display(TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w800,
        height: 1.12,
        letterSpacing: -0.8,
        color: c.textPrimary,
      )),
      headlineMedium: AppFonts.display(TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        height: 1.2,
        letterSpacing: -0.5,
        color: c.textPrimary,
      )),
      headlineSmall: AppFonts.display(TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w700,
        height: 1.25,
        letterSpacing: -0.3,
        color: c.textPrimary,
      )),
      titleLarge: AppFonts.display(TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        height: 1.3,
        letterSpacing: -0.2,
        color: c.textPrimary,
      )),
      titleMedium: AppFonts.ui(TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.35,
        color: c.textPrimary,
      )),
      bodyLarge: AppFonts.ui(TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        height: 1.45,
        color: c.textPrimary,
      )),
      bodyMedium: AppFonts.ui(TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: c.textSecondary,
      )),
      bodySmall: AppFonts.ui(TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w400,
        height: 1.45,
        color: c.textSecondary,
      )),
      labelLarge: AppFonts.ui(TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: 0,
        color: c.textPrimary,
      )),
      labelMedium: AppFonts.ui(TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        height: 1.2,
        color: c.textSecondary,
      )),
      // Étiquettes de section : petites capitales espacées, en gris.
      labelSmall: AppFonts.ui(TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        height: 1.2,
        letterSpacing: 0.9,
        color: c.textTertiary,
      )),
    );
  }
}

/// Style des valeurs secrètes. À utiliser partout où s'affiche un mot de passe,
/// un code ou une clé.
abstract final class SecretText {
  static TextStyle of(BuildContext context, {double size = 15}) =>
      AppFonts.mono(TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w500,
        height: 1.4,
        letterSpacing: 0.4,
        color: context.palette.textPrimary,
      ));
}
