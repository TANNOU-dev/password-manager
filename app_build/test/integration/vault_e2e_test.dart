// Essai de bout en bout contre un vrai serveur Node.
//
// Lancé par tool/e2e.sh, qui démarre un serveur sur une base temporaire, passe
// son URL en --dart-define, puis inspecte la base pour vérifier qu'aucun secret
// n'y apparaît en clair.
//
//   ./tool/e2e.sh
//
// Ces marqueurs sont volontairement improbables : le script les cherche
// ensuite octet par octet dans le fichier SQLite.
import 'package:flutter_test/flutter_test.dart';

import 'package:password_manager/core/crypto/kdf_params.dart';
import 'package:password_manager/core/crypto/vault_crypto.dart';
import 'package:password_manager/data/api/api_client.dart';
import 'package:password_manager/data/api/coffort_api.dart';
import 'package:password_manager/data/export/vault_export.dart';
import 'package:password_manager/data/import/importers.dart';
import 'package:password_manager/data/models/cipher.dart';
import 'package:password_manager/data/vault_repository.dart';

const apiUrl = String.fromEnvironment('PASSVAULT_API_URL');

const email = 'e2e@coffort.test';
const masterPassword = 'mot-de-passe-maitre-de-test-2026';

// Marqueurs recherchés ensuite dans le fichier de base de données.
const marqueurMotDePasse = 'MARQUEUR-SECRET-Zx9Qw7';
const marqueurNomElement = 'MARQUEUR-NOM-Kp3Rt8';
const marqueurNote = 'MARQUEUR-NOTE-Vb2Nm5';
const marqueurDossier = 'MARQUEUR-DOSSIER-Hj6Ly4';
const marqueurCarte = '4111111111111111';
const marqueurTotp = 'JBSWY3DPEHPK3PXP';

void main() {
  if (apiUrl.isEmpty) {
    test('essai de bout en bout ignoré', () {
      markTestSkipped('PASSVAULT_API_URL non défini — lancer ./tool/e2e.sh');
    }, skip: true);
    return;
  }

  // Paramètres allégés : on valide l'enchaînement, pas le coût du KDF.
  const kdf = KdfParams(
    type: KdfType.argon2id,
    iterations: 1,
    memory: 8192,
    parallelism: 1,
  );

  VaultRepository build() => VaultRepository(
        api: CoffortApi(ApiClient(baseUrl: apiUrl)),
        deviceName: 'suite-e2e',
      );

  test('le serveur se déclare zero-knowledge', () async {
    final status = await build().serverStatus();
    expect(status.zeroKnowledge, isTrue);
    expect(status.apiVersion, 2);
    expect(status.acceptsRegistration, isTrue);
  });

  test('cycle complet : créer, remplir, verrouiller, rouvrir', () async {
    final repo = build();

    await repo.createVault(
      email: email,
      masterPassword: masterPassword,
      kdf: kdf,
    );
    expect(repo.status, VaultStatus.unlocked);
    expect(repo.items, isEmpty);

    // ── Un identifiant complet ──
    await repo.saveItem(CipherItem(
      favorite: true,
      data: LoginData(
        name: marqueurNomElement,
        username: 'tannou@example.test',
        password: marqueurMotDePasse,
        totp: marqueurTotp,
        notes: marqueurNote,
        uris: const [LoginUri(uri: 'https://github.com')],
        fields: const [
          CustomField(
            name: 'code de secours',
            value: 'AAAA-BBBB',
            type: CustomFieldType.hidden,
          ),
        ],
      ),
    ));

    // ── Une carte bancaire ──
    await repo.saveItem(const CipherItem(
      data: CardData(
        name: 'Carte de test',
        cardholderName: 'TANNOU ABOU',
        number: marqueurCarte,
        expMonth: '12',
        expYear: '2030',
        code: '123',
      ),
    ));

    // ── Une note et une identité ──
    await repo.saveItem(const CipherItem(
      data: SecureNoteData(name: 'Note de test', notes: marqueurNote),
    ));
    await repo.saveItem(const CipherItem(
      data: IdentityData(
        name: 'Identité de test',
        firstName: 'Tannou',
        lastName: 'Abou',
        email: 'tannou@example.test',
      ),
    ));

    // ── Un dossier, avec un élément dedans ──
    final folder = await repo.createFolder(marqueurDossier);
    await repo.saveItem(CipherItem(
      folderId: folder.id,
      data: const LoginData(name: 'Dans le dossier', password: 'peu-importe'),
    ));

    expect(repo.items.length, 5);
    expect(repo.folders.length, 1);
    expect(repo.undecryptable, isEmpty);

    // ── Verrouillage : la clé doit quitter la mémoire ──
    repo.lock();
    expect(repo.status, VaultStatus.locked);
    expect(repo.items, isEmpty);
    expect(
      () => repo.saveItem(
        const CipherItem(data: LoginData(name: 'refusé')),
      ),
      throwsStateError,
    );

    // ── Réouverture : tout doit revenir à l'identique ──
    await repo.unlock(email: email, masterPassword: masterPassword);
    expect(repo.status, VaultStatus.unlocked);
    expect(repo.items.length, 5);
    expect(repo.undecryptable, isEmpty, reason: 'aucun élément ne doit être illisible');

    final login = repo.items
        .map((i) => i.data)
        .whereType<LoginData>()
        .firstWhere((d) => d.name == marqueurNomElement);
    expect(login.password, marqueurMotDePasse);
    expect(login.totp, marqueurTotp);
    expect(login.notes, marqueurNote);
    expect(login.uris.single.host, 'github.com');
    expect(login.fields.single.value, 'AAAA-BBBB');

    final card = repo.items.map((i) => i.data).whereType<CardData>().single;
    expect(card.number, marqueurCarte);
    expect(card.last4, '1111');
    expect(card.inferredBrand, 'Visa');

    // Le nom du dossier est chiffré, donc il doit revenir déchiffré à l'identique.
    expect(repo.folders.single.name, marqueurDossier);

    // Le favori est une métadonnée en clair : elle doit survivre aussi.
    expect(repo.items.where((i) => i.favorite).length, 1);
  });

  test('un mauvais mot de passe maître n’ouvre pas le coffre', () async {
    final repo = build();
    await expectLater(
      repo.unlock(email: email, masterPassword: 'ce-n-est-pas-le-bon'),
      throwsA(anyOf(
        isA<WrongMasterPasswordException>(),
        isA<UnauthorizedFailure>(),
      )),
    );
    expect(repo.status, VaultStatus.locked);
    expect(repo.items, isEmpty);
  });

  test('la corbeille retient puis rend un élément', () async {
    final repo = build();
    await repo.unlock(email: email, masterPassword: masterPassword);

    final target = repo.items.first;
    await repo.moveToTrash(target);
    expect(repo.items.any((i) => i.id == target.id), isFalse);
    expect(repo.trash.any((i) => i.id == target.id), isTrue);

    await repo.restoreFromTrash(repo.trash.first);
    expect(repo.items.any((i) => i.id == target.id), isTrue);
    expect(repo.trash, isEmpty);
  });

  test('l’historique conserve l’ancien mot de passe', () async {
    final repo = build();
    await repo.unlock(email: email, masterPassword: masterPassword);

    final item = repo.items.firstWhere((i) => i.data is LoginData);
    final before = item.data as LoginData;
    final updated = await repo.saveItem(
      item.copyWith(data: before.withNewPassword('nouveau-mot-de-passe')),
    );

    final after = updated.data as LoginData;
    expect(after.password, 'nouveau-mot-de-passe');
    expect(after.passwordHistory.first.password, before.password);
    expect(after.passwordUpdatedAt, isNotNull);
  });

  test('un import Bitwarden traverse toute la chaîne', () async {
    final repo = build();
    await repo.unlock(email: email, masterPassword: masterPassword);

    final foldersBefore = repo.folders.length;
    final itemsBefore = repo.items.length;

    // Deux entrées dans un dossier neuf, une dans un dossier au nom déjà pris
    // s'il existe. Les importateurs renvoient des *noms* de dossiers ; c'est
    // importParsed qui doit les créer et les résoudre en identifiants.
    const source = '''
    {
      "encrypted": false,
      "folders": [{"id": "f-a", "name": "Importé"}],
      "items": [
        {
          "type": 1, "name": "Importé GitHub", "folderId": "f-a",
          "login": {"username": "u1", "password": "MARQUEUR-IMPORT-Qw8Zx3"}
        },
        {
          "type": 3, "name": "Importé Carte", "folderId": "f-a",
          "card": {"number": "4111111111111111", "code": "999"}
        },
        {"type": 2, "name": "Importé Note", "notes": "sans dossier"}
      ]
    }
    ''';

    final parsed = parseImport(source);
    expect(parsed.count, 3);
    expect(parsed.folderNames, ['Importé']);

    final steps = <String>[];
    final imported = await repo.importParsed(
      parsed,
      onProgress: steps.add,
    );

    expect(imported, 3);
    expect(steps.any((s) => s.contains('Importé')), isTrue);
    expect(repo.items.length, itemsBefore + 3);
    expect(repo.folders.length, foldersBefore + 1);
    expect(repo.undecryptable, isEmpty);

    // Le dossier a bien été créé, et les éléments y pointent par identifiant.
    final folder = repo.folders.firstWhere((f) => f.name == 'Importé');
    final inFolder =
        repo.items.where((i) => i.folderId == folder.id).toList();
    expect(inFolder.length, 2);

    // L'élément sans dossier ne s'est pas vu attribuer celui des autres.
    final note = repo.items.firstWhere((i) => i.data.name == 'Importé Note');
    expect(note.folderId, isNull);

    // Et le contenu est relisible après un aller-retour complet.
    final github = repo.items
        .map((i) => i.data)
        .whereType<LoginData>()
        .firstWhere((d) => d.name == 'Importé GitHub');
    expect(github.password, 'MARQUEUR-IMPORT-Qw8Zx3');
  });

  test('réimporter le même fichier ne duplique pas le dossier', () async {
    final repo = build();
    await repo.unlock(email: email, masterPassword: masterPassword);

    const source = '''
    {
      "encrypted": false,
      "folders": [{"id": "f-a", "name": "Importé"}],
      "items": [
        {"type": 2, "name": "Doublon", "folderId": "f-a", "notes": "x"}
      ]
    }
    ''';

    final foldersBefore = repo.folders.length;
    await repo.importParsed(parseImport(source));
    // Le dossier « Importé » existe déjà depuis le test précédent : le compte ne
    // doit pas bouger.
    expect(repo.folders.where((f) => f.name == 'Importé').length, 1);
    expect(repo.folders.length, foldersBefore);
  });

  test('une sauvegarde chiffrée fait l’aller-retour complet', () async {
    final repo = build();
    await repo.unlock(email: email, masterPassword: masterPassword);

    final folderNames = {for (final f in repo.folders) f.id: f.name};
    final backup = await VaultExporter.toEncryptedJson(
      repo.items,
      exportPassword: 'phrase-de-passe-de-la-sauvegarde',
      folderNames: folderNames,
      kdf: kdf,
    );

    // Le coffre réel ne doit pas être lisible dans le fichier.
    expect(backup, isNot(contains(marqueurMotDePasse)));
    expect(backup, isNot(contains(marqueurCarte)));

    final plain = await VaultExporter.decryptBackup(
      backup,
      exportPassword: 'phrase-de-passe-de-la-sauvegarde',
    );
    final reimported = parseImport(plain);
    expect(reimported.count, repo.items.length);
    expect(
      reimported.items
          .map((i) => i.data)
          .whereType<LoginData>()
          .any((d) => d.password == marqueurMotDePasse),
      isTrue,
    );
  });

  test('supprimer un dossier n’emporte pas ses éléments', () async {
    final repo = build();
    await repo.unlock(email: email, masterPassword: masterPassword);

    // Cible le dossier par son nom : d'autres tests en ont créé entre-temps.
    final folder = repo.folders.firstWhere((f) => f.name == marqueurDossier);
    final inFolder = repo.items.where((i) => i.folderId == folder.id).toList();
    expect(inFolder, isNotEmpty);

    final foldersBefore = repo.folders.length;
    await repo.deleteFolder(folder.id);
    expect(repo.folders.length, foldersBefore - 1);
    expect(repo.folders.any((f) => f.name == marqueurDossier), isFalse);
    for (final item in inFolder) {
      final still = repo.items.firstWhere((i) => i.id == item.id);
      expect(still.folderId, isNull);
    }
  });
}
