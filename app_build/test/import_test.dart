import 'package:flutter_test/flutter_test.dart';

import 'package:password_manager/data/import/csv_table.dart';
import 'package:password_manager/data/import/importers.dart';
import 'package:password_manager/data/models/cipher.dart';

/// Les fixtures reproduisent les en-têtes réels de chaque gestionnaire. C'est le
/// seul moyen de vérifier la correspondance de colonnes : un mappage écrit
/// « de mémoire » se trompe systématiquement sur un format ou deux.

LoginData login(CipherItem item) => item.data as LoginData;

CipherItem byName(ParsedImport out, String name) =>
    out.items.firstWhere((i) => i.data.name == name);

void main() {
  group('parseur CSV', () {
    test('conserve une note multiligne entre guillemets', () {
      // Le parseur du serveur v1 découpait sur \n sans regarder les guillemets :
      // la note s'arrêtait à sa première ligne.
      final table = CsvTable.parse(
        'name,password,notes\n'
        'Test,pw,"ligne un\nligne deux"\n',
      );
      expect(table.body.single[2], 'ligne un\nligne deux');
    });

    test('gère les guillemets doublés', () {
      final table = CsvTable.parse('name,password\n"il a dit ""bonjour""",x\n');
      expect(table.body.single[0], 'il a dit "bonjour"');
    });

    test('gère les fins de ligne Windows', () {
      final table = CsvTable.parse('name,password\r\nTest,pw\r\n');
      expect(table.body.single, ['Test', 'pw']);
    });

    test('devine un séparateur point-virgule', () {
      // Export européen : lu avec la virgule, il ne donnerait qu'une colonne.
      final table = CsvTable.parseAuto('name;username;password\nTest;a;b\n');
      expect(table.body.single.length, 3);
      expect(table.body.single[2], 'b');
    });

    test('devine une tabulation', () {
      final table = CsvTable.parseAuto('name\tusername\tpassword\nTest\ta\tb\n');
      expect(table.body.single.length, 3);
    });

    test('ne prend pas une ligne de données pour un en-tête', () {
      final table = CsvTable.parse('https://exemple.com,tannou,pw\n');
      expect(table.header, isNull);
      expect(table.body.length, 1);
    });
  });

  group('Bitwarden JSON', () {
    const source = '''
    {
      "encrypted": false,
      "folders": [
        {"id": "f-1", "name": "Banque"},
        {"id": "f-2", "name": "Dossier vide"}
      ],
      "items": [
        {
          "type": 1, "name": "GitHub", "folderId": "f-1", "favorite": true,
          "reprompt": 1,
          "notes": "note de test",
          "login": {
            "username": "tannou",
            "password": "hunter2",
            "totp": "JBSWY3DPEHPK3PXP",
            "uris": [
              {"uri": "https://github.com", "match": 0},
              {"uri": "https://gist.github.com", "match": 3}
            ]
          },
          "fields": [
            {"name": "code de secours", "value": "AAAA", "type": 1},
            {"name": "actif", "value": "true", "type": 2}
          ],
          "passwordHistory": [
            {"password": "ancien1", "lastUsedDate": "2025-01-01T10:00:00.000Z"}
          ]
        },
        {
          "type": 3, "name": "Carte Visa",
          "card": {
            "cardholderName": "TANNOU ABOU", "number": "4111111111111111",
            "expMonth": "12", "expYear": "2030", "code": "123", "brand": "Visa"
          }
        },
        {
          "type": 4, "name": "Mon identité",
          "identity": {
            "firstName": "Tannou", "lastName": "Abou",
            "email": "a@b.c", "ssn": "123-45-6789", "country": "CI"
          }
        },
        {"type": 2, "name": "Ma note", "notes": "contenu secret"},
        {"type": 9, "name": "Type inconnu"}
      ]
    }
    ''';

    test('est détecté automatiquement', () {
      expect(detectImporter(source), isA<BitwardenImporter>());
    });

    test('importe les quatre types et signale l’inconnu', () {
      final out = parseImport(source);
      expect(out.sourceLabel, 'Bitwarden (JSON)');
      expect(out.count, 4);
      expect(out.byType[CipherType.login], 1);
      expect(out.byType[CipherType.card], 1);
      expect(out.byType[CipherType.identity], 1);
      expect(out.byType[CipherType.secureNote], 1);
      expect(out.skipped.single, contains('type 9'));
    });

    test('conserve tout le détail d’un identifiant', () {
      final item = byName(parseImport(source), 'GitHub');
      final data = login(item);

      expect(item.favorite, isTrue);
      expect(item.reprompt, isTrue);
      expect(item.folderId, 'Banque');
      expect(data.username, 'tannou');
      expect(data.password, 'hunter2');
      expect(data.totp, 'JBSWY3DPEHPK3PXP');
      expect(data.notes, 'note de test');
      expect(data.uris.length, 2);
      expect(data.uris[1].match, UriMatchType.exact);
      expect(data.fields.length, 2);
      expect(data.fields[0].type, CustomFieldType.hidden);
      expect(data.fields[1].type, CustomFieldType.boolean);
      expect(data.passwordHistory.single.password, 'ancien1');
    });

    test('ne recrée que les dossiers réellement utilisés', () {
      final out = parseImport(source);
      expect(out.folderNames, ['Banque']);
    });

    test('conserve les champs de carte et d’identité', () {
      final out = parseImport(source);
      final card = byName(out, 'Carte Visa').data as CardData;
      expect(card.number, '4111111111111111');
      expect(card.code, '123');
      expect(card.last4, '1111');

      final identity = byName(out, 'Mon identité').data as IdentityData;
      expect(identity.fullName, 'Tannou Abou');
      expect(identity.ssn, '123-45-6789');
      expect(identity.country, 'CI');
    });

    test('refuse un export chiffré avec une consigne utilisable', () {
      expect(
        () => parseImport('{"encrypted": true, "items": []}'),
        throwsA(
          isA<ImportFormatException>().having(
            (e) => e.message,
            'message',
            contains('non chiffré'),
          ),
        ),
      );
    });

    test('n’invente pas de date de changement de mot de passe', () {
      expect(login(byName(parseImport(source), 'GitHub')).passwordUpdatedAt,
          isNull);
    });
  });

  group('CSV Chrome', () {
    const source = 'name,url,username,password,note\n'
        'github.com,https://github.com,tannou,hunter2,perso\n'
        ',https://exemple.com,sansnom,pw,\n';

    test('est reconnu et étiqueté', () {
      final out = parseImport(source);
      expect(out.sourceLabel, 'CSV Chrome / Edge');
      expect(out.count, 2);
    });

    test('retombe sur l’hôte quand le nom manque', () {
      final out = parseImport(source);
      expect(out.items.any((i) => i.data.name == 'exemple.com'), isTrue);
    });

    test('promeut l’URL en URI', () {
      expect(login(byName(parseImport(source), 'github.com')).uris.single.uri,
          'https://github.com');
    });
  });

  group('CSV LastPass', () {
    const source = 'url,username,password,totp,extra,name,grouping,fav\n'
        'https://github.com,tannou,hunter2,JBSWY3DPEHPK3PXP,ma note,GitHub,Dev,1\n'
        'http://sn,,,,note seule,Note,Perso,0\n';

    test('mappe les colonnes propres à LastPass', () {
      final out = parseImport(source);
      expect(out.sourceLabel, 'CSV LastPass');

      final item = byName(out, 'GitHub');
      final data = login(item);
      expect(data.username, 'tannou');
      expect(data.totp, 'JBSWY3DPEHPK3PXP');
      // « extra » est la colonne de notes chez LastPass.
      expect(data.notes, 'ma note');
      expect(item.favorite, isTrue, reason: 'fav=1 doit devenir un favori');
      expect(item.folderId, 'Dev');
    });

    test('collecte les dossiers', () {
      final out = parseImport(source);
      expect(out.folderNames.toSet(), {'Dev', 'Perso'});
    });
  });

  group('CSV 1Password', () {
    const source = 'Title,Url,Username,Password,OTPAuth,Favorite,Notes\n'
        'GitHub,https://github.com,tannou,hunter2,'
        'otpauth://totp/GitHub?secret=JBSWY3DPEHPK3PXP,true,note\n';

    test('mappe Title et OTPAuth', () {
      final out = parseImport(source);
      expect(out.sourceLabel, 'CSV 1Password');
      final item = byName(out, 'GitHub');
      expect(login(item).totp, startsWith('otpauth://'));
      expect(item.favorite, isTrue);
    });
  });

  group('CSV KeePassXC', () {
    const source = '"Group","Title","Username","Password","URL","Notes","TOTP"\n'
        '"Base/Dev","GitHub","tannou","hunter2","https://github.com",'
        '"ligne un\nligne deux","JBSWY3DPEHPK3PXP"\n';

    test('mappe Group en dossier et conserve la note multiligne', () {
      final out = parseImport(source);
      expect(out.sourceLabel, 'CSV KeePassXC');
      final item = byName(out, 'GitHub');
      expect(item.folderId, 'Base/Dev');
      expect(login(item).notes, 'ligne un\nligne deux');
      expect(login(item).totp, 'JBSWY3DPEHPK3PXP');
    });
  });

  group('CSV Dashlane', () {
    const source = 'username,title,password,note,url,category,otpSecret\n'
        'tannou,GitHub,hunter2,ma note,https://github.com,Dev,SECRET32\n';

    test('mappe otpSecret et category', () {
      final out = parseImport(source);
      final item = byName(out, 'GitHub');
      expect(login(item).totp, 'SECRET32');
      expect(item.folderId, 'Dev');
    });
  });

  group('CSV Firefox', () {
    const source = 'url,username,password,httpRealm,formActionOrigin,guid\n'
        'https://github.com,tannou,hunter2,,,{abc}\n';

    test('fonctionne sans colonne de nom', () {
      final out = parseImport(source);
      expect(out.sourceLabel, 'CSV Firefox');
      expect(out.items.single.data.name, 'github.com');
    });
  });

  group('KeePass XML', () {
    const source = '''
    <?xml version="1.0" encoding="utf-8"?>
    <KeePassFile>
      <Root>
        <Group>
          <Name>MaBase</Name>
          <Entry>
            <String><Key>Title</Key><Value>Racine</Value></String>
            <String><Key>UserName</Key><Value>root</Value></String>
            <String><Key>Password</Key><Value>pw-racine</Value></String>
          </Entry>
          <Group>
            <Name>Dev</Name>
            <Group>
              <Name>Git</Name>
              <Entry>
                <String><Key>Title</Key><Value>GitHub</Value></String>
                <String><Key>UserName</Key><Value>tannou</Value></String>
                <String><Key>Password</Key><Value>hunter2</Value></String>
                <String><Key>URL</Key><Value>https://github.com</Value></String>
                <String><Key>Notes</Key><Value>ma note</Value></String>
                <String><Key>otp</Key><Value>JBSWY3DPEHPK3PXP</Value></String>
                <String>
                  <Key>Question secrete</Key>
                  <Value ProtectedInMemory="True">ma reponse</Value>
                </String>
                <String><Key>Numero client</Key><Value>12345</Value></String>
              </Entry>
            </Group>
          </Group>
        </Group>
      </Root>
    </KeePassFile>
    ''';

    test('est détecté automatiquement', () {
      expect(detectImporter(source), isA<KeepassXmlImporter>());
    });

    test('aplatit la hiérarchie de groupes en un chemin', () {
      final out = parseImport(source);
      expect(out.sourceLabel, 'KeePass (XML)');
      final item = byName(out, 'GitHub');
      // La racine « MaBase » est le nom de la base, pas un dossier.
      expect(item.folderId, 'Dev / Git');
    });

    test('n’attribue pas de dossier aux entrées de la racine', () {
      expect(byName(parseImport(source), 'Racine').folderId, isNull);
    });

    test('distingue les champs protégés des champs libres', () {
      final data = login(byName(parseImport(source), 'GitHub'));
      final protege =
          data.fields.firstWhere((f) => f.name == 'Question secrete');
      final libre = data.fields.firstWhere((f) => f.name == 'Numero client');
      expect(protege.type, CustomFieldType.hidden);
      expect(libre.type, CustomFieldType.text);
    });

    test('reconnaît le champ otp comme secret TOTP', () {
      expect(login(byName(parseImport(source), 'GitHub')).totp,
          'JBSWY3DPEHPK3PXP');
    });

    test('rejette un XML qui n’est pas du KeePass', () {
      expect(
        () => parseImport('<KeePassFile><Autre/></KeePassFile>'),
        throwsA(isA<ImportFormatException>()),
      );
    });
  });

  group('PassVault v1', () {
    test('lit la sortie de export-v1.js', () {
      const source = '{"version":1,"entries":['
          '{"site":"github.com","email":"tannou","password":"hunter2","note":"perso"},'
          '{"site":"Ma banque","email":"a@b.c","password":"s3cr3t","note":""}]}';
      final out = parseImport(source);
      expect(out.sourceLabel, 'PassVault v1 (JSON)');
      expect(out.count, 2);
      expect(login(byName(out, 'github.com')).uris.single.uri,
          'https://github.com');
      // « Ma banque » n'est pas un domaine : pas d'URI inventée.
      expect(login(byName(out, 'Ma banque')).uris, isEmpty);
    });

    test('lit le tableau nu de l’ancienne app', () {
      const source = '[{"site":"netflix.com","email":"a@b.c","password":"pw"}]';
      final out = parseImport(source);
      expect(out.sourceLabel, 'PassVault v1 (JSON)');
      expect(out.count, 1);
    });

    test('lit le CSV v1 et garde son étiquette', () {
      const source = 'site,email,password,note\n'
          'github.com,tannou,hunter2,perso\n';
      final out = parseImport(source);
      expect(out.sourceLabel, 'PassVault v1 (CSV)');
      expect(login(out.items.single).password, 'hunter2');
    });

    test('déballe les noms au format Markdown', () {
      // Cas rencontré dans un vrai coffre v1 : le nom du site avait été collé
      // depuis un document, sous forme de lien Markdown. Sans déballage, l'URI
      // enregistrée était la chaîne entière et l'autofill ne correspondait
      // jamais.
      const source = '''
      {"version":1,"entries":[
        {"site":"[www.paypal.com](https://www.paypal.com)","email":"a@b.c","password":"pw"},
        {"site":"[](https://www.netflix.com)","email":"x","password":"pw"},
        {"site":"[Ma banque](https://mabanque.ci/login)","email":"y","password":"pw"}
      ]}
      ''';
      final out = parseImport(source);
      expect(out.count, 3);

      final paypal = out.items.first;
      expect(paypal.data.name, 'www.paypal.com');
      expect(login(paypal).uris.single.uri, 'https://www.paypal.com');
      expect(login(paypal).uris.single.host, 'paypal.com');

      // Libellé vide : on retombe sur l'URL.
      final netflix = out.items[1];
      expect(netflix.data.name, 'https://www.netflix.com');
      expect(login(netflix).uris.single.uri, 'https://www.netflix.com');

      // Libellé lisible : on le garde, et l'URI conserve son chemin.
      final banque = out.items[2];
      expect(banque.data.name, 'Ma banque');
      expect(login(banque).uris.single.uri, 'https://mabanque.ci/login');
    });

    test('ne touche pas aux noms qui ne sont pas des liens', () {
      const source = '''
      [{"site":"Ma banque [perso]","email":"a","password":"p"},
       {"site":"github.com","email":"b","password":"p"}]
      ''';
      final out = parseImport(source);
      expect(out.items[0].data.name, 'Ma banque [perso]');
      expect(out.items[1].data.name, 'github.com');
    });

    test('signale les entrées inexploitables', () {
      const source = '[{"site":"ok.com","email":"a","password":"p"},'
          '{"site":"","email":"","password":""},"pas un objet"]';
      final out = parseImport(source);
      expect(out.count, 1);
      expect(out.skipped.length, 2);
    });
  });

  group('détection et erreurs', () {
    test('rejette un fichier vide', () {
      expect(() => parseImport('   '), throwsA(isA<ImportFormatException>()));
    });

    test('rejette un format inconnu avec la liste des formats lus', () {
      expect(
        () => parseImport('ceci est du texte libre, sans structure'),
        throwsA(
          isA<ImportFormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('Bitwarden'), contains('KeePass')),
          ),
        ),
      );
    });

    test('rejette un CSV sans colonne de mot de passe', () {
      expect(
        () => parseImport('name,url\nTest,https://x.com\n'),
        throwsA(isA<ImportFormatException>()),
      );
    });

    test('les extensions proposées couvrent tous les formats', () {
      expect(importExtensions, containsAll(['json', 'csv', 'xml']));
    });
  });
}
