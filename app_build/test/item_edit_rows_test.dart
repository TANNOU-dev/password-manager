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

/// Retrait d'une ligne répétable dans l'écran d'édition.
///
/// Le retrait d'une adresse ou d'un champ personnalisé n'était couvert nulle
/// part, alors qu'il détruit un `TextEditingController` et décale toutes les
/// lignes suivantes. Ces tests verrouillent le comportement attendu : la ligne
/// visée disparaît, les autres gardent leur contenu, et la liste supporte d'être
/// vidée puis regarnie.
///
/// À noter pour qui les relira : ils passaient déjà avant qu'on clée les lignes
/// par identité. Ils décrivent le contrat, ils ne démontrent pas un correctif.
/// Le défaut de contrôleur détruit trop tôt observé sur appareil venait d'une
/// boîte de dialogue — voir dialog_controller_test.dart.

const _profile = VaultProfile(
  id: 'u1',
  email: 'tannou@coffort.test',
  kdf: KdfParams.argon2idDefault,
  kdfSalt: '0123456789abcdef0123456789abcdef',
  protectedKey: '1.AAAA',
);

const _item = CipherItem(
  id: '00000000-0000-4000-8000-000000000001',
  data: LoginData(
    name: 'Trois adresses',
    username: 'tannou',
    password: 'Kx7mQ2vB9nTz4wLp',
    uris: [
      LoginUri(uri: 'https://premier.test'),
      LoginUri(uri: 'https://deuxieme.test'),
      LoginUri(uri: 'https://troisieme.test'),
    ],
    fields: [
      CustomField(name: 'Question', value: 'Ville de naissance'),
      CustomField(name: 'Client', value: '4821'),
    ],
  ),
);

Future<VaultRepository> _seeded() async {
  final repo = VaultRepository(
    api: CoffortApi(ApiClient(baseUrl: 'http://127.0.0.1:1')),
    deviceName: 'test',
  );
  await repo.seedForTest(items: const [_item], profile: _profile);
  return repo;
}

/// Surface haute : l'écran d'édition dépasse largement les 600 px du gabarit
/// par défaut, et un widget hors écran n'est pas construit — donc introuvable.
/// On veut ici éprouver le retrait, pas le défilement.
Future<VaultRepository> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final repo = await _seeded();
  addTearDown(repo.dispose);

  await tester.pumpWidget(
    ChangeNotifierProvider<VaultRepository>.value(
      value: repo,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const ItemEditScreen(existing: _item),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

/// Les boutons « Retirer » des adresses et des champs personnalisés partagent
/// icône et infobulle. Ils se distinguent par leur ordre : les trois adresses
/// précèdent les deux champs dans l'arbre.
Finder get _removeButtons =>
    find.widgetWithIcon(IconButton, Icons.close_rounded);

void main() {
  testWidgets('retirer la première adresse ne touche pas aux suivantes',
      (tester) async {
    await _open(tester);

    expect(find.text('https://premier.test'), findsOneWidget);
    expect(find.text('https://troisieme.test'), findsOneWidget);

    // La première : c'est le retrait en tête qui décale tous les rangs suivants.
    await tester.tap(_removeButtons.first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'aucun contrôleur ne doit être lu après sa destruction');
    expect(find.text('https://premier.test'), findsNothing);
    expect(find.text('https://deuxieme.test'), findsOneWidget);
    expect(find.text('https://troisieme.test'), findsOneWidget);
  });

  testWidgets('retirer les adresses une à une jusqu’à la liste vide',
      (tester) async {
    await _open(tester);

    for (var reste = 3; reste > 0; reste--) {
      await tester.tap(_removeButtons.first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'échec au retrait avec $reste adresses restantes');
    }

    expect(
      find.text('Aucune adresse. Elles serviront au remplissage automatique.'),
      findsOneWidget,
    );
  });

  testWidgets('ajouter une adresse après en avoir retiré une', (tester) async {
    // Enchaîne les deux opérations : un ajout juste après un retrait est le cas
    // où un élément recyclé a le plus de chances de traîner un ancien état.
    await _open(tester);

    await tester.tap(_removeButtons.first);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Ajouter').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('https://deuxieme.test'), findsOneWidget);
    expect(find.text('https://troisieme.test'), findsOneWidget);
  });

  testWidgets('retirer le premier champ personnalisé garde le second',
      (tester) async {
    await _open(tester);

    expect(_removeButtons, findsNWidgets(5)); // 3 adresses puis 2 champs
    expect(find.text('Ville de naissance'), findsOneWidget);

    await tester.tap(_removeButtons.at(3));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Ville de naissance'), findsNothing);
    expect(find.text('Client'), findsOneWidget);
    expect(find.text('4821'), findsOneWidget);
  });
}
