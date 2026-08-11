import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:password_manager/data/breach/hibp_service.dart';
import 'package:password_manager/data/models/cipher.dart';
import 'package:password_manager/features/security/vault_health.dart';

/// Aucun de ces tests ne touche le réseau : le client HTTP est simulé.
/// C'est indispensable — une suite de tests qui appelle un service tiers est
/// lente, fragile, et envoie de vraies requêtes à chaque exécution.

String sha1Upper(String value) =>
    crypto.sha1.convert(utf8.encode(value)).toString().toUpperCase();

void main() {
  group('protocole k-anonymity', () {
    test('n’envoie que les 5 premiers caractères de l’empreinte', () async {
      const password = 'hunter2';
      final digest = sha1Upper(password);
      Uri? requested;
      Map<String, String>? headers;

      final service = HibpService(
        endpoint: 'https://exemple.test/range',
        client: MockClient((request) async {
          requested = request.url;
          headers = request.headers;
          return http.Response('${digest.substring(5)}:42\n', 200);
        }),
      );

      final count = await service.countFor(password);

      expect(count, 42);
      expect(requested!.path, endsWith('/${digest.substring(0, 5)}'));
      // Le reste de l'empreinte ne doit apparaître nulle part dans la requête.
      expect(requested.toString(), isNot(contains(digest.substring(5))));
      expect(requested.toString(), isNot(contains(password)));
      // Le remplissage masque la taille de la réponse.
      expect(headers!['Add-Padding'], 'true');
    });

    test('renvoie 0 quand le suffixe est absent du seau', () async {
      final service = HibpService(
        endpoint: 'https://exemple.test/range',
        client: MockClient((_) async => http.Response(
              '0000000000000000000000000000000000000:9\n'
              '1111111111111111111111111111111111111:3\n',
              200,
            )),
      );
      expect(await service.countFor('un-mot-de-passe-probablement-inedit'), 0);
    });

    test('ignore le remplissage de Add-Padding', () async {
      const password = 'hunter2';
      final digest = sha1Upper(password);
      final service = HibpService(
        endpoint: 'https://exemple.test/range',
        client: MockClient((_) async => http.Response(
              // Entrées factices à compte nul, plus la vraie.
              'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA:0\n'
              'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB:0\n'
              '${digest.substring(5)}:7\n',
              200,
            )),
      );
      expect(await service.countFor(password), 7);
    });

    test('tolère la casse du suffixe renvoyé', () async {
      const password = 'hunter2';
      final digest = sha1Upper(password);
      final service = HibpService(
        endpoint: 'https://exemple.test/range',
        client: MockClient((_) async =>
            http.Response('${digest.substring(5).toLowerCase()}:5\n', 200)),
      );
      expect(await service.countFor(password), 5);
    });

    test('un mot de passe vide ne déclenche aucune requête', () async {
      var called = false;
      final service = HibpService(
        endpoint: 'https://exemple.test/range',
        client: MockClient((_) async {
          called = true;
          return http.Response('', 200);
        }),
      );
      expect(await service.countFor(''), 0);
      expect(called, isFalse);
    });
  });

  group('mise en cache et lots', () {
    test('un préfixe n’est demandé qu’une fois', () async {
      var requests = 0;
      final digest = sha1Upper('hunter2');
      final service = HibpService(
        endpoint: 'https://exemple.test/range',
        client: MockClient((_) async {
          requests++;
          return http.Response('${digest.substring(5)}:1\n', 200);
        }),
      );

      await service.countFor('hunter2');
      await service.countFor('hunter2');
      await service.countFor('hunter2');
      expect(requests, 1, reason: 'le seau doit venir du cache');
    });

    test('un lot déduplique les mots de passe réutilisés', () async {
      var requests = 0;
      final service = HibpService(
        endpoint: 'https://exemple.test/range',
        client: MockClient((_) async {
          requests++;
          return http.Response('', 200);
        }),
      );

      // Quatre entrées, deux mots de passe distincts.
      final result = await service.countForAll(
        ['aaa', 'bbb', 'aaa', 'bbb', ''],
      );
      expect(result.length, 2);
      expect(requests, 2);
    });

    test('rapporte la progression', () async {
      final service = HibpService(
        endpoint: 'https://exemple.test/range',
        client: MockClient((_) async => http.Response('', 200)),
      );
      final steps = <String>[];
      await service.countForAll(
        ['a', 'b', 'c'],
        onProgress: (done, total) => steps.add('$done/$total'),
      );
      expect(steps, ['1/3', '2/3', '3/3']);
    });

    test('vider le cache force une nouvelle requête', () async {
      var requests = 0;
      final service = HibpService(
        endpoint: 'https://exemple.test/range',
        client: MockClient((_) async {
          requests++;
          return http.Response('', 200);
        }),
      );
      await service.countFor('aaa');
      service.clearCache();
      await service.countFor('aaa');
      expect(requests, 2);
    });
  });

  group('pannes', () {
    test('une erreur HTTP est signalée, pas avalée', () async {
      final service = HibpService(
        endpoint: 'https://exemple.test/range',
        client: MockClient((_) async => http.Response('rate limited', 429)),
      );
      // Renvoyer 0 ici déclarerait le mot de passe sain à tort.
      await expectLater(
        service.countFor('hunter2'),
        throwsA(isA<HibpFailure>()),
      );
    });

    test('un réseau injoignable est signalé', () async {
      final service = HibpService(
        endpoint: 'https://exemple.test/range',
        client: MockClient((_) async => throw const HttpExceptionStub()),
      );
      await expectLater(
        service.countFor('hunter2'),
        throwsA(isA<HibpFailure>()),
      );
    });
  });

  group('intégration au rapport de santé', () {
    final items = [
      const CipherItem(
        id: 'a',
        data: LoginData(name: 'Exposé', password: 'MotDePasseFuite2026!'),
      ),
      const CipherItem(
        id: 'b',
        data: LoginData(name: 'Sain', password: 'Kx7mQ2vB9nTz4wLp!Rt'),
      ),
    ];

    test('sans vérification, aucun élément n’est marqué exposé', () {
      final report = VaultHealth.analyse(items);
      expect(report.countOf(HealthIssue.breached), 0);
      // Et rien n'est faussement déclaré vérifié.
      expect(report.analysed.every((h) => h.breachCount == null), isTrue);
    });

    test('un mot de passe trouvé dans une fuite est marqué exposé', () {
      final report = VaultHealth.analyse(
        items,
        breachCounts: const {'MotDePasseFuite2026!': 1523},
      );
      expect(report.countOf(HealthIssue.breached), 1);
      final exposed = report.withIssue(HealthIssue.breached).single;
      expect(exposed.item.data.name, 'Exposé');
      expect(exposed.breachCount, 1523);
    });

    test('un compte de 0 ne marque pas l’élément', () {
      final report = VaultHealth.analyse(
        items,
        breachCounts: const {'Kx7mQ2vB9nTz4wLp!Rt': 0},
      );
      expect(report.countOf(HealthIssue.breached), 0);
    });

    test('une fuite prime sur les autres problèmes', () {
      // « azerty » est faible ET exposé : c'est la fuite qui doit s'afficher.
      final report = VaultHealth.analyse(
        [
          const CipherItem(
            id: 'c',
            data: LoginData(name: 'Double problème', password: 'azerty'),
          ),
        ],
        breachCounts: const {'azerty': 900000},
      );
      final health = report.analysed.single;
      expect(health.issues, containsAll([HealthIssue.breached, HealthIssue.weak]));
      expect(health.primaryIssue, HealthIssue.breached);
    });

    test('une fuite pèse plus lourd qu’un mot de passe faible sur le score', () {
      final faible = VaultHealth.analyse([
        const CipherItem(id: 'x', data: LoginData(name: 'F', password: 'azerty')),
      ]);
      final expose = VaultHealth.analyse(
        [
          const CipherItem(
            id: 'y',
            data: LoginData(name: 'E', password: 'Kx7mQ2vB9nTz4wLp!Rt'),
          ),
        ],
        breachCounts: const {'Kx7mQ2vB9nTz4wLp!Rt': 5},
      );
      expect(expose.score, lessThan(faible.score));
    });

    test('le résumé mentionne les exposés en premier', () {
      final report = VaultHealth.analyse(
        items,
        breachCounts: const {'MotDePasseFuite2026!': 12},
      );
      expect(report.summaryLine, startsWith('1 exposé'));
    });
  });
}

/// Exception d'exemple, pour simuler une panne réseau sans dépendre de dart:io.
class HttpExceptionStub implements Exception {
  const HttpExceptionStub();
  @override
  String toString() => 'réseau injoignable';
}
