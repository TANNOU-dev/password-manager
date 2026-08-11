import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import 'enc_string.dart';
import 'kdf_params.dart';

/// Hiérarchie de clés.
///
///   mot de passe maître
///        │  Argon2id(sel servi par le serveur)
///        ▼
///   clé maître (32 o) ── ne quitte jamais l'appareil
///        │
///        ├─ HKDF info="passvault:wrap:v1" ──▶ clé d'enveloppe
///        │        déballe protectedKey ──▶ clé de coffre
///        │                                      │
///        │                                      ▼
///        │                            chiffre chaque élément (AES-256-GCM)
///        │
///        └─ HKDF info="passvault:auth:v1" ──▶ masterPasswordHash
///                 seule valeur envoyée au serveur
///
/// La séparation de domaines par `info` est ce qui rend l'envoi du
/// masterPasswordHash sans danger : il est calculatoirement inutilisable pour
/// remonter à la clé d'enveloppe.
///
/// La clé de coffre est tirée une fois à la création et ne change jamais. Un
/// changement de mot de passe maître se contente de la réenvelopper, ce qui rend
/// l'opération instantanée quelle que soit la taille du coffre.

const String _wrapInfo = 'passvault:wrap:v1';
const String _authInfo = 'passvault:auth:v1';

/// Argon2id n'est pas accéléré nativement : sur mobile la dérivation prend
/// facilement une à trois secondes. On la sort donc du thread d'interface.
/// `compute` retombe sur une exécution en ligne sur le web, où les isolats
/// n'existent pas.
class _Argon2Request {
  final String password;
  final Uint8List salt;
  final int memory;
  final int iterations;
  final int parallelism;

  const _Argon2Request({
    required this.password,
    required this.salt,
    required this.memory,
    required this.iterations,
    required this.parallelism,
  });
}

Future<Uint8List> _deriveArgon2id(_Argon2Request req) async {
  final kdf = Argon2id(
    memory: req.memory,
    iterations: req.iterations,
    parallelism: req.parallelism,
    hashLength: 32,
  );
  final key = await kdf.deriveKeyFromPassword(
    password: req.password,
    nonce: req.salt,
  );
  return Uint8List.fromList(await key.extractBytes());
}

class _Pbkdf2Request {
  final String password;
  final Uint8List salt;
  final int iterations;

  const _Pbkdf2Request({
    required this.password,
    required this.salt,
    required this.iterations,
  });
}

Future<Uint8List> _derivePbkdf2(_Pbkdf2Request req) async {
  final kdf = Pbkdf2.hmacSha256(iterations: req.iterations, bits: 256);
  final key = await kdf.deriveKeyFromPassword(
    password: req.password,
    nonce: req.salt,
  );
  return Uint8List.fromList(await key.extractBytes());
}

/// Ce qui est dérivé du mot de passe maître pour une session donnée.
class MasterKeyMaterial {
  /// Enveloppe et déballe la clé de coffre. Reste en mémoire tant que le coffre
  /// est déverrouillé.
  final SecretKeyData wrapKey;

  /// Seule valeur transmise au serveur pour prouver la connaissance du mot de
  /// passe maître.
  final String masterPasswordHash;

  MasterKeyMaterial({required this.wrapKey, required this.masterPasswordHash});

  void destroy() => wrapKey.destroy();
}

/// Clé symétrique du coffre. Chiffre le contenu de chaque élément.
class VaultKey {
  final SecretKeyData key;
  const VaultKey(this.key);

  void destroy() => key.destroy();
  bool get isDestroyed => key.hasBeenDestroyed;
}

/// Le mot de passe maître ne permet pas de déballer la clé de coffre : soit il
/// est faux, soit l'enregistrement est corrompu. Les deux cas sont
/// indistinguables, et c'est voulu — AES-GCM ne dit pas *pourquoi* il échoue.
class WrongMasterPasswordException implements Exception {
  const WrongMasterPasswordException();
  @override
  String toString() => 'WrongMasterPasswordException';
}

/// Un élément du coffre n'a pas pu être déchiffré alors que le coffre est
/// ouvert. Signale une donnée abîmée, pas une erreur d'authentification.
class VaultDataCorruptException implements Exception {
  final String detail;
  const VaultDataCorruptException(this.detail);
  @override
  String toString() => 'VaultDataCorruptException: $detail';
}

class VaultCrypto {
  VaultCrypto({AesGcm? cipher}) : _aes = cipher ?? AesGcm.with256bits();

  final AesGcm _aes;

  // ==================== DÉRIVATION ====================

  /// Rejoue le KDF à partir du mot de passe maître et du sel servi par le
  /// serveur, puis en tire les deux valeurs dérivées.
  Future<MasterKeyMaterial> deriveMasterKeyMaterial({
    required String masterPassword,
    required String kdfSaltHex,
    required KdfParams params,
  }) async {
    final salt = _hexToBytes(kdfSaltHex);

    final masterKeyBytes = switch (params.type) {
      KdfType.argon2id => await compute(
          _deriveArgon2id,
          _Argon2Request(
            password: masterPassword,
            salt: salt,
            memory: params.memory ?? KdfParams.argon2idDefault.memory!,
            iterations: params.iterations,
            parallelism: params.parallelism ?? 1,
          ),
        ),
      KdfType.pbkdf2 => await compute(
          _derivePbkdf2,
          _Pbkdf2Request(
            password: masterPassword,
            salt: salt,
            iterations: params.iterations,
          ),
        ),
    };

    final masterKey = SecretKeyData(masterKeyBytes, overwriteWhenDestroyed: true);
    try {
      final wrapKey = await _expand(masterKey, _wrapInfo);
      final authKey = await _expand(masterKey, _authInfo);
      final hash = base64.encode(authKey.bytes);
      authKey.destroy();
      return MasterKeyMaterial(wrapKey: wrapKey, masterPasswordHash: hash);
    } finally {
      // La clé maître elle-même n'a plus de raison de rester en mémoire : tout
      // ce dont on a besoin en découle.
      masterKey.destroy();
    }
  }

  Future<SecretKeyData> _expand(SecretKeyData masterKey, String info) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final derived = await hkdf.deriveKey(
      secretKey: masterKey,
      info: utf8.encode(info),
    );
    return SecretKeyData(
      Uint8List.fromList(derived.bytes),
      overwriteWhenDestroyed: true,
    );
  }

  // ==================== CLÉ DE COFFRE ====================

  /// Tire une clé de coffre neuve. Appelé une seule fois dans la vie du coffre.
  Future<VaultKey> newVaultKey() async {
    final key = await _aes.newSecretKey();
    return VaultKey(
      SecretKeyData(
        Uint8List.fromList(await key.extractBytes()),
        overwriteWhenDestroyed: true,
      ),
    );
  }

  Future<String> wrapVaultKey({
    required VaultKey vaultKey,
    required SecretKeyData wrapKey,
  }) async {
    return _encryptBytes(Uint8List.fromList(vaultKey.key.bytes), wrapKey);
  }

  Future<VaultKey> unwrapVaultKey({
    required String protectedKey,
    required SecretKeyData wrapKey,
  }) async {
    final Uint8List raw;
    try {
      raw = await _decryptBytes(protectedKey, wrapKey);
    } on SecretBoxAuthenticationError {
      throw const WrongMasterPasswordException();
    } on EncStringFormatException catch (e) {
      throw VaultDataCorruptException('clé de coffre illisible : ${e.message}');
    }
    if (raw.length != 32) {
      throw const VaultDataCorruptException(
        'la clé de coffre déballée ne fait pas 32 octets',
      );
    }
    return VaultKey(SecretKeyData(raw, overwriteWhenDestroyed: true));
  }

  // ==================== CONTENU ====================

  Future<String> encryptString(String plainText, VaultKey vaultKey) {
    return _encryptBytes(
      Uint8List.fromList(utf8.encode(plainText)),
      vaultKey.key,
    );
  }

  Future<String> decryptString(String encoded, VaultKey vaultKey) async {
    final bytes = await _decryptBytes(encoded, vaultKey.key);
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw const VaultDataCorruptException('contenu déchiffré non UTF-8');
    }
  }

  Future<String> encryptJson(Map<String, dynamic> value, VaultKey vaultKey) {
    return encryptString(jsonEncode(value), vaultKey);
  }

  Future<Map<String, dynamic>> decryptJson(
    String encoded,
    VaultKey vaultKey,
  ) async {
    final plain = await decryptString(encoded, vaultKey);
    try {
      final decoded = jsonDecode(plain);
      if (decoded is! Map<String, dynamic>) {
        throw const VaultDataCorruptException('objet JSON attendu');
      }
      return decoded;
    } on FormatException {
      throw const VaultDataCorruptException('contenu déchiffré non JSON');
    }
  }

  // ==================== CLÉ ARBITRAIRE ====================

  // Utilisées par l'export chiffré, qui protège son fichier avec une clé dérivée
  // d'une phrase de passe choisie à l'export — indépendante de la clé du coffre,
  // pour que la sauvegarde survive à un changement de mot de passe maître.

  Future<String> encryptStringWithKey(String plainText, SecretKeyData key) {
    return _encryptBytes(Uint8List.fromList(utf8.encode(plainText)), key);
  }

  Future<String> decryptStringWithKey(String encoded, SecretKeyData key) async {
    final Uint8List bytes;
    try {
      bytes = await _decryptBytes(encoded, key);
    } on SecretBoxAuthenticationError {
      // Même traitement que pour la clé du coffre : AES-GCM ne dit pas si c'est
      // la clé qui est fausse ou le contenu qui est abîmé.
      throw const WrongMasterPasswordException();
    }
    try {
      return utf8.decode(bytes);
    } on FormatException {
      throw const VaultDataCorruptException('contenu déchiffré non UTF-8');
    }
  }

  /// Octets aléatoires cryptographiquement sûrs. Passe par la même source que
  /// les clés du coffre.
  static Uint8List randomBytes(int length) {
    final random = SecretKeyData.random(length: length);
    return Uint8List.fromList(random.bytes);
  }

  // ==================== PRIMITIVES ====================

  Future<String> _encryptBytes(Uint8List plain, SecretKeyData key) async {
    // Nonce tiré par la bibliothèque à chaque appel. Ne jamais le réutiliser :
    // en GCM, deux messages sous le même couple (clé, nonce) livrent la clé
    // d'authentification.
    final box = await _aes.encrypt(plain, secretKey: key);
    return EncString.v1(
      nonce: Uint8List.fromList(box.nonce),
      cipherText: Uint8List.fromList(box.cipherText),
      mac: Uint8List.fromList(box.mac.bytes),
    ).serialize();
  }

  Future<Uint8List> _decryptBytes(String encoded, SecretKeyData key) async {
    final parsed = EncString.parse(encoded);
    final box = SecretBox(
      parsed.cipherText,
      nonce: parsed.nonce,
      mac: Mac(parsed.mac),
    );
    final plain = await _aes.decrypt(box, secretKey: key);
    return Uint8List.fromList(plain);
  }

  static Uint8List _hexToBytes(String hex) {
    if (hex.length.isOdd) {
      throw ArgumentError('sel hexadécimal de longueur impaire');
    }
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      final byte = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      if (byte == null) throw ArgumentError('sel hexadécimal invalide');
      out[i] = byte;
    }
    return out;
  }
}
