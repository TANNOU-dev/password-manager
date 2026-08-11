import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';

import 'package:password_manager/core/crypto/enc_string.dart';
import 'package:password_manager/core/crypto/kdf_params.dart';
import 'package:password_manager/core/crypto/vault_crypto.dart';

// Paramètres volontairement faibles : ces tests valident la mécanique, pas le
// coût de la dérivation. Le coût réel est mesuré par tool/bench_kdf.dart.
const fastKdf = KdfParams(
  type: KdfType.argon2id,
  iterations: 1,
  memory: 8192,
  parallelism: 1,
);

const saltA = '0123456789abcdef0123456789abcdef';
const saltB = 'fedcba9876543210fedcba9876543210';

void main() {
  final crypto = VaultCrypto();

  Future<MasterKeyMaterial> derive(String password, {String salt = saltA}) {
    return crypto.deriveMasterKeyMaterial(
      masterPassword: password,
      kdfSaltHex: salt,
      params: fastKdf,
    );
  }

  group('EncString', () {
    test('sérialise et reparse sans perte', () {
      final original = EncString.v1(
        nonce: Uint8List.fromList(List.generate(12, (i) => i)),
        cipherText: Uint8List.fromList([9, 8, 7, 6, 5]),
        mac: Uint8List.fromList(List.generate(16, (i) => 200 - i)),
      );
      final parsed = EncString.parse(original.serialize());

      expect(parsed.version, '1');
      expect(parsed.nonce, original.nonce);
      expect(parsed.cipherText, original.cipherText);
      expect(parsed.mac, original.mac);
    });

    test('refuse une version inconnue', () {
      expect(
        () => EncString.parse('7.${base64.encode(List.filled(40, 0))}'),
        throwsA(isA<EncStringFormatException>()),
      );
    });

    test('refuse une charge utile trop courte pour un nonce et un MAC', () {
      expect(
        () => EncString.parse('1.${base64.encode(List.filled(20, 0))}'),
        throwsA(isA<EncStringFormatException>()),
      );
    });

    test('refuse du base64 invalide', () {
      expect(
        () => EncString.parse('1.pas du base64 !'),
        throwsA(isA<EncStringFormatException>()),
      );
    });

    test('reconnaît une chaîne restée en clair', () {
      expect(EncString.looksEncrypted('hunter2'), isFalse);
      expect(EncString.looksEncrypted(''), isFalse);
      expect(EncString.looksEncrypted(null), isFalse);
    });
  });

  group('dérivation de la clé maître', () {
    test('le masterPasswordHash a la forme attendue par le serveur', () async {
      final material = await derive('un-mot-de-passe-maitre');
      // Le serveur valide exactement 44 caractères de base64 : 32 octets.
      expect(material.masterPasswordHash.length, 44);
      expect(base64.decode(material.masterPasswordHash).length, 32);
      material.destroy();
    });

    test('est déterministe à mot de passe et sel constants', () async {
      final a = await derive('meme-mot-de-passe');
      final b = await derive('meme-mot-de-passe');
      expect(a.masterPasswordHash, b.masterPasswordHash);
      expect(a.wrapKey.bytes, b.wrapKey.bytes);
      a.destroy();
      b.destroy();
    });

    test('un sel différent donne une clé différente', () async {
      final a = await derive('meme-mot-de-passe', salt: saltA);
      final b = await derive('meme-mot-de-passe', salt: saltB);
      expect(a.masterPasswordHash, isNot(b.masterPasswordHash));
      expect(a.wrapKey.bytes, isNot(b.wrapKey.bytes));
      a.destroy();
      b.destroy();
    });

    test('la clé d’enveloppe et le hash d’authentification sont disjoints',
        () async {
      // C'est cette séparation qui rend l'envoi du hash au serveur inoffensif.
      final material = await derive('un-mot-de-passe-maitre');
      expect(base64.encode(material.wrapKey.bytes),
          isNot(material.masterPasswordHash));
      material.destroy();
    });

    test('effacer le matériel de clé rend la clé inaccessible', () async {
      final material = await derive('un-mot-de-passe-maitre');
      material.destroy();
      expect(material.wrapKey.hasBeenDestroyed, isTrue);
      expect(() => material.wrapKey.bytes, throwsStateError);
    });
  });

  group('enveloppe de la clé de coffre', () {
    test('aller-retour', () async {
      final material = await derive('correct-horse-battery-staple');
      final vaultKey = await crypto.newVaultKey();
      final protectedKey = await crypto.wrapVaultKey(
        vaultKey: vaultKey,
        wrapKey: material.wrapKey,
      );

      expect(protectedKey.startsWith('1.'), isTrue);

      final reopened = await crypto.unwrapVaultKey(
        protectedKey: protectedKey,
        wrapKey: material.wrapKey,
      );
      expect(reopened.key.bytes, vaultKey.key.bytes);
    });

    test('un mauvais mot de passe maître ne déballe rien', () async {
      final good = await derive('le-bon');
      final vaultKey = await crypto.newVaultKey();
      final protectedKey = await crypto.wrapVaultKey(
        vaultKey: vaultKey,
        wrapKey: good.wrapKey,
      );

      final bad = await derive('le-mauvais');
      await expectLater(
        crypto.unwrapVaultKey(protectedKey: protectedKey, wrapKey: bad.wrapKey),
        throwsA(isA<WrongMasterPasswordException>()),
      );
    });

    test('une clé enveloppée altérée est rejetée, pas acceptée à moitié',
        () async {
      final material = await derive('le-bon');
      final vaultKey = await crypto.newVaultKey();
      final protectedKey = await crypto.wrapVaultKey(
        vaultKey: vaultKey,
        wrapKey: material.wrapKey,
      );

      // On retourne un bit du chiffré.
      final parsed = EncString.parse(protectedKey);
      final tampered = Uint8List.fromList(parsed.cipherText);
      tampered[0] ^= 0x01;
      final forged = EncString.v1(
        nonce: parsed.nonce,
        cipherText: tampered,
        mac: parsed.mac,
      ).serialize();

      await expectLater(
        crypto.unwrapVaultKey(
          protectedKey: forged,
          wrapKey: material.wrapKey,
        ),
        throwsA(isA<WrongMasterPasswordException>()),
      );
    });
  });

  group('chiffrement du contenu', () {
    test('aller-retour sur une chaîne', () async {
      final vaultKey = await crypto.newVaultKey();
      const secret = 'hunter2 — avec des accents, des émojis 🔐 et des \n sauts';
      final encrypted = await crypto.encryptString(secret, vaultKey);

      expect(encrypted, isNot(contains('hunter2')));
      expect(await crypto.decryptString(encrypted, vaultKey), secret);
    });

    test('aller-retour sur un objet JSON', () async {
      final vaultKey = await crypto.newVaultKey();
      final item = {
        'name': 'GitHub',
        'username': 'tannou',
        'password': 'hunter2',
        'uris': ['https://github.com', 'https://gist.github.com'],
        'totp': 'JBSWY3DPEHPK3PXP',
        'fields': [
          {'name': 'code de secours', 'value': '123456', 'type': 1}
        ],
      };
      final encrypted = await crypto.encryptJson(item, vaultKey);
      expect(await crypto.decryptJson(encrypted, vaultKey), item);
    });

    test('deux chiffrements du même clair donnent deux chiffrés différents',
        () async {
      // Sinon un observateur du serveur repérerait les mots de passe réutilisés
      // en comparant simplement les blobs.
      final vaultKey = await crypto.newVaultKey();
      final a = await crypto.encryptString('identique', vaultKey);
      final b = await crypto.encryptString('identique', vaultKey);
      expect(a, isNot(b));
      expect(EncString.parse(a).nonce, isNot(EncString.parse(b).nonce));
    });

    test('un chiffré altéré est rejeté', () async {
      final vaultKey = await crypto.newVaultKey();
      final encrypted = await crypto.encryptString('intact', vaultKey);
      final parsed = EncString.parse(encrypted);
      final tampered = Uint8List.fromList(parsed.cipherText);
      tampered[0] ^= 0xFF;

      await expectLater(
        crypto.decryptString(
          EncString.v1(
            nonce: parsed.nonce,
            cipherText: tampered,
            mac: parsed.mac,
          ).serialize(),
          vaultKey,
        ),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });

    test('une autre clé de coffre ne déchiffre pas', () async {
      final mine = await crypto.newVaultKey();
      final other = await crypto.newVaultKey();
      final encrypted = await crypto.encryptString('mon secret', mine);

      await expectLater(
        crypto.decryptString(encrypted, other),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });

  group('changement de mot de passe maître', () {
    test('réenveloppe la clé sans rendre le coffre illisible', () async {
      // Le scénario qui doit absolument marcher : changer de mot de passe maître
      // ne rechiffre aucun élément, donc les anciens blobs doivent rester
      // lisibles avec la clé de coffre déballée par le nouveau mot de passe.
      final oldMaterial = await derive('ancien-mot-de-passe');
      final vaultKey = await crypto.newVaultKey();
      final protectedKey = await crypto.wrapVaultKey(
        vaultKey: vaultKey,
        wrapKey: oldMaterial.wrapKey,
      );

      final item = await crypto.encryptString('secret écrit avant', vaultKey);

      // Changement : on déballe avec l'ancien, on réenveloppe avec le nouveau.
      final unwrapped = await crypto.unwrapVaultKey(
        protectedKey: protectedKey,
        wrapKey: oldMaterial.wrapKey,
      );
      final newMaterial = await derive('nouveau-mot-de-passe');
      final newProtectedKey = await crypto.wrapVaultKey(
        vaultKey: unwrapped,
        wrapKey: newMaterial.wrapKey,
      );

      // Après changement, le nouveau mot de passe ouvre l'ancien contenu.
      final afterChange = await crypto.unwrapVaultKey(
        protectedKey: newProtectedKey,
        wrapKey: newMaterial.wrapKey,
      );
      expect(await crypto.decryptString(item, afterChange), 'secret écrit avant');

      // Et l'ancien mot de passe n'ouvre plus rien.
      await expectLater(
        crypto.unwrapVaultKey(
          protectedKey: newProtectedKey,
          wrapKey: oldMaterial.wrapKey,
        ),
        throwsA(isA<WrongMasterPasswordException>()),
      );
    });
  });
}
