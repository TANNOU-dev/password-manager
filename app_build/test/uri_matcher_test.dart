import 'package:flutter_test/flutter_test.dart';

import 'package:password_manager/data/models/cipher.dart';
import 'package:password_manager/features/autofill/uri_matcher.dart';

/// Le remplissage automatique se trompe dans deux directions, et la seconde est
/// dangereuse : proposer les identifiants d'une banque sur un site d'hameçonnage.
/// Ces tests couvrent les deux.

CipherItem login(
  String name,
  List<LoginUri> uris, {
  bool favorite = false,
  String username = 'u',
}) =>
    CipherItem(
      id: name,
      favorite: favorite,
      data: LoginData(
        name: name,
        username: username,
        password: 'p',
        uris: uris,
      ),
    );

void main() {
  group('extraction de l’hôte', () {
    test('tolère l’absence de schéma', () {
      expect(UriMatcher.hostOf('github.com'), 'github.com');
      expect(UriMatcher.hostOf('https://github.com'), 'github.com');
      expect(UriMatcher.hostOf('https://github.com/login?x=1'), 'github.com');
    });

    test('retire le www', () {
      expect(UriMatcher.hostOf('https://www.github.com'), 'github.com');
    });

    test('reconnaît un identifiant de paquet Android', () {
      expect(
        UriMatcher.hostOf('androidapp://com.exemple.app'),
        'com.exemple.app',
      );
    });

    test('rend null sur une chaîne vide', () {
      expect(UriMatcher.hostOf('   '), isNull);
    });
  });

  group('domaine de base', () {
    test('réduit un sous-domaine', () {
      expect(UriMatcher.baseDomain('mail.google.com'), 'google.com');
      expect(UriMatcher.baseDomain('https://a.b.c.exemple.com'), 'exemple.com');
    });

    test('garde un domaine déjà minimal', () {
      expect(UriMatcher.baseDomain('github.com'), 'github.com');
    });

    test('gère les suffixes à deux niveaux', () {
      // Sans cette gestion, exemple.co.uk se réduirait à co.uk et *tous* les
      // sites britanniques correspondraient entre eux.
      expect(UriMatcher.baseDomain('boutique.exemple.co.uk'), 'exemple.co.uk');
      expect(UriMatcher.baseDomain('exemple.co.uk'), 'exemple.co.uk');
    });

    test('gère les suffixes ivoiriens', () {
      expect(UriMatcher.baseDomain('www.ecobank.co.ci'), 'ecobank.co.ci');
      expect(UriMatcher.baseDomain('mon.compte.orange.ci'), 'orange.ci');
      expect(UriMatcher.baseDomain('site.impots.gouv.ci'), 'impots.gouv.ci');
    });

    test('laisse une adresse IP intacte', () {
      expect(UriMatcher.baseDomain('http://192.168.1.10:8080'), '192.168.1.10');
    });
  });

  group('correspondance par domaine (défaut)', () {
    test('accepte un sous-domaine du même site', () {
      expect(
        UriMatcher.matches(
          stored: const LoginUri(uri: 'https://github.com'),
          requested: 'https://gist.github.com/login',
        ),
        isTrue,
      );
    });

    test('accepte le www', () {
      expect(
        UriMatcher.matches(
          stored: const LoginUri(uri: 'github.com'),
          requested: 'https://www.github.com',
        ),
        isTrue,
      );
    });

    test('refuse un domaine d’hameçonnage qui contient le vrai', () {
      // Le cas qui compte. Une comparaison par `contains` accepterait ceci.
      expect(
        UriMatcher.matches(
          stored: const LoginUri(uri: 'https://mabanque.ci'),
          requested: 'https://mabanque.ci.attaquant.example/login',
        ),
        isFalse,
      );
    });

    test('refuse un site qui commence pareil', () {
      expect(
        UriMatcher.matches(
          stored: const LoginUri(uri: 'https://orange.ci'),
          requested: 'https://orange-ci.example',
        ),
        isFalse,
      );
    });

    test('refuse deux sites différents sous le même suffixe', () {
      expect(
        UriMatcher.matches(
          stored: const LoginUri(uri: 'https://a.co.uk'),
          requested: 'https://b.co.uk',
        ),
        isFalse,
      );
    });
  });

  group('autres règles de correspondance', () {
    test('hôte exact refuse un sous-domaine', () {
      expect(
        UriMatcher.matches(
          stored: const LoginUri(
            uri: 'https://mail.google.com',
            match: UriMatchType.host,
          ),
          requested: 'https://drive.google.com',
        ),
        isFalse,
      );
      expect(
        UriMatcher.matches(
          stored: const LoginUri(
            uri: 'https://mail.google.com',
            match: UriMatchType.host,
          ),
          requested: 'https://mail.google.com/inbox',
        ),
        isTrue,
      );
    });

    test('URL exacte exige l’égalité stricte', () {
      const stored = LoginUri(
        uri: 'https://exemple.com/login',
        match: UriMatchType.exact,
      );
      expect(
        UriMatcher.matches(stored: stored, requested: 'https://exemple.com/login'),
        isTrue,
      );
      expect(
        UriMatcher.matches(stored: stored, requested: 'https://exemple.com/autre'),
        isFalse,
      );
    });

    test('« commence par » suit son préfixe', () {
      const stored = LoginUri(
        uri: 'https://exemple.com/app',
        match: UriMatchType.startsWith,
      );
      expect(
        UriMatcher.matches(
            stored: stored, requested: 'https://exemple.com/app/page'),
        isTrue,
      );
      expect(
        UriMatcher.matches(
            stored: stored, requested: 'https://exemple.com/autre'),
        isFalse,
      );
    });

    test('« jamais » ne correspond à rien', () {
      expect(
        UriMatcher.matches(
          stored: const LoginUri(
            uri: 'https://exemple.com',
            match: UriMatchType.never,
          ),
          requested: 'https://exemple.com',
        ),
        isFalse,
      );
    });
  });

  group('applications Android', () {
    test('un paquet correspond à lui-même', () {
      expect(
        UriMatcher.matches(
          stored: const LoginUri(uri: 'androidapp://com.exemple.app'),
          requested: 'androidapp://com.exemple.app',
        ),
        isTrue,
      );
    });

    test('deux paquets différents ne correspondent pas', () {
      expect(
        UriMatcher.matches(
          stored: const LoginUri(uri: 'androidapp://com.exemple.app'),
          requested: 'androidapp://com.exemple.autre',
        ),
        isFalse,
      );
    });

    test('un paquet ne correspond pas à un site, ni l’inverse', () {
      // Un nom de paquet ressemble à un domaine inversé : sans ce garde-fou,
      // « com.exemple.app » pourrait correspondre à « exemple.com ».
      expect(
        UriMatcher.matches(
          stored: const LoginUri(uri: 'androidapp://com.exemple.app'),
          requested: 'https://exemple.com',
        ),
        isFalse,
      );
      expect(
        UriMatcher.matches(
          stored: const LoginUri(uri: 'https://exemple.com'),
          requested: 'androidapp://com.exemple.app',
        ),
        isFalse,
      );
    });

    test('un préfixe de paquet ne suffit pas', () {
      expect(
        UriMatcher.matches(
          stored: const LoginUri(uri: 'androidapp://com.exemple'),
          requested: 'androidapp://com.exemple.malveillant',
        ),
        isFalse,
      );
    });
  });

  group('sélection des candidats', () {
    final vault = [
      login('GitHub générique', const [LoginUri(uri: 'https://github.com')]),
      login('GitHub Gist', const [
        LoginUri(uri: 'https://gist.github.com', match: UriMatchType.host),
      ]),
      login('Orange', const [LoginUri(uri: 'https://orange.ci')]),
      login('Sans adresse', const []),
      login('App native', const [LoginUri(uri: 'androidapp://com.orange.app')]),
      login('Favori GitHub', const [LoginUri(uri: 'https://github.com')],
          favorite: true),
    ];

    test('ne retient que ce qui correspond', () {
      final found = UriMatcher.candidatesFor(vault, 'https://orange.ci/login');
      expect(found.map((i) => i.data.name), ['Orange']);
    });

    test('place l’hôte exact avant le domaine générique', () {
      final found =
          UriMatcher.candidatesFor(vault, 'https://gist.github.com/x');
      expect(found.first.data.name, 'GitHub Gist');
      expect(found.map((i) => i.data.name), contains('Favori GitHub'));
    });

    test('à score égal, le favori passe devant', () {
      final found = UriMatcher.candidatesFor(vault, 'https://github.com/login');
      expect(found.first.data.name, 'Favori GitHub');
    });

    test('trouve aussi par nom de paquet', () {
      final found = UriMatcher.candidatesFor(
        vault,
        '',
        packageName: 'com.orange.app',
      );
      expect(found.map((i) => i.data.name), ['App native']);
    });

    test('écarte les éléments sans adresse', () {
      final found = UriMatcher.candidatesFor(vault, 'https://github.com');
      expect(found.map((i) => i.data.name), isNot(contains('Sans adresse')));
    });

    test('ne propose rien pour un site inconnu', () {
      expect(
        UriMatcher.candidatesFor(vault, 'https://inconnu.example'),
        isEmpty,
      );
    });

    test('ignore les types autres qu’identifiant', () {
      final withCard = [
        ...vault,
        const CipherItem(
          id: 'carte',
          data: CardData(name: 'Carte', number: '4111111111111111'),
        ),
      ];
      final found = UriMatcher.candidatesFor(withCard, 'https://github.com');
      expect(found.every((i) => i.data is LoginData), isTrue);
    });
  });
}
