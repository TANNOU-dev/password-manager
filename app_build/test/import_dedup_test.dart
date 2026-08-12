import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:password_manager/core/crypto/kdf_params.dart';
import 'package:password_manager/data/api/api_client.dart';
import 'package:password_manager/data/api/coffort_api.dart';
import 'package:password_manager/data/import/importers.dart';
import 'package:password_manager/data/models/cipher.dart';
import 'package:password_manager/data/vault_repository.dart';

/// Doublons à l'import.
///
/// Un export contient très souvent deux fois le même compte : une entrée saisie
/// à la main, puis la même reprise par le navigateur. Les enregistrer toutes les
/// deux donne un coffre où l'on ne sait plus laquelle fait foi, et où changer un
/// mot de passe n'en corrige qu'une.
///
/// Le critère retenu est l'égalité du **contenu entier**. Deux comptes distincts
/// sur un même site — le cas d'une adresse personnelle et d'une professionnelle —
/// doivent survivre tous les deux ; c'est ce que vérifie la moitié de ces tests.

String _csv(List<List<String>> rows) {
  final out = StringBuffer()
    ..writeln('folder,name,url,username,password,totp,notes,favorite');
  for (final r in rows) {
    out.writeln(r.join(','));
  }
  return out.toString();
}

void main() {
  group('doublons dans le fichier', () {
    test('deux lignes identiques n’en donnent qu’une', () {
      final parsed = parseImport(_csv([
        ['', 'Gmail', 'https://gmail.com', 'moi@gmail.com', 'hunter2', '', '', ''],
        ['', 'Gmail', 'https://gmail.com', 'moi@gmail.com', 'hunter2', '', '', ''],
      ]));

      expect(parsed.count, 1);
      expect(parsed.duplicatesInFile, 1);
    });

    test('trois exemplaires : il en reste un, deux sont comptés', () {
      final ligne = ['', 'Gmail', 'https://gmail.com', 'moi@gmail.com', 'x', '', '', ''];
      final parsed = parseImport(_csv([ligne, ligne, ligne]));

      expect(parsed.count, 1);
      expect(parsed.duplicatesInFile, 2);
    });

    test('un mot de passe différent n’est pas un doublon', () {
      // Le cas dangereux à ne pas confondre : même compte, mot de passe changé.
      // Écarter la seconde ligne perdrait le mot de passe à jour.
      final parsed = parseImport(_csv([
        ['', 'Gmail', 'https://gmail.com', 'moi@gmail.com', 'ancien', '', '', ''],
        ['', 'Gmail', 'https://gmail.com', 'moi@gmail.com', 'nouveau', '', '', ''],
      ]));

      expect(parsed.count, 2);
      expect(parsed.duplicatesInFile, 0);
    });

    test('deux comptes sur le même site restent deux entrées', () {
      final parsed = parseImport(_csv([
        ['', 'Gmail', 'https://gmail.com', 'perso@gmail.com', 'a', '', '', ''],
        ['', 'Gmail', 'https://gmail.com', 'pro@gmail.com', 'b', '', '', ''],
      ]));

      expect(parsed.count, 2);
      expect(parsed.duplicatesInFile, 0);
    });

    test('une note qui diffère suffit à distinguer', () {
      final parsed = parseImport(_csv([
        ['', 'Gmail', 'https://gmail.com', 'moi@gmail.com', 'x', '', 'perso', ''],
        ['', 'Gmail', 'https://gmail.com', 'moi@gmail.com', 'x', '', 'travail', ''],
      ]));

      expect(parsed.count, 2);
    });

    test('la première occurrence est celle qui reste', () {
      // Elle porte le dossier ; la seconde n'en a pas. On garde la première,
      // donc l'information de rangement survit.
      final parsed = parseImport(_csv([
        ['Perso', 'Gmail', 'https://gmail.com', 'moi@gmail.com', 'x', '', '', ''],
        ['Perso', 'Gmail', 'https://gmail.com', 'moi@gmail.com', 'x', '', '', ''],
      ]));

      expect(parsed.count, 1);
      expect(parsed.items.single.folderId, 'Perso');
    });
  });

  group('empreinte de contenu', () {
    const base = CipherItem(
      id: '00000000-0000-4000-8000-000000000001',
      data: LoginData(name: 'Gmail', username: 'moi', password: 'x'),
    );

    test('l’identifiant n’entre pas dans l’empreinte', () {
      const autre = CipherItem(
        id: '00000000-0000-4000-8000-000000000002',
        data: LoginData(name: 'Gmail', username: 'moi', password: 'x'),
      );
      expect(base.contentFingerprint, autre.contentFingerprint);
    });

    test('le dossier et le favori non plus', () {
      // Deux lignes du même export peuvent différer par le rangement seul :
      // ça reste le même compte.
      final range = base.copyWith(folderId: 'f1', favorite: true);
      expect(range.contentFingerprint, base.contentFingerprint);
    });

    test('un champ du contenu, si', () {
      const different = CipherItem(
        id: '00000000-0000-4000-8000-000000000001',
        data: LoginData(name: 'Gmail', username: 'moi', password: 'y'),
      );
      expect(base.contentFingerprint, isNot(different.contentFingerprint));
    });

    test('deux types différents ne se confondent pas', () {
      const note = CipherItem(
        id: '00000000-0000-4000-8000-000000000001',
        data: SecureNoteData(name: 'Gmail'),
      );
      const login = CipherItem(
        id: '00000000-0000-4000-8000-000000000001',
        data: LoginData(name: 'Gmail'),
      );
      expect(note.contentFingerprint, isNot(login.contentFingerprint));
    });
  });

  group('depuis un export Bitwarden', () {
    test('le même élément deux fois n’est importé qu’une', () {
      final item = {
        'id': '1',
        'type': 1,
        'name': 'Gmail',
        'login': {'username': 'moi@gmail.com', 'password': 'hunter2'},
      };
      final parsed = parseImport(jsonEncode({
        'encrypted': false,
        'items': [item, {...item, 'id': '2'}],
      }));

      // Les identifiants diffèrent, le contenu non : c'est un doublon.
      expect(parsed.count, 1);
      expect(parsed.duplicatesInFile, 1);
    });
  });
  group('nettoyage du coffre existant', () {
    const gmail = LoginData(
      name: 'Gmail',
      username: 'moi@gmail.com',
      password: 'hunter2',
    );

    CipherItem item(String id, CipherData data) =>
        CipherItem(id: '00000000-0000-4000-8000-00000000000$id', data: data);

    Future<VaultRepository> seeded(List<CipherItem> items) async {
      final repo = VaultRepository(
        api: CoffortApi(ApiClient(baseUrl: 'http://127.0.0.1:1')),
        deviceName: 'test',
      );
      await repo.seedForTest(
        items: items,
        profile: const VaultProfile(
          id: 'u1',
          email: 'tannou@coffort.test',
          kdf: KdfParams.argon2idDefault,
          kdfSalt: '0123456789abcdef0123456789abcdef',
          protectedKey: '1.AAAA',
        ),
      );
      return repo;
    }

    test('compte les exemplaires en trop, pas les groupes', () async {
      // Trois exemplaires d'une entrée et deux d'une autre : quatre en trop,
      // pas deux. C'est le nombre qu'on propose de retirer.
      final repo = await seeded([
        item('1', gmail),
        item('2', gmail),
        item('3', gmail),
        item('4', const LoginData(name: 'PayPal', password: 'x')),
        item('5', const LoginData(name: 'PayPal', password: 'x')),
      ]);
      addTearDown(repo.dispose);

      expect(repo.duplicateGroups().length, 2);
      expect(repo.duplicateCount, 3);
    });

    test('un coffre sans doublon n’en signale aucun', () async {
      final repo = await seeded([
        item('1', gmail),
        item('2', const LoginData(name: 'PayPal', password: 'x')),
      ]);
      addTearDown(repo.dispose);

      expect(repo.duplicateGroups(), isEmpty);
      expect(repo.duplicateCount, 0);
    });

    test('un mot de passe différent n’est pas un doublon', () async {
      // Le même compte à deux époques. Les fondre perdrait le mot de passe
      // à jour, et on ne saurait pas lequel des deux a survécu.
      final repo = await seeded([
        item('1', gmail),
        item('2', const LoginData(
          name: 'Gmail',
          username: 'moi@gmail.com',
          password: 'nouveau',
        )),
      ]);
      addTearDown(repo.dispose);

      expect(repo.duplicateCount, 0);
    });

    test('la corbeille ne compte pas comme doublon', () async {
      // Sinon une entrée jetée ferait passer sa jumelle active pour un doublon.
      final repo = await seeded([
        item('1', gmail),
        CipherItem(
          id: '00000000-0000-4000-8000-000000000002',
          data: gmail,
          deletedAt: DateTime.utc(2026, 8, 1),
        ),
      ]);
      addTearDown(repo.dispose);

      expect(repo.duplicateCount, 0);
    });

    test('le cache suit les mutations du coffre', () async {
      // Le décompte est lu dans un `build`, donc à chaque redessin : il est
      // mémoïsé. Ce test vérifie que la mémoïsation ne survit pas à une
      // modification — un cache correct sur un coffre figé mais périmé après
      // une suppression serait pire que pas de cache du tout.
      final repo = await seeded([item('1', gmail), item('2', gmail)]);
      addTearDown(repo.dispose);
      expect(repo.duplicateCount, 1);

      await repo.seedForTest(
        items: [item('1', gmail)],
        profile: repo.profile!,
      );
      expect(repo.duplicateCount, 0);
    });

    test('un élément sans identifiant serveur n’est jamais celui qu’on garde',
        () async {
      // On ne saurait pas le supprimer ensuite : le conserver reviendrait à
      // garder l'exemplaire dont on ne peut plus rien faire.
      final repo = await seeded([
        const CipherItem(data: gmail),
        item('2', gmail),
      ]);
      addTearDown(repo.dispose);

      final group = repo.duplicateGroups().single;
      expect(group.first.id, isNotNull);
      expect(group.last.id, isNull);
    });
  });
}
