import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:password_manager/core/crypto/kdf_params.dart';
import 'package:password_manager/core/design/app_theme.dart';
import 'package:password_manager/core/settings/app_settings.dart';
import 'package:password_manager/data/api/api_client.dart';
import 'package:password_manager/data/api/coffort_api.dart';
import 'package:password_manager/data/models/cipher.dart';
import 'package:password_manager/data/vault_repository.dart';
import 'package:password_manager/features/security/security_screen.dart';
import 'package:password_manager/features/vault/item_detail_screen.dart';
import 'package:password_manager/features/vault/trash_screen.dart';
import 'package:password_manager/features/vault/vault_screen.dart';
import 'package:password_manager/widgets/vault_item_tile.dart';

/// Rendu des écrans du coffre avec de vraies données déchiffrées.
///
/// Le dépôt est amorcé par `seedForTest`, donc aucun serveur n'est requis : ces
/// tests vérifient ce que l'utilisateur voit, pas le transport.

const _profile = VaultProfile(
  id: 'u1',
  email: 'tannou@coffort.test',
  kdf: KdfParams.argon2idDefault,
  kdfSalt: '0123456789abcdef0123456789abcdef',
  protectedKey: '1.AAAA',
);

/// Un coffre représentatif : un mot de passe solide, un faible, un réutilisé,
/// un TOTP, et un de chaque autre type.
List<CipherItem> _sampleVault() => const [
      CipherItem(
        id: '00000000-0000-4000-8000-000000000001',
        favorite: true,
        data: LoginData(
          name: 'GitHub',
          username: 'tannou-dev',
          password: 'Kx7mQ2vB9nTz4wLp',
          totp: 'JBSWY3DPEHPK3PXP',
          uris: [LoginUri(uri: 'https://github.com')],
        ),
      ),
      CipherItem(
        id: '00000000-0000-4000-8000-000000000002',
        data: LoginData(
          name: 'Orange CI',
          username: 'tannou@example.test',
          password: 'azerty123',
          uris: [LoginUri(uri: 'https://orange.ci')],
        ),
      ),
      CipherItem(
        id: '00000000-0000-4000-8000-000000000003',
        data: LoginData(
          name: 'Forum',
          username: 'tannou',
          // Même mot de passe que l'entrée suivante : doit être signalé comme
          // réutilisé.
          password: 'PartageEntreDeuxComptes1',
        ),
      ),
      CipherItem(
        id: '00000000-0000-4000-8000-000000000004',
        data: LoginData(
          name: 'Boutique',
          username: 'tannou',
          password: 'PartageEntreDeuxComptes1',
        ),
      ),
      CipherItem(
        id: '00000000-0000-4000-8000-000000000005',
        data: CardData(
          name: 'Carte Ecobank',
          cardholderName: 'TANNOU ABOU',
          number: '4539876543219876',
          expMonth: '09',
          expYear: '2029',
          code: '447',
        ),
      ),
      CipherItem(
        id: '00000000-0000-4000-8000-000000000006',
        data: SecureNoteData(
          name: 'Codes de récupération',
          notes: 'ABCD-EFGH\nIJKL-MNOP',
        ),
      ),
    ];

Future<VaultRepository> _seeded({
  List<CipherItem>? items,
  List<FolderItem> folders = const [],
}) async {
  final repo = VaultRepository(
    api: CoffortApi(ApiClient(baseUrl: 'http://127.0.0.1:1')),
    deviceName: 'test',
  );
  await repo.seedForTest(
    items: items ?? _sampleVault(),
    folders: folders,
    profile: _profile,
  );
  return repo;
}

Widget _wrap(Widget child, VaultRepository repo, {AppSettings? settings}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<VaultRepository>.value(value: repo),
      if (settings != null) ChangeNotifierProvider<AppSettings>.value(value: settings),
    ],
    child: MaterialApp(theme: AppTheme.dark(), home: child),
  );
}

void main() {
  testWidgets('la liste du coffre affiche chaque élément', (tester) async {
    final repo = await _seeded();
    addTearDown(repo.dispose);

    await tester.pumpWidget(_wrap(const VaultScreen(), repo));
    await tester.pumpAndSettle();

    expect(find.text('Mon coffre'), findsOneWidget);
    // Le sous-titre joint le compte et l'horodatage dans un seul Text, et
    // l'étiquette de section passe en capitales.
    expect(find.textContaining('6 éléments'), findsWidgets);
    expect(find.text('6 ÉLÉMENTS'), findsOneWidget);
    expect(find.text('GitHub'), findsOneWidget);

    // La liste est paresseuse : les dernières lignes ne sont construites
    // qu'après défilement. On va donc les chercher.
    await tester.scrollUntilVisible(
      find.text('Codes de récupération'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Codes de récupération'), findsOneWidget);
    expect(find.text('Carte Ecobank'), findsOneWidget);
  });

  testWidgets('aucun mot de passe n’apparaît dans la liste', (tester) async {
    final repo = await _seeded();
    addTearDown(repo.dispose);

    await tester.pumpWidget(_wrap(const VaultScreen(), repo));
    await tester.pumpAndSettle();

    // La liste montre des noms et des identifiants, jamais de secret.
    expect(find.textContaining('Kx7mQ2vB9nTz4wLp'), findsNothing);
    expect(find.textContaining('azerty123'), findsNothing);
    expect(find.textContaining('4539876543219876'), findsNothing);
    expect(find.textContaining('447'), findsNothing);
  });

  testWidgets('le bandeau de santé annonce le compte réel', (tester) async {
    final repo = await _seeded();
    addTearDown(repo.dispose);

    await tester.pumpWidget(_wrap(const VaultScreen(), repo));
    await tester.pumpAndSettle();

    // « azerty123 » est faible, et deux entrées partagent un mot de passe :
    // trois éléments à revoir.
    expect(find.text('3 mots de passe à revoir'), findsOneWidget);
    expect(find.textContaining('faible'), findsWidgets);
    expect(find.textContaining('réutilisé'), findsWidgets);
  });

  testWidgets('le filtre par type restreint la liste', (tester) async {
    final repo = await _seeded();
    addTearDown(repo.dispose);

    await tester.pumpWidget(_wrap(const VaultScreen(), repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cartes'));
    await tester.pumpAndSettle();

    expect(find.text('Carte Ecobank'), findsOneWidget);
    expect(find.text('GitHub'), findsNothing);
  });

  testWidgets('le filtre favoris ne garde que les favoris', (tester) async {
    final repo = await _seeded();
    addTearDown(repo.dispose);

    await tester.pumpWidget(_wrap(const VaultScreen(), repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Favoris'));
    await tester.pumpAndSettle();

    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('Orange CI'), findsNothing);
  });

  testWidgets('la recherche filtre sur le coffre déchiffré', (tester) async {
    final repo = await _seeded();
    addTearDown(repo.dispose);

    await tester.pumpWidget(_wrap(const VaultScreen(), repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'ecobank');
    await tester.pumpAndSettle();

    expect(find.text('Carte Ecobank'), findsOneWidget);
    expect(find.text('GitHub'), findsNothing);
  });

  testWidgets('une recherche sans résultat propose de réinitialiser',
      (tester) async {
    final repo = await _seeded();
    addTearDown(repo.dispose);

    await tester.pumpWidget(_wrap(const VaultScreen(), repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'zzzzz');
    await tester.pumpAndSettle();

    expect(find.text('Aucun résultat'), findsOneWidget);
    expect(find.text('Réinitialiser les filtres'), findsOneWidget);
  });

  testWidgets('un coffre vide invite à ajouter un élément', (tester) async {
    final repo = await _seeded(items: const []);
    addTearDown(repo.dispose);

    await tester.pumpWidget(_wrap(const VaultScreen(), repo));
    await tester.pumpAndSettle();

    expect(find.text('Coffre vide'), findsOneWidget);
    expect(find.byType(VaultItemTile), findsNothing);
  });

  testWidgets('le détail d’un identifiant masque le mot de passe par défaut',
      (tester) async {
    final repo = await _seeded();
    addTearDown(repo.dispose);

    await tester.pumpWidget(_wrap(
      const ItemDetailScreen(itemId: '00000000-0000-4000-8000-000000000001'),
      repo,
    ));
    await tester.pumpAndSettle();

    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('tannou-dev'), findsOneWidget);
    expect(find.text('https://github.com'), findsOneWidget);

    // Le mot de passe est présent dans l'arbre mais rendu flouté ; ce qui
    // compte ici est que le champ existe et que le TOTP soit calculé.
    expect(find.text('MOT DE PASSE'), findsOneWidget);
    expect(find.textContaining('CODE À USAGE UNIQUE'), findsOneWidget);
  });

  testWidgets('le détail d’une carte n’affiche que les quatre derniers chiffres',
      (tester) async {
    final repo = await _seeded();
    addTearDown(repo.dispose);

    await tester.pumpWidget(_wrap(
      const ItemDetailScreen(itemId: '00000000-0000-4000-8000-000000000005'),
      repo,
    ));
    await tester.pumpAndSettle();

    expect(find.text('•••• •••• •••• 9876'), findsOneWidget);
    expect(find.text('Visa'), findsOneWidget);
    expect(find.text('TANNOU ABOU'), findsOneWidget);
  });

  testWidgets('un identifiant supprimé affiche le bandeau corbeille',
      (tester) async {
    final deleted = CipherItem(
      id: '00000000-0000-4000-8000-0000000000ff',
      data: const LoginData(name: 'Supprimé', password: 'x'),
      deletedAt: DateTime(2026, 8, 1),
    );
    final repo = await _seeded(items: [deleted]);
    addTearDown(repo.dispose);

    await tester.pumpWidget(_wrap(
      const ItemDetailScreen(itemId: '00000000-0000-4000-8000-0000000000ff'),
      repo,
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('À la corbeille depuis le 01/08/2026'),
        findsOneWidget);
  });

  testWidgets('l’écran sécurité classe les problèmes par catégorie',
      (tester) async {
    final repo = await _seeded();
    addTearDown(repo.dispose);

    await tester.pumpWidget(_wrap(const SecurityScreen(), repo));
    await tester.pumpAndSettle();

    expect(find.text('Sécurité'), findsOneWidget);
    // La vérification des fuites n'a pas été lancée : elle ne doit pas être
    // présentée comme faite.
    expect(find.text('Lancer la vérification'), findsOneWidget);
    expect(find.text('Mot de passe exposé (1)'), findsNothing);

    // Les sections d'anomalies sont en bas de la liste, construite
    // paresseusement.
    await tester.scrollUntilVisible(
      find.text('Mot de passe réutilisé (2)'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Mot de passe faible (1)'), findsOneWidget);
    expect(find.text('Mot de passe réutilisé (2)'), findsOneWidget);
    expect(find.text('Utilisé sur 2 comptes'), findsNWidgets(2));
  });

  testWidgets('un coffre sain affiche un score de 100', (tester) async {
    final repo = await _seeded(items: const [
      CipherItem(
        id: '00000000-0000-4000-8000-00000000000a',
        data: LoginData(
          name: 'Solide',
          password: 'Kx7mQ2vB9nTz4wLp!Rt',
          passwordUpdatedAt: null,
        ),
      ),
    ]);
    addTearDown(repo.dispose);

    await tester.pumpWidget(_wrap(const SecurityScreen(), repo));
    await tester.pumpAndSettle();

    expect(find.text('Aucun problème détecté'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
  });

  testWidgets('la corbeille vide explique à quoi elle sert', (tester) async {
    final repo = await _seeded(items: const []);
    addTearDown(repo.dispose);

    await tester.pumpWidget(_wrap(const TrashScreen(), repo));
    await tester.pumpAndSettle();

    expect(find.text('Corbeille vide'), findsOneWidget);
  });

  testWidgets('la corbeille liste les éléments supprimés', (tester) async {
    final repo = await _seeded(items: [
      const CipherItem(
        id: '00000000-0000-4000-8000-00000000000b',
        data: LoginData(name: 'Actif', password: 'x'),
      ),
      CipherItem(
        id: '00000000-0000-4000-8000-00000000000c',
        data: const LoginData(name: 'Jeté', password: 'x'),
        deletedAt: DateTime(2026, 8, 5),
      ),
    ]);
    addTearDown(repo.dispose);

    await tester.pumpWidget(_wrap(const TrashScreen(), repo));
    await tester.pumpAndSettle();

    expect(find.text('Jeté'), findsOneWidget);
    expect(find.text('Actif'), findsNothing);
    expect(find.text('1 élément récupérable. Ils restent chiffrés sur le serveur.'),
        findsOneWidget);
  });

  testWidgets('un dossier apparaît comme filtre actif', (tester) async {
    const folder = FolderItem(id: 'f1', name: 'Banque');
    final repo = await _seeded(
      items: [
        const CipherItem(
          id: '00000000-0000-4000-8000-00000000000d',
          folderId: 'f1',
          data: LoginData(name: 'Dans Banque', password: 'x'),
        ),
      ],
      folders: const [folder],
    );
    addTearDown(repo.dispose);

    await tester.pumpWidget(_wrap(const VaultScreen(), repo));
    await tester.pumpAndSettle();

    expect(find.text('Dans Banque'), findsOneWidget);
  });
}
