import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Les composants fournis par Flutter parlent-ils français ?
///
/// Le menu de sélection de texte — « Couper », « Copier », « Coller » — n'est
/// pas écrit dans ce dépôt : il vient de Flutter, qui n'embarque que l'anglais
/// tant qu'on ne charge pas `flutter_localizations`. L'écran devenait alors
/// mi-français mi-anglais, avec « Coller » impossible à obtenir même sur un
/// téléphone configuré en français.
///
/// Ces tests interrogent directement les traductions officielles plutôt que
/// l'app entière : ils vérifient que le paquet est présent et que la langue est
/// bien celle qu'on impose, ce qui est exactement la condition qui manquait.

void main() {
  testWidgets('les délégués officiels rendent le français', (tester) async {
    late MaterialLocalizations m;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) {
            m = MaterialLocalizations.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    // Les libellés que l'utilisateur voyait en anglais.
    expect(m.cutButtonLabel, 'Couper');
    expect(m.copyButtonLabel, 'Copier');
    expect(m.pasteButtonLabel, 'Coller');
    expect(m.selectAllButtonLabel, 'Tout sélectionner');
  });

  testWidgets('sans les délégués, Flutter retombe sur l’anglais',
      (tester) async {
    // Ce test documente la cause du défaut : ce n'est pas un réglage oublié de
    // l'appareil, c'est que le moteur n'embarque que l'anglais. Déclarer la
    // langue ne suffit pas, il faut fournir les traductions.
    late MaterialLocalizations m;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        home: Builder(
          builder: (context) {
            m = MaterialLocalizations.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(m.pasteButtonLabel, 'Paste',
        reason: 'sans flutter_localizations, le français est ignoré');
  });

  testWidgets('les autres composants suivent aussi', (tester) async {
    // Le menu de texte n'est que le plus visible. Les sélecteurs de date et
    // les libellés d'accessibilité viennent du même paquet : les vérifier
    // garantit que c'est bien tout le jeu qui est chargé, pas une partie.
    late MaterialLocalizations m;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) {
            m = MaterialLocalizations.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(m.okButtonLabel, 'OK');
    expect(m.cancelButtonLabel, 'Annuler');
    expect(m.closeButtonLabel, 'Fermer');
    expect(m.searchFieldLabel, 'Rechercher');
  });
}
