import 'dart:convert';

import '../../core/crypto/kdf_params.dart';
import '../../core/crypto/vault_crypto.dart';
import '../models/cipher.dart';

/// Export du coffre.
///
/// Deux sorties, et la distinction est le point important :
///
/// * **chiffré** — protégé par une phrase de passe choisie à l'export, avec sa
///   propre dérivation Argon2id. C'est la sauvegarde à conserver. Elle ne dépend
///   pas du mot de passe maître, ce qui permet de la restaurer même après un
///   changement de mot de passe.
/// * **en clair** — lisible par n'importe qui. Utile pour migrer vers un autre
///   gestionnaire, et rien d'autre. L'interface le dit explicitement.
///
/// L'export en clair adopte le **format Bitwarden** plutôt qu'un format maison :
/// il se relit avec `BitwardenImporter`, et il s'importe tel quel dans Bitwarden.
/// Un format propriétaire n'aurait servi personne.
abstract final class VaultExporter {
  /// JSON non chiffré, au format d'export Bitwarden.
  ///
  /// `folderNames` associe l'identifiant de dossier à son nom déchiffré.
  static String toBitwardenJson(
    List<CipherItem> items, {
    Map<String, String> folderNames = const {},
  }) {
    // Bitwarden référence les dossiers par identifiant : on ne réexporte que
    // ceux réellement utilisés.
    final usedIds = items
        .map((i) => i.folderId)
        .whereType<String>()
        .toSet()
        .where(folderNames.containsKey)
        .toList();

    return const JsonEncoder.withIndent('  ').convert({
      'encrypted': false,
      'folders': [
        for (final id in usedIds) {'id': id, 'name': folderNames[id]},
      ],
      'items': [for (final item in items) _itemToJson(item)],
    });
  }

  /// CSV à plat. Perd les types autres qu'identifiant, les champs personnalisés
  /// et l'historique — c'est inhérent au format, et l'interface l'annonce.
  static String toCsv(
    List<CipherItem> items, {
    Map<String, String> folderNames = const {},
  }) {
    final rows = StringBuffer()
      ..writeln('folder,name,url,username,password,totp,notes,favorite');

    for (final item in items) {
      final data = item.data;
      final folder = folderNames[item.folderId] ?? '';
      final String url;
      final String username;
      final String password;
      final String totp;

      if (data is LoginData) {
        url = data.uris.isEmpty ? '' : data.uris.first.uri;
        username = data.username;
        password = data.password;
        totp = data.totp;
      } else {
        url = '';
        username = '';
        password = '';
        totp = '';
      }

      rows.writeln([
        folder,
        data.name,
        url,
        username,
        password,
        totp,
        // Les cartes et identités n'ont pas de colonne dédiée : leur contenu
        // part dans les notes plutôt que d'être perdu sans le dire.
        _notesFor(data),
        item.favorite ? '1' : '0',
      ].map(_escapeCsv).join(','));
    }

    return rows.toString();
  }

  /// Sauvegarde chiffrée, autonome.
  ///
  /// La clé est dérivée de `exportPassword`, pas du mot de passe maître : une
  /// sauvegarde doit rester déchiffrable après un changement de mot de passe.
  static Future<String> toEncryptedJson(
    List<CipherItem> items, {
    required String exportPassword,
    Map<String, String> folderNames = const {},
    VaultCrypto? crypto,
    KdfParams kdf = KdfParams.argon2idDefault,
    String? saltHexForTest,
  }) async {
    if (exportPassword.length < 8) {
      throw const ExportException(
        'La phrase de passe de la sauvegarde doit faire au moins 8 caractères.',
      );
    }

    final engine = crypto ?? VaultCrypto();
    final salt = saltHexForTest ?? _randomSaltHex();

    final material = await engine.deriveMasterKeyMaterial(
      masterPassword: exportPassword,
      kdfSaltHex: salt,
      params: kdf,
    );
    try {
      // On réutilise la clé d'enveloppe comme clé de chiffrement du fichier :
      // même dérivation, même séparation de domaines, code déjà éprouvé.
      final payload = toBitwardenJson(items, folderNames: folderNames);
      final sealed = await engine.encryptStringWithKey(payload, material.wrapKey);

      return const JsonEncoder.withIndent('  ').convert({
        'format': encryptedFormatMarker,
        'version': 1,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'kdf': kdf.toJson(),
        'kdfSalt': salt,
        'itemCount': items.length,
        'data': sealed,
      });
    } finally {
      material.destroy();
    }
  }

  /// Marqueur du format chiffré. Sert à la détection avant de demander la phrase
  /// de passe.
  static const String encryptedFormatMarker = 'passvault-encrypted';

  /// Vrai si le contenu est une sauvegarde chiffrée Coffort.
  static bool isEncryptedBackup(String content) {
    final trimmed = content.trimLeft();
    if (!trimmed.startsWith('{')) return false;
    try {
      final decoded = jsonDecode(content);
      return decoded is Map<String, dynamic> &&
          decoded['format'] == encryptedFormatMarker;
    } catch (_) {
      return false;
    }
  }

  /// Déchiffre une sauvegarde et renvoie le JSON en clair, prêt pour
  /// `BitwardenImporter`.
  static Future<String> decryptBackup(
    String content, {
    required String exportPassword,
    VaultCrypto? crypto,
  }) async {
    final Map<String, dynamic> root;
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        throw const ExportException('Sauvegarde illisible');
      }
      root = decoded;
    } on FormatException {
      throw const ExportException('Sauvegarde illisible : JSON invalide');
    }

    if (root['format'] != encryptedFormatMarker) {
      throw const ExportException(
        'Ce fichier n’est pas une sauvegarde chiffrée Coffort.',
      );
    }

    final kdfJson = root['kdf'];
    final salt = root['kdfSalt'];
    final sealed = root['data'];
    if (kdfJson is! Map<String, dynamic> ||
        salt is! String ||
        sealed is! String) {
      throw const ExportException('Sauvegarde incomplète');
    }

    final engine = crypto ?? VaultCrypto();
    final material = await engine.deriveMasterKeyMaterial(
      masterPassword: exportPassword,
      kdfSaltHex: salt,
      params: KdfParams.fromJson(kdfJson),
    );
    try {
      return await engine.decryptStringWithKey(sealed, material.wrapKey);
    } on WrongMasterPasswordException {
      throw const ExportException('Phrase de passe incorrecte.');
    } catch (_) {
      // AES-GCM ne distingue pas « mauvaise clé » de « fichier abîmé », et c'est
      // voulu : les deux se présentent comme un échec d'authentification.
      throw const ExportException(
        'Déchiffrement impossible : phrase de passe incorrecte ou fichier abîmé.',
      );
    } finally {
      material.destroy();
    }
  }

  // ==================== INTERNES ====================

  static Map<String, dynamic> _itemToJson(CipherItem item) {
    final data = item.data;
    final base = <String, dynamic>{
      'type': item.type.wire,
      'name': data.name,
      'notes': data.notes.isEmpty ? null : data.notes,
      'favorite': item.favorite,
      'reprompt': item.reprompt ? 1 : 0,
      'folderId': item.folderId,
      if (data.fields.isNotEmpty)
        'fields': [
          for (final field in data.fields)
            {'name': field.name, 'value': field.value, 'type': field.type.wire},
        ],
    };

    switch (data) {
      case LoginData d:
        base['login'] = {
          'username': d.username.isEmpty ? null : d.username,
          'password': d.password.isEmpty ? null : d.password,
          'totp': d.totp.isEmpty ? null : d.totp,
          if (d.uris.isNotEmpty)
            'uris': [
              for (final uri in d.uris) {'uri': uri.uri, 'match': uri.match.wire},
            ],
        };
        if (d.passwordHistory.isNotEmpty) {
          base['passwordHistory'] = [
            for (final entry in d.passwordHistory)
              {
                'password': entry.password,
                'lastUsedDate': entry.replacedAt.toUtc().toIso8601String(),
              },
          ];
        }
      case CardData d:
        base['card'] = {
          'cardholderName': d.cardholderName.isEmpty ? null : d.cardholderName,
          'brand': d.brand.isEmpty ? null : d.brand,
          'number': d.number.isEmpty ? null : d.number,
          'expMonth': d.expMonth.isEmpty ? null : d.expMonth,
          'expYear': d.expYear.isEmpty ? null : d.expYear,
          'code': d.code.isEmpty ? null : d.code,
        };
      case IdentityData d:
        base['identity'] = {
          'title': d.title.isEmpty ? null : d.title,
          'firstName': d.firstName.isEmpty ? null : d.firstName,
          'middleName': d.middleName.isEmpty ? null : d.middleName,
          'lastName': d.lastName.isEmpty ? null : d.lastName,
          'company': d.company.isEmpty ? null : d.company,
          'email': d.email.isEmpty ? null : d.email,
          'phone': d.phone.isEmpty ? null : d.phone,
          'username': d.username.isEmpty ? null : d.username,
          'ssn': d.ssn.isEmpty ? null : d.ssn,
          'passportNumber': d.passportNumber.isEmpty ? null : d.passportNumber,
          'licenseNumber': d.licenseNumber.isEmpty ? null : d.licenseNumber,
          'address1': d.address1.isEmpty ? null : d.address1,
          'address2': d.address2.isEmpty ? null : d.address2,
          'city': d.city.isEmpty ? null : d.city,
          'state': d.state.isEmpty ? null : d.state,
          'postalCode': d.postalCode.isEmpty ? null : d.postalCode,
          'country': d.country.isEmpty ? null : d.country,
        };
      case SecureNoteData():
        base['secureNote'] = {'type': 0};
      case SshKeyData d:
        // Mêmes clés que dans l'export de Bitwarden, pour que le fichier reste
        // relisible par eux comme par nous.
        base['sshKey'] = {
          'privateKey': d.privateKey.isEmpty ? null : d.privateKey,
          'publicKey': d.publicKey.isEmpty ? null : d.publicKey,
          'keyFingerprint':
              d.keyFingerprint.isEmpty ? null : d.keyFingerprint,
        };
    }

    return base;
  }

  /// Aplatit ce qu'un CSV ne peut pas représenter, plutôt que de le perdre.
  static String _notesFor(CipherData data) {
    final extra = <String>[];
    switch (data) {
      case CardData d:
        if (d.number.isNotEmpty) extra.add('Numéro : ${d.number}');
        if (d.expiry.isNotEmpty) extra.add('Échéance : ${d.expiry}');
        if (d.code.isNotEmpty) extra.add('Cryptogramme : ${d.code}');
        if (d.cardholderName.isNotEmpty) {
          extra.add('Titulaire : ${d.cardholderName}');
        }
      case IdentityData d:
        if (d.fullName.isNotEmpty) extra.add('Nom : ${d.fullName}');
        if (d.email.isNotEmpty) extra.add('E-mail : ${d.email}');
        if (d.phone.isNotEmpty) extra.add('Téléphone : ${d.phone}');
        if (d.ssn.isNotEmpty) extra.add('N° sécurité sociale : ${d.ssn}');
        if (d.passportNumber.isNotEmpty) {
          extra.add('Passeport : ${d.passportNumber}');
        }
      case SshKeyData d:
        // La clé publique et l'empreinte, oui. La clé privée, non : un CSV est
        // un fichier en clair, souvent destiné à une autre application, et y
        // déverser un bloc PEM de plusieurs lignes le rendrait de surcroît
        // illisible. L'export JSON chiffré, lui, la conserve.
        if (d.publicKey.isNotEmpty) extra.add('Clé publique : ${d.publicKey}');
        if (d.keyFingerprint.isNotEmpty) {
          extra.add('Empreinte : ${d.keyFingerprint}');
        }
        extra.add('Clé privée non exportée en CSV — utiliser l’export chiffré.');
      case LoginData():
      case SecureNoteData():
        break;
    }
    for (final field in data.fields) {
      extra.add('${field.name} : ${field.value}');
    }
    return [if (data.notes.isNotEmpty) data.notes, ...extra].join('\n');
  }

  static String _escapeCsv(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  static String _randomSaltHex() {
    // Même source d'aléa que les clés du coffre.
    final key = VaultCrypto.randomBytes(16);
    return key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

class ExportException implements Exception {
  final String message;
  const ExportException(this.message);
  @override
  String toString() => message;
}
