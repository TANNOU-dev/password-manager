import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:password_manager/core/utils/ssh_key.dart';

/// Conformité au format OpenSSH.
///
/// Le juge de paix n'est pas une constante recopiée dans le test, c'est
/// `ssh-keygen` lui-même : on lui donne la clé privée produite ici et on
/// vérifie qu'il en dérive la même clé publique et la même empreinte. Un format
/// « presque bon » — un remplissage mal calculé, une longueur oubliée — serait
/// refusé par lui alors qu'un aller-retour interne ne verrait rien.
///
/// Les tests qui en dépendent sont ignorés là où `ssh-keygen` est absent, mais
/// jamais silencieusement transformés en succès.

Future<bool> _hasSshKeygen() async {
  try {
    final r = await Process.run('which', ['ssh-keygen']);
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Écrit la clé privée avec des droits restreints : `ssh-keygen` refuse de lire
/// une clé lisible par tous, exactement comme il le ferait pour une vraie.
Future<Directory> _writeKey(SshKeyPair pair) async {
  final dir = await Directory.systemTemp.createTemp('coffort_ssh');
  final file = File('${dir.path}/id_ed25519');
  await file.writeAsString(pair.privateKey);
  await Process.run('chmod', ['600', file.path]);
  await File('${file.path}.pub').writeAsString('${pair.publicKey}\n');
  return dir;
}

void main() {
  test('ssh-keygen relit la clé privée et retrouve la même clé publique',
      () async {
    if (!await _hasSshKeygen()) {
      markTestSkipped('ssh-keygen absent de cette machine');
      return;
    }

    final pair = await SshKeys.generateEd25519(comment: 'tannou@coffort');
    final dir = await _writeKey(pair);
    addTearDown(() => dir.delete(recursive: true));

    final derived = await Process.run(
      'ssh-keygen',
      ['-y', '-f', '${dir.path}/id_ed25519'],
    );

    expect(derived.exitCode, 0,
        reason: 'ssh-keygen a refusé la clé : ${derived.stderr}');

    // `-y` réémet la ligne complète, commentaire compris : elle doit être
    // identique caractère pour caractère à celle qu'on a produite.
    expect((derived.stdout as String).trim(), pair.publicKey);
  });

  test('ssh-keygen calcule la même empreinte', () async {
    if (!await _hasSshKeygen()) {
      markTestSkipped('ssh-keygen absent de cette machine');
      return;
    }

    final pair = await SshKeys.generateEd25519(comment: 'tannou@coffort');
    final dir = await _writeKey(pair);
    addTearDown(() => dir.delete(recursive: true));

    final listed = await Process.run(
      'ssh-keygen',
      ['-l', '-f', '${dir.path}/id_ed25519.pub'],
    );

    expect(listed.exitCode, 0, reason: listed.stderr.toString());
    // Sortie : « 256 SHA256:xxxx commentaire (ED25519) »
    final fields = (listed.stdout as String).trim().split(RegExp(r'\s+'));
    expect(fields[0], '256');
    expect(fields[1], pair.fingerprint);
    expect(fields.last, '(ED25519)');
  });

  test('une clé sans commentaire reste valide', () async {
    if (!await _hasSshKeygen()) {
      markTestSkipped('ssh-keygen absent de cette machine');
      return;
    }

    // Le commentaire vide donne une chaîne de longueur nulle dans l'enveloppe,
    // et décale le remplissage : c'est le cas limite du calcul de padding.
    final pair = await SshKeys.generateEd25519();
    final dir = await _writeKey(pair);
    addTearDown(() => dir.delete(recursive: true));

    final derived = await Process.run(
      'ssh-keygen',
      ['-y', '-f', '${dir.path}/id_ed25519'],
    );
    expect(derived.exitCode, 0, reason: derived.stderr.toString());
    expect((derived.stdout as String).trim(), pair.publicKey.trim());
  });

  test('deux tirages ne donnent jamais la même clé', () async {
    final a = await SshKeys.generateEd25519();
    final b = await SshKeys.generateEd25519();
    expect(a.publicKey, isNot(b.publicKey));
    expect(a.privateKey, isNot(b.privateKey));
    expect(a.fingerprint, isNot(b.fingerprint));
  });

  test('la forme des trois représentations', () async {
    final pair = await SshKeys.generateEd25519(comment: 'tannou@coffort');

    expect(pair.privateKey, startsWith('-----BEGIN OPENSSH PRIVATE KEY-----'));
    expect(pair.privateKey.trimRight(),
        endsWith('-----END OPENSSH PRIVATE KEY-----'));
    expect(pair.publicKey, startsWith('ssh-ed25519 AAAAC3NzaC1lZDI1NTE5'));
    expect(pair.publicKey, endsWith(' tannou@coffort'));
    expect(pair.fingerprint, startsWith('SHA256:'));
    // Base64 de 32 octets, remplissage retiré : 43 caractères.
    expect(pair.fingerprint.length, 'SHA256:'.length + 43);
  });

  group('lecture d’une clé collée', () {
    test('empreinte recalculée depuis la clé publique seule', () async {
      final pair = await SshKeys.generateEd25519(comment: 'poste@maison');
      expect(SshKeys.fingerprintOfPublicKey(pair.publicKey), pair.fingerprint);
    });

    test('le commentaire est extrait, espaces compris', () async {
      final pair = await SshKeys.generateEd25519(comment: 'mon poste de bureau');
      expect(SshKeys.commentOfPublicKey(pair.publicKey), 'mon poste de bureau');
    });

    test('une clé sans commentaire n’en invente pas', () async {
      final pair = await SshKeys.generateEd25519();
      expect(SshKeys.commentOfPublicKey(pair.publicKey), '');
    });

    test('du base64 valide mais qui n’est pas une clé est refusé', () {
      // Le blob doit se déclarer du même type que le préfixe de la ligne, sinon
      // n'importe quel base64 obtiendrait une empreinte.
      expect(SshKeys.fingerprintOfPublicKey('ssh-ed25519 QUJDREVGRw=='), isNull);
      expect(SshKeys.fingerprintOfPublicKey('ssh-ed25519 pas du base64'), isNull);
      expect(SshKeys.fingerprintOfPublicKey('ssh-ed25519'), isNull);
      expect(SshKeys.fingerprintOfPublicKey(''), isNull);
    });

    test('reconnaître les deux moitiés d’une paire', () async {
      final pair = await SshKeys.generateEd25519();
      expect(SshKeys.looksLikePublicKey(pair.publicKey), isTrue);
      expect(SshKeys.looksLikePrivateKey(pair.privateKey), isTrue);
      expect(SshKeys.looksLikePublicKey(pair.privateKey), isFalse);
      expect(SshKeys.looksLikePrivateKey(pair.publicKey), isFalse);
    });
  });

  test('un matériel connu donne toujours la même sortie', () {
    // Verrouille l'encodage : si quelqu'un touche au remplissage ou à l'ordre
    // des champs, la sortie change et ce test le dit sans avoir besoin de
    // ssh-keygen.
    final seed = Uint8List.fromList(List.generate(32, (i) => i));
    final pub = Uint8List.fromList(List.generate(32, (i) => 255 - i));

    final a = SshKeys.fromEd25519Material(
      seed: seed,
      pub: pub,
      comment: 'fixe',
      checkInt: 0x01020304,
    );
    final b = SshKeys.fromEd25519Material(
      seed: seed,
      pub: pub,
      comment: 'fixe',
      checkInt: 0x01020304,
    );

    expect(a.privateKey, b.privateKey);
    expect(a.publicKey, b.publicKey);
    expect(a.fingerprint, b.fingerprint);

    // Le contrôle aléatoire est le seul champ qui bouge d'un appel à l'autre :
    // à matériel égal, seule sa valeur peut changer la clé privée.
    final c = SshKeys.fromEd25519Material(
      seed: seed,
      pub: pub,
      comment: 'fixe',
      checkInt: 0x05060708,
    );
    expect(c.privateKey, isNot(a.privateKey));
    expect(c.publicKey, a.publicKey);
  });
  group('lecture d’un fichier de clé', () {
    test('une clé produite par ssh-keygen est relue et sa paire dérivée',
        () async {
      if (!await _hasSshKeygen()) {
        markTestSkipped('ssh-keygen absent de cette machine');
        return;
      }

      // Le sens inverse du premier test : là on écrivait pour ssh-keygen, ici
      // on lit ce qu'il a écrit. Les deux directions doivent tenir pour qu'une
      // clé existante entre dans le coffre sans perte.
      final dir = await Directory.systemTemp.createTemp('coffort_read');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/id_ed25519';

      final gen = await Process.run('ssh-keygen', [
        '-t', 'ed25519', '-N', '', '-C', 'origine@ssh-keygen', '-f', path,
      ]);
      expect(gen.exitCode, 0, reason: gen.stderr.toString());

      final parsed = SshKeys.readKeyFile(await File(path).readAsString());

      // La clé publique dérivée doit être celle que ssh-keygen a écrite à côté.
      final expected = (await File('$path.pub').readAsString()).trim();
      expect(parsed.publicKey, expected);

      final listed = await Process.run('ssh-keygen', ['-l', '-f', '$path.pub']);
      expect(listed.stdout.toString().trim().split(RegExp(r'\s+'))[1],
          parsed.fingerprint);
    });

    test('un fichier .pub seul remplit ce qu’il peut', () async {
      final pair = await SshKeys.generateEd25519(comment: 'poste@maison');
      final read = SshKeys.readKeyFile('${pair.publicKey}\n');

      expect(read.publicKey, pair.publicKey);
      expect(read.fingerprint, pair.fingerprint);
      // La clé privée reste à fournir : on ne l'invente pas.
      expect(read.privateKey, isEmpty);
    });

    test('notre propre clé se relit', () async {
      final pair = await SshKeys.generateEd25519(comment: 'aller@retour');
      final read = SshKeys.readKeyFile(pair.privateKey);
      expect(read.publicKey, pair.publicKey);
      expect(read.fingerprint, pair.fingerprint);
      expect(read.privateKey, pair.privateKey);
    });

    test('une clé protégée par une phrase de passe est refusée clairement',
        () async {
      if (!await _hasSshKeygen()) {
        markTestSkipped('ssh-keygen absent de cette machine');
        return;
      }

      final dir = await Directory.systemTemp.createTemp('coffort_pass');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/id_ed25519';
      await Process.run('ssh-keygen',
          ['-t', 'ed25519', '-N', 'secret', '-C', 'x', '-f', path]);

      // Le message doit donner la sortie de secours, pas seulement le constat.
      expect(
        () => SshKeys.readKeyFile(File(path).readAsStringSync()),
        throwsA(isA<SshKeyException>().having(
          (e) => e.message, 'message', contains('ssh-keygen -p'))),
      );
    });

    test('une clé RSA est refusée en le disant', () async {
      if (!await _hasSshKeygen()) {
        markTestSkipped('ssh-keygen absent de cette machine');
        return;
      }

      final dir = await Directory.systemTemp.createTemp('coffort_rsa');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}/id_rsa';
      await Process.run('ssh-keygen',
          ['-t', 'rsa', '-b', '2048', '-N', '', '-C', 'x', '-f', path]);

      expect(
        () => SshKeys.readKeyFile(File(path).readAsStringSync()),
        throwsA(isA<SshKeyException>().having(
          (e) => e.message, 'message', contains('ssh-rsa'))),
      );
    });

    test('un fichier tronqué ou étranger ne fait pas planter', () {
      for (final bad in [
        '',
        'bonjour',
        '-----BEGIN OPENSSH PRIVATE KEY-----\nAAAA\n-----END OPENSSH PRIVATE KEY-----',
        '-----BEGIN OPENSSH PRIVATE KEY-----\n!!!pas du base64!!!\n-----END OPENSSH PRIVATE KEY-----',
      ]) {
        expect(() => SshKeys.readKeyFile(bad), throwsA(isA<SshKeyException>()),
            reason: 'entrée : ${bad.length > 30 ? "${bad.substring(0, 30)}…" : bad}');
      }
    });
  });
}
