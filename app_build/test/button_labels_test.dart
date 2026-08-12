import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:password_manager/core/crypto/kdf_params.dart';
import 'package:password_manager/core/design/app_theme.dart';
import 'package:password_manager/data/api/api_client.dart';
import 'package:password_manager/data/api/coffort_api.dart';
import 'package:password_manager/data/models/cipher.dart';
import 'package:password_manager/data/vault_repository.dart';
import 'package:password_manager/features/vault/item_edit_screen.dart';

/// Les libellés de boutons tiennent-ils sur une ligne ?
///
/// « Annuler » se coupait en « Annule » et « r » sur l'écran d'édition : deux
/// `Expanded` en 1:2 lui laissaient une centaine de points sur un écran de
/// 360, marge interne du bouton déduite. Un partage en proportions fixes ne
/// peut pas tenir compte de la longueur réelle du texte — laquelle change avec
/// la langue et avec la taille de police du système.
///
/// Ces tests mesurent la hauteur rendue du libellé. Une hauteur qui dépasse
/// une ligne signifie que le texte est passé à la ligne, donc que le bouton est
/// trop étroit — quelle qu'en soit la cause.

const _profile = VaultProfile(
  id: 'u1',
  email: 'tannou@coffort.test',
  kdf: KdfParams.argon2idDefault,
  kdfSalt: '0123456789abcdef0123456789abcdef',
  protectedKey: '1.AAAA',
);

/// Hauteur au-delà de laquelle un libellé occupe forcément deux lignes.
///
/// Le corps de texte des boutons tourne autour de 14 points, interligne
/// compris on reste sous 24. Un texte replié dépasse largement ce seuil.
const double _uneLigneMax = 26;

/// Le libellé du bouton principal de la barre du bas.
///
/// « Ajouter » apparaît aussi sur les boutons d'ajout d'adresse et de champ
/// personnalisé, qui sont des `TextButton`. On désigne celui de la barre
/// d'action, seul `FilledButton` de l'écran.
final Finder _labelPrincipal =
    find.descendant(of: find.byType(FilledButton), matching: find.text('Ajouter'));

Future<VaultRepository> _vault() async {
  final repo = VaultRepository(
    api: CoffortApi(ApiClient(baseUrl: 'http://127.0.0.1:1')),
    deviceName: 'test',
  );
  await repo.seedForTest(items: const [], profile: _profile);
  return repo;
}

Future<void> _openEditor(
  WidgetTester tester,
  VaultRepository repo, {
  required Size surface,
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<VaultRepository>.value(
      value: repo,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: const ItemEditScreen(type: CipherType.login),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('« Annuler » tient sur une ligne sur un écran étroit',
      (tester) async {
    // 360 points de large : le format du téléphone où le défaut est apparu.
    final repo = await _vault();
    addTearDown(repo.dispose);
    await _openEditor(tester, repo, surface: const Size(360, 800));

    final hauteur = tester.getSize(find.text('Annuler')).height;
    expect(hauteur, lessThan(_uneLigneMax),
        reason: 'le libellé se replie : le bouton est trop étroit');
  });

  testWidgets('le bouton principal aussi', (tester) async {
    final repo = await _vault();
    addTearDown(repo.dispose);
    await _openEditor(tester, repo, surface: const Size(360, 800));

    expect(tester.getSize(_labelPrincipal).height, lessThan(_uneLigneMax));
  });

  testWidgets('sur un écran très étroit, aucun des deux ne se replie',
      (tester) async {
    // 320 points : les plus petits Android encore en circulation.
    final repo = await _vault();
    addTearDown(repo.dispose);
    await _openEditor(tester, repo, surface: const Size(320, 640));

    expect(tester.getSize(find.text('Annuler')).height, lessThan(_uneLigneMax));
    expect(tester.getSize(_labelPrincipal).height, lessThan(_uneLigneMax));
  });

  testWidgets('le secondaire garde sa largeur quand le libellé s’allonge',
      (tester) async {
    // Le vrai sujet du défaut : c'est la longueur du texte qui décide, pas une
    // proportion figée. Une police agrandie reproduit ce qu'aurait donné une
    // traduction plus verbeuse.
    final repo = await _vault();
    addTearDown(repo.dispose);
    await _openEditor(
      tester,
      repo,
      surface: const Size(360, 800),
      textScale: 1.3,
    );

    expect(tester.getSize(find.text('Annuler')).height,
        lessThan(_uneLigneMax * 1.3),
        reason: 'à 130 % de police, le libellé doit encore tenir sur une ligne');
  });

  testWidgets('les boutons sont empilés, action principale au-dessus',
      (tester) async {
    // Empiler est le seul choix qui tienne dans toutes les langues et à toutes
    // les tailles de police : la rangée ne rentrait sur aucun téléphone une
    // fois « Enregistrer » affiché.
    final repo = await _vault();
    addTearDown(repo.dispose);
    await _openEditor(tester, repo, surface: const Size(360, 800));

    final annuler = tester.getRect(find.text('Annuler'));
    final ajouter = tester.getRect(_labelPrincipal);
    expect(ajouter.bottom, lessThan(annuler.top),
        reason: 'l’action principale doit être au-dessus');
  });

  testWidgets('« Enregistrer », plus long, tient aussi sur une ligne',
      (tester) async {
    // Le libellé de modification est plus long que celui de création : c'est
    // lui qui condamnait la disposition en rangée.
    final repo = await _vault();
    addTearDown(repo.dispose);

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<VaultRepository>.value(
        value: repo,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const ItemEditScreen(
            existing: CipherItem(
              id: '00000000-0000-4000-8000-000000000001',
              data: LoginData(name: 'GitHub', username: 'moi', password: 'x'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getSize(find.text('Enregistrer')).height,
        lessThan(_uneLigneMax));
    expect(tester.getSize(find.text('Annuler')).height, lessThan(_uneLigneMax));
  });
}
