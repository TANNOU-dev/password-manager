import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:password_manager/core/design/app_theme.dart';
import 'package:password_manager/data/api/api_client.dart';
import 'package:password_manager/data/api/coffort_api.dart';
import 'package:password_manager/data/vault_repository.dart';
import 'package:password_manager/features/vault/vault_screen.dart';
import 'package:password_manager/widgets/vault_item_tile.dart';
import 'package:password_manager/data/models/cipher.dart';

/// Tests de rendu. Ils ne parlent à aucun serveur : le dépôt reste verrouillé,
/// ce qui est précisément l'état qu'on veut vérifier ici — l'app ne doit rien
/// afficher du coffre avant d'avoir la clé.

/// Dépôt pointé sur une adresse morte. Aucun appel ne doit aboutir, et c'est
/// voulu : un test qui toucherait un vrai serveur ne serait plus un test unitaire.
VaultRepository _offlineRepo() => VaultRepository(
      api: CoffortApi(ApiClient(baseUrl: 'http://127.0.0.1:1')),
      deviceName: 'test',
    );

Widget _wrap(Widget child, VaultRepository repo) {
  return ChangeNotifierProvider<VaultRepository>.value(
    value: repo,
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: child,
    ),
  );
}

void main() {
  testWidgets('un coffre verrouillé n’expose aucun élément', (tester) async {
    final repo = _offlineRepo();
    addTearDown(repo.dispose);

    expect(repo.status, VaultStatus.locked);
    expect(repo.items, isEmpty);
    expect(repo.folders, isEmpty);
    expect(repo.profile, isNull);
  });

  testWidgets('l’écran du coffre affiche son état vide', (tester) async {
    final repo = _offlineRepo();
    addTearDown(repo.dispose);

    await tester.pumpWidget(_wrap(const VaultScreen(), repo));
    await tester.pump();

    expect(find.text('Mon coffre'), findsOneWidget);
    expect(find.text('Coffre vide'), findsOneWidget);
    // Aucune ligne d'élément ne doit être rendue.
    expect(find.byType(VaultItemTile), findsNothing);
  });

  testWidgets('la ligne d’un élément montre le nom sans révéler le mot de passe',
      (tester) async {
    const item = CipherItem(
      id: '00000000-0000-4000-8000-000000000000',
      data: LoginData(
        name: 'GitHub',
        username: 'tannou-dev',
        password: 'ne-doit-pas-apparaitre',
        uris: [LoginUri(uri: 'https://github.com')],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: VaultItemTile(item: item, onTap: () {})),
      ),
    );

    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('tannou-dev'), findsOneWidget);
    expect(find.textContaining('ne-doit-pas-apparaitre'), findsNothing);
  });

  testWidgets('un mot de passe faible est signalé sur la ligne', (tester) async {
    const item = CipherItem(
      id: '00000000-0000-4000-8000-000000000001',
      data: LoginData(name: 'Faible', password: 'azerty'),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: VaultItemTile(
            item: item,
            warning: 'Mot de passe faible',
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('Mot de passe faible'), findsOneWidget);
  });
}
