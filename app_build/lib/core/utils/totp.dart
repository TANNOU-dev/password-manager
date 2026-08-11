import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// Codes à usage unique, RFC 6238 (TOTP) au-dessus de RFC 4226 (HOTP).
///
/// Implémenté directement plutôt qu'ajouté en dépendance : l'algorithme fait
/// vingt lignes, et le secret TOTP est une donnée du même niveau de sensibilité
/// qu'un mot de passe — autant qu'il ne traverse aucun code tiers.
///
/// Le calcul est local et hors ligne : il ne dépend que de l'horloge. Si les
/// codes sont systématiquement refusés, c'est l'heure de l'appareil qui dérive.

class TotpConfig {
  final Uint8List secret;
  final int digits;
  final int periodSeconds;
  final TotpAlgorithm algorithm;

  /// Renseignés par les URI `otpauth://`, utiles à l'affichage.
  final String? issuer;
  final String? account;

  const TotpConfig({
    required this.secret,
    this.digits = 6,
    this.periodSeconds = 30,
    this.algorithm = TotpAlgorithm.sha1,
    this.issuer,
    this.account,
  });
}

enum TotpAlgorithm {
  sha1('SHA1'),
  sha256('SHA256'),
  sha512('SHA512');

  const TotpAlgorithm(this.wireName);
  final String wireName;

  static TotpAlgorithm fromName(String? value) {
    if (value == null) return TotpAlgorithm.sha1;
    final upper = value.toUpperCase();
    return TotpAlgorithm.values.firstWhere(
      (a) => a.wireName == upper,
      orElse: () => TotpAlgorithm.sha1,
    );
  }

  // Import préfixé : sans ça, `sha1` dans ce corps d'enum désignerait la
  // constante voisine et non l'algorithme du paquet crypto.
  crypto.Hmac hmacWith(List<int> key) => switch (this) {
        TotpAlgorithm.sha1 => crypto.Hmac(crypto.sha1, key),
        TotpAlgorithm.sha256 => crypto.Hmac(crypto.sha256, key),
        TotpAlgorithm.sha512 => crypto.Hmac(crypto.sha512, key),
      };
}

class TotpFormatException implements Exception {
  final String message;
  const TotpFormatException(this.message);
  @override
  String toString() => message;
}

/// Code courant et temps restant sur sa fenêtre.
class TotpCode {
  final String code;
  final Duration remaining;
  final int periodSeconds;

  const TotpCode({
    required this.code,
    required this.remaining,
    required this.periodSeconds,
  });

  /// 1.0 au début de la fenêtre, 0.0 juste avant l'expiration. Alimente
  /// directement l'anneau de progression.
  double get progress =>
      (remaining.inMilliseconds / (periodSeconds * 1000)).clamp(0.0, 1.0);

  /// Groupé par trois : « 418 249 » se recopie beaucoup plus sûrement que
  /// « 418249 ».
  String get grouped {
    if (code.length == 6) return '${code.substring(0, 3)} ${code.substring(3)}';
    if (code.length == 8) return '${code.substring(0, 4)} ${code.substring(4)}';
    return code;
  }
}

abstract final class Totp {
  /// Accepte soit un secret base32 nu, soit une URI `otpauth://totp/...`.
  /// Les deux formes circulent : les QR codes produisent la seconde, les sites
  /// affichent souvent la première.
  static TotpConfig parse(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      throw const TotpFormatException('Secret TOTP vide');
    }

    if (trimmed.toLowerCase().startsWith('otpauth://')) {
      return _parseUri(trimmed);
    }
    return TotpConfig(secret: decodeBase32(trimmed));
  }

  static TotpConfig _parseUri(String source) {
    final uri = Uri.tryParse(source);
    if (uri == null) {
      throw const TotpFormatException('URI otpauth illisible');
    }
    final secret = uri.queryParameters['secret'];
    if (secret == null || secret.isEmpty) {
      throw const TotpFormatException('URI otpauth sans paramètre « secret »');
    }

    // Le libellé est « Issuer:compte » ; le paramètre `issuer` le double parfois.
    String? issuer = uri.queryParameters['issuer'];
    String? account;
    final label = uri.pathSegments.isNotEmpty
        ? Uri.decodeComponent(uri.pathSegments.last)
        : '';
    if (label.contains(':')) {
      final parts = label.split(':');
      issuer ??= parts.first.trim();
      account = parts.sublist(1).join(':').trim();
    } else if (label.isNotEmpty) {
      account = label;
    }

    final digits = int.tryParse(uri.queryParameters['digits'] ?? '') ?? 6;
    final period = int.tryParse(uri.queryParameters['period'] ?? '') ?? 30;

    return TotpConfig(
      secret: decodeBase32(secret),
      digits: digits.clamp(6, 10),
      periodSeconds: period < 1 ? 30 : period,
      algorithm: TotpAlgorithm.fromName(uri.queryParameters['algorithm']),
      issuer: issuer,
      account: account,
    );
  }

  /// Base32 selon RFC 4648, sans casse et sans remplissage obligatoire — les
  /// sites publient le secret avec ou sans `=`, et souvent par groupes de
  /// quatre séparés par des espaces.
  static Uint8List decodeBase32(String input) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final cleaned =
        input.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '').replaceAll('=', '');
    if (cleaned.isEmpty) {
      throw const TotpFormatException('Secret TOTP vide');
    }

    var buffer = 0;
    var bitsLeft = 0;
    final out = <int>[];

    for (final ch in cleaned.split('')) {
      final value = alphabet.indexOf(ch);
      if (value < 0) {
        throw TotpFormatException('Caractère « $ch » invalide en base32');
      }
      buffer = (buffer << 5) | value;
      bitsLeft += 5;
      if (bitsLeft >= 8) {
        bitsLeft -= 8;
        out.add((buffer >> bitsLeft) & 0xFF);
      }
    }

    if (out.isEmpty) {
      throw const TotpFormatException('Secret TOTP trop court');
    }
    return Uint8List.fromList(out);
  }

  /// Code pour l'instant donné. `at` sert aux tests, sinon l'heure courante.
  static TotpCode generate(TotpConfig config, {DateTime? at}) {
    final now = (at ?? DateTime.now()).toUtc();
    final epochSeconds = now.millisecondsSinceEpoch ~/ 1000;
    final counter = epochSeconds ~/ config.periodSeconds;

    final code = _hotp(config, counter);

    final elapsedMs = now.millisecondsSinceEpoch -
        (counter * config.periodSeconds * 1000);
    final remainingMs = config.periodSeconds * 1000 - elapsedMs;

    return TotpCode(
      code: code,
      remaining: Duration(milliseconds: remainingMs),
      periodSeconds: config.periodSeconds,
    );
  }

  static String _hotp(TotpConfig config, int counter) {
    // Compteur sur 8 octets, gros-boutiste.
    final message = ByteData(8);
    message.setUint64(0, counter, Endian.big);

    final digest =
        config.algorithm.hmacWith(config.secret).convert(message.buffer.asUint8List());
    final bytes = digest.bytes;

    // Troncature dynamique : les 4 bits de poids faible du dernier octet
    // désignent l'offset de lecture.
    final offset = bytes[bytes.length - 1] & 0x0F;
    final binary = ((bytes[offset] & 0x7F) << 24) |
        ((bytes[offset + 1] & 0xFF) << 16) |
        ((bytes[offset + 2] & 0xFF) << 8) |
        (bytes[offset + 3] & 0xFF);

    final modulo = _pow10(config.digits);
    return (binary % modulo).toString().padLeft(config.digits, '0');
  }

  static int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }

  /// Vrai si la chaîne donne un secret exploitable. Sert à valider la saisie
  /// sans faire échouer l'enregistrement de tout l'élément.
  static bool isValid(String source) {
    try {
      generate(parse(source));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Nom lisible d'un secret, pour l'afficher à côté du code.
  static String? describe(String source) {
    try {
      final config = parse(source);
      final parts = [config.issuer, config.account]
          .where((s) => s != null && s.isNotEmpty)
          .cast<String>();
      return parts.isEmpty ? null : parts.join(' · ');
    } catch (_) {
      return null;
    }
  }
}
