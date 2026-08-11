import 'dart:convert';
import 'dart:typed_data';

/// Représentation sur le fil d'une donnée chiffrée : `1.base64(nonce‖chiffré‖mac)`.
///
/// Le préfixe de version rend un futur changement de suite cryptographique
/// non ambigu : un enregistrement écrit aujourd'hui restera identifiable.
/// Le serveur ne voit jamais que cette chaîne.
class EncString {
  /// AES-GCM, nonce de 96 bits, étiquette de 128 bits.
  static const String currentVersion = '1';
  static const int nonceLength = 12;
  static const int macLength = 16;

  final String version;
  final Uint8List nonce;
  final Uint8List cipherText;
  final Uint8List mac;

  const EncString({
    required this.version,
    required this.nonce,
    required this.cipherText,
    required this.mac,
  });

  EncString.v1({
    required this.nonce,
    required this.cipherText,
    required this.mac,
  }) : version = currentVersion;

  /// Concaténation attendue par le chiffreur : nonce, puis chiffré, puis MAC.
  Uint8List get concatenation {
    final out = Uint8List(nonce.length + cipherText.length + mac.length);
    out.setAll(0, nonce);
    out.setAll(nonce.length, cipherText);
    out.setAll(nonce.length + cipherText.length, mac);
    return out;
  }

  String serialize() => '$version.${base64.encode(concatenation)}';

  @override
  String toString() => serialize();

  static EncString parse(String value) {
    final dot = value.indexOf('.');
    if (dot <= 0) {
      throw const EncStringFormatException('préfixe de version absent');
    }
    final version = value.substring(0, dot);
    if (version != currentVersion) {
      throw EncStringFormatException('version « $version » non prise en charge');
    }

    final Uint8List raw;
    try {
      raw = base64.decode(value.substring(dot + 1));
    } on FormatException {
      throw const EncStringFormatException('charge utile base64 invalide');
    }

    if (raw.length < nonceLength + macLength) {
      throw const EncStringFormatException(
        'charge utile trop courte pour contenir un nonce et un MAC',
      );
    }

    return EncString(
      version: version,
      nonce: Uint8List.sublistView(raw, 0, nonceLength),
      cipherText: Uint8List.sublistView(raw, nonceLength, raw.length - macLength),
      mac: Uint8List.sublistView(raw, raw.length - macLength),
    );
  }

  /// Vrai si la chaîne a la forme d'une donnée chiffrée. Utile pour distinguer
  /// un champ déjà chiffré d'un champ resté en clair par erreur.
  static bool looksEncrypted(String? value) {
    if (value == null || value.isEmpty) return false;
    try {
      parse(value);
      return true;
    } on EncStringFormatException {
      return false;
    }
  }
}

class EncStringFormatException implements Exception {
  final String message;
  const EncStringFormatException(this.message);

  @override
  String toString() => 'EncStringFormatException: $message';
}
