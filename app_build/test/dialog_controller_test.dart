import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:password_manager/core/crypto/kdf_params.dart';
import 'package:password_manager/core/design/app_theme.dart';
import 'package:password_manager/data/api/api_client.dart';
import 'package:password_manager/data/api/coffort_api.dart';
import 'package:password_manager/data/models/cipher.dart';
import 'package:password_manager/data/vault_repository.dart';
import 'package:password_manager/features/vault/folder_sheet.dart';

/// Durée de vie du contrôleur d'une boîte de dialogue à champ de saisie.
///
/// `showDialog` rend la main dès `Navigator.pop`, c'est-à-dire au *début* de
/// l'animation de sortie. Un `controller.dispose()` placé juste après l'attente
/// détruit donc le contrôleur sous un `TextField` encore monté pour toute la
/// durée de la transition.
///
/// Ce que ça donnait sur un vrai téléphone : « A TextEditingController was used
/// after being disposed », puis une cascade d'assertions du framework
/// (`_dependents.isEmpty`, `Duplicate GlobalKeys`, `node.built`) qui laissait
/// l'arbre incohérent pour le reste de la session.
///
/// Le point délicat de ce test : il faut faire tourner l'animation de sortie
/// **avant** de relever l'exception. `pumpAndSettle` suffit, un `pump` unique
/// non — c'est précisément pour ça que le défaut n'avait été vu nulle part.

const _profile = VaultProfile(
  id: 'u1',
  email: 'tannou@coffort.test',
  kdf: KdfParams.argon2idDefault,
  kdfSalt: '0123456789abcdef0123456789abcdef',
  protectedKey: '1.AAAA',
);

Future<VaultRepository> _seeded() async {
  final repo = VaultRepository(
    api: CoffortApi(ApiClient(baseUrl: 'http://127.0.0.1:1')),
    deviceName: 'test',
  );
  await repo.seedForTest(
    items: const [],
    folders: const [FolderItem(id: 'f1', name: 'Banque')],
    profile: _profile,
  );
  return repo;
}

Future<void> _openSheet(WidgetTester tester, VaultRepository repo) async {
  await tester.pumpWidget(
    ChangeNotifierProvider<VaultRepository>.value(
      value: repo,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: FolderSheet()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('annuler la boîte « Nouveau dossier » ne détruit pas le '
      'contrôleur trop tôt', (tester) async {
    final repo = await _seeded();
    addTearDown(repo.dispose);
    await _openSheet(tester, repo);

    await tester.tap(find.text('Nouveau dossier'));
    await tester.pumpAndSettle();
    expect(find.text('Nom du dossier'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Impôts');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Annuler'));
    // Fait tourner l'animation de sortie jusqu'au bout : c'est pendant
    // celle-ci que le champ lisait un contrôleur détruit.
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Nom du dossier'), findsNothing);
  });

  testWidgets('valider la boîte « Nouveau dossier » non plus', (tester) async {
    final repo = await _seeded();
    addTearDown(repo.dispose);
    await _openSheet(tester, repo);

    await tester.tap(find.text('Nouveau dossier'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Impôts');
    await tester.pumpAndSettle();

    // La validation lit `controller.text` puis referme : le contrôleur est
    // sollicité au moment même du pop.
    await tester.tap(find.widgetWithText(FilledButton, 'Valider'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('fermer en tapant hors de la boîte non plus', (tester) async {
    // Le renvoi par barrière suit un chemin différent de celui des boutons :
    // aucun code de l'app n'est appelé, la route est simplement dépilée.
    final repo = await _seeded();
    addTearDown(repo.dispose);
    await _openSheet(tester, repo);

    await tester.tap(find.text('Nouveau dossier'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Impôts');
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Nom du dossier'), findsNothing);
  });
}
