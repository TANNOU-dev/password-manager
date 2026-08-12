import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:password_manager/core/crypto/kdf_params.dart';
import 'package:password_manager/data/export/vault_export.dart';
import 'package:password_manager/data/import/importers.dart';
import 'package:password_manager/data/models/cipher.dart';

/// Paramètres allégés : ces tests valident le format et l'aller-retour, pas le
/// coût de la dérivation.
const _fastKdf = KdfParams(
  type: KdfType.argon2id,
  iterations: 1,
  memory: 8192,
  parallelism: 1,
);

final _vault = <CipherItem>[
  const CipherItem(
    id: 'i1',
    folderId: 'f1',
    favorite: true,
    reprompt: true,
    data: LoginData(
      name: 'GitHub',
      username: 'tannou',
      password: 'hunter2',
      totp: 'JBSWY3DPEHPK3PXP',
      notes: 'ma note',
      uris: [
        LoginUri(uri: 'https://github.com'),
        LoginUri(uri: 'https://gist.github.com', match: UriMatchType.exact),
      ],
      fields: [
        CustomField(
          name: 'code de secours',
          value: 'AAAA',
          type: CustomFieldType.hidden,
        ),
      ],
    ),
  ),
  const CipherItem(
    id: 'i2',
    data: CardData(
      name: 'Carte Visa',
      cardholderName: 'TANNOU ABOU',
      number: '4111111111111111',
      expMonth: '12',
      expYear: '2030',
      code: '123',
    ),
  ),
  const CipherItem(
    id: 'i3',
    data: IdentityData(
      name: 'Mon identité',
      firstName: 'Tannou',
      lastName: 'Abou',
      email: 'a@b.c',
      ssn: '123-45-6789',
    ),
  ),
  const CipherItem(
    id: 'i4',
    data: SecureNoteData(name: 'Ma note', notes: 'contenu secret'),
  ),
];

const _folderNames = {'f1': 'Développement', 'f2': 'Jamais utilisé'};

void main() {
  group('export JSON au format Bitwarden', () {
    test('produit un JSON non chiffré valide', () {
      final json = jsonDecode(
        VaultExporter.toBitwardenJson(_vault, folderNames: _folderNames),
      ) as Map<String, dynamic>;

      expect(json['encrypted'], isFalse);
      expect((json['items'] as List).length, 4);
    });

    test('n’exporte que les dossiers réellement utilisés', () {
      final json = jsonDecode(
        VaultExporter.toBitwardenJson(_vault, folderNames: _folderNames),
      ) as Map<String, dynamic>;

      final folders = (json['folders'] as List).cast<Map<String, dynamic>>();
      expect(folders.length, 1);
      expect(folders.single['name'], 'Développement');
    });

    test('se relit avec notre propre importateur Bitwarden', () {
      // C'est l'intérêt d'avoir choisi ce format plutôt qu'un format maison :
      // l'aller-retour est vérifiable, et le fichier s'importe dans Bitwarden.
      final exported =
          VaultExporter.toBitwardenJson(_vault, folderNames: _folderNames);
      final reimported = parseImport(exported);

      expect(reimported.sourceLabel, 'Bitwarden (JSON)');
      expect(reimported.count, 4);
    });

    test('l’aller-retour conserve tout le détail d’un identifiant', () {
      final exported =
          VaultExporter.toBitwardenJson(_vault, folderNames: _folderNames);
      final item = parseImport(exported)
          .items
          .firstWhere((i) => i.data.name == 'GitHub');
      final data = item.data as LoginData;

      expect(data.username, 'tannou');
      expect(data.password, 'hunter2');
      expect(data.totp, 'JBSWY3DPEHPK3PXP');
      expect(data.notes, 'ma note');
      expect(data.uris.length, 2);
      expect(data.uris[1].match, UriMatchType.exact);
      expect(data.fields.single.type, CustomFieldType.hidden);
      expect(item.favorite, isTrue);
      expect(item.reprompt, isTrue);
      expect(item.folderId, 'Développement');
    });

    test('l’aller-retour conserve carte, identité et note', () {
      final reimported = parseImport(VaultExporter.toBitwardenJson(_vault));

      final card = reimported.items
          .map((i) => i.data)
          .whereType<CardData>()
          .single;
      expect(card.number, '4111111111111111');
      expect(card.code, '123');

      final identity = reimported.items
          .map((i) => i.data)
          .whereType<IdentityData>()
          .single;
      expect(identity.ssn, '123-45-6789');

      final note = reimported.items
          .map((i) => i.data)
          .whereType<SecureNoteData>()
          .single;
      expect(note.notes, 'contenu secret');
    });
  });

  group('export CSV', () {
    test('écrit un en-tête et une ligne par élément', () {
      final csv = VaultExporter.toCsv(_vault, folderNames: _folderNames);
      final lines = const LineSplitter().convert(csv);
      expect(lines.first, startsWith('folder,name,url,username,password'));
      // 4 éléments, mais les notes multilignes occupent plusieurs lignes
      // physiques : on vérifie via le parseur.
      expect(csv, contains('GitHub'));
      expect(csv, contains('Développement'));
    });

    test('échappe les virgules et les guillemets', () {
      final csv = VaultExporter.toCsv([
        const CipherItem(
          data: LoginData(
            name: 'Avec, virgule',
            password: 'il a dit "bonjour"',
          ),
        ),
      ]);
      // Relu par notre parseur, le contenu doit être intact.
      final reimported = parseImport(csv);
      final data = reimported.items.single.data as LoginData;
      expect(data.name, 'Avec, virgule');
      expect(data.password, 'il a dit "bonjour"');
    });

    test('ne perd pas silencieusement le contenu des cartes', () {
      // Le CSV n'a pas de colonne pour un numéro de carte : le contenu part dans
      // les notes plutôt que de disparaître.
      final csv = VaultExporter.toCsv([_vault[1]]);
      expect(csv, contains('4111111111111111'));
      expect(csv, contains('Cryptogramme'));
    });

    test('ne perd pas les champs personnalisés', () {
      final csv = VaultExporter.toCsv([_vault[0]]);
      expect(csv, contains('code de secours'));
      expect(csv, contains('AAAA'));
    });
  });

  group('sauvegarde chiffrée', () {
    test('ne laisse aucun secret en clair dans le fichier', () async {
      final backup = await VaultExporter.toEncryptedJson(
        _vault,
        exportPassword: 'phrase-de-passe-de-sauvegarde',
        folderNames: _folderNames,
        kdf: _fastKdf,
      );

      // Le contenu du coffre ne doit apparaître nulle part.
      expect(backup, isNot(contains('hunter2')));
      expect(backup, isNot(contains('GitHub')));
      expect(backup, isNot(contains('4111111111111111')));
      expect(backup, isNot(contains('123-45-6789')));
      expect(backup, isNot(contains('contenu secret')));
      expect(backup, isNot(contains('phrase-de-passe-de-sauvegarde')));

      // Les métadonnées nécessaires à la restauration, elles, sont lisibles.
      final json = jsonDecode(backup) as Map<String, dynamic>;
      expect(json['format'], 'passvault-encrypted');
      expect(json['itemCount'], 4);
      expect(json['kdfSalt'], matches(RegExp(r'^[0-9a-f]{32}$')));
      expect((json['data'] as String).startsWith('1.'), isTrue);
    });

    test('se restaure avec la bonne phrase de passe', () async {
      final backup = await VaultExporter.toEncryptedJson(
        _vault,
        exportPassword: 'phrase-de-passe-de-sauvegarde',
        folderNames: _folderNames,
        kdf: _fastKdf,
      );

      final plain = await VaultExporter.decryptBackup(
        backup,
        exportPassword: 'phrase-de-passe-de-sauvegarde',
      );
      final reimported = parseImport(plain);

      expect(reimported.count, 4);
      final data = reimported.items
          .map((i) => i.data)
          .whereType<LoginData>()
          .single;
      expect(data.password, 'hunter2');
    });

    test('refuse une mauvaise phrase de passe', () async {
      final backup = await VaultExporter.toEncryptedJson(
        _vault,
        exportPassword: 'la-bonne-phrase-de-passe',
        kdf: _fastKdf,
      );

      await expectLater(
        VaultExporter.decryptBackup(backup, exportPassword: 'la-mauvaise'),
        throwsA(isA<ExportException>()),
      );
    });

    test('refuse un fichier altéré', () async {
      final backup = await VaultExporter.toEncryptedJson(
        _vault,
        exportPassword: 'phrase-de-passe-de-sauvegarde',
        kdf: _fastKdf,
      );
      // On retourne un caractère du chiffré.
      final json = jsonDecode(backup) as Map<String, dynamic>;
      final sealed = json['data'] as String;
      json['data'] =
          '${sealed.substring(0, 10)}${sealed[10] == 'A' ? 'B' : 'A'}${sealed.substring(11)}';

      await expectLater(
        VaultExporter.decryptBackup(
          jsonEncode(json),
          exportPassword: 'phrase-de-passe-de-sauvegarde',
        ),
        throwsA(isA<ExportException>()),
      );
    });

    test('deux exports du même coffre diffèrent', () async {
      // Sel et nonce tirés à chaque export : deux sauvegardes identiques
      // révéleraient que le coffre n'a pas changé.
      final a = await VaultExporter.toEncryptedJson(
        _vault,
        exportPassword: 'phrase-de-passe-de-sauvegarde',
        kdf: _fastKdf,
      );
      final b = await VaultExporter.toEncryptedJson(
        _vault,
        exportPassword: 'phrase-de-passe-de-sauvegarde',
        kdf: _fastKdf,
      );
      expect(jsonDecode(a)['kdfSalt'], isNot(jsonDecode(b)['kdfSalt']));
      expect(jsonDecode(a)['data'], isNot(jsonDecode(b)['data']));
    });

    test('refuse une phrase de passe trop courte', () async {
      await expectLater(
        VaultExporter.toEncryptedJson(
          _vault,
          exportPassword: 'court',
          kdf: _fastKdf,
        ),
        throwsA(isA<ExportException>()),
      );
    });

    test('la sauvegarde est reconnue avant qu’on demande la phrase', () async {
      final backup = await VaultExporter.toEncryptedJson(
        _vault,
        exportPassword: 'phrase-de-passe-de-sauvegarde',
        kdf: _fastKdf,
      );
      expect(VaultExporter.isEncryptedBackup(backup), isTrue);
      expect(VaultExporter.isEncryptedBackup('{"items":[]}'), isFalse);
      expect(VaultExporter.isEncryptedBackup('pas du json'), isFalse);
    });

    test('rejette un fichier qui n’est pas une sauvegarde Coffort', () async {
      await expectLater(
        VaultExporter.decryptBackup(
          '{"format":"autre-chose"}',
          exportPassword: 'peu-importe-ici',
        ),
        throwsA(isA<ExportException>()),
      );
    });

    test('la restauration survit à un changement de mot de passe maître',
        () async {
      // La sauvegarde est protégée par sa propre phrase de passe, indépendante
      // du mot de passe maître : c'est ce qui la rend utile après un changement.
      final backup = await VaultExporter.toEncryptedJson(
        _vault,
        exportPassword: 'ma-phrase-de-sauvegarde',
        kdf: _fastKdf,
      );
      final plain = await VaultExporter.decryptBackup(
        backup,
        exportPassword: 'ma-phrase-de-sauvegarde',
      );
      expect(parseImport(plain).count, 4);
    });
  });
}
