import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:password_manager/core/utils/totp.dart';

/// Les vecteurs de la RFC 6238 sont donnés avec le secret ASCII « 12345678901234567890 ».
/// On le convertit en base32 pour passer par le même chemin que l'app.
String _base32Of(List<int> bytes) {
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  var buffer = 0;
  var bits = 0;
  final out = StringBuffer();
  for (final byte in bytes) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out.write(alphabet[(buffer >> bits) & 0x1F]);
    }
  }
  if (bits > 0) out.write(alphabet[(buffer << (5 - bits)) & 0x1F]);
  return out.toString();
}

void main() {
  final sha1Secret = _base32Of(utf8.encode('12345678901234567890'));
  // SHA-256 : le secret de la RFC fait 32 octets (la séquence répétée tronquée).
  final sha256Secret =
      _base32Of(utf8.encode('12345678901234567890123456789012'));

  TotpCode at(String secret, int epochSeconds,
      {TotpAlgorithm algo = TotpAlgorithm.sha1}) {
    final config = TotpConfig(
      secret: Totp.decodeBase32(secret),
      digits: 8,
      periodSeconds: 30,
      algorithm: algo,
    );
    return Totp.generate(
      config,
      at: DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000, isUtc: true),
    );
  }

  group('vecteurs de test RFC 6238', () {
    // Tableau de l'appendice B de la RFC.
    test('SHA-1', () {
      expect(at(sha1Secret, 59).code, '94287082');
      expect(at(sha1Secret, 1111111109).code, '07081804');
      expect(at(sha1Secret, 1111111111).code, '14050471');
      expect(at(sha1Secret, 1234567890).code, '89005924');
      expect(at(sha1Secret, 2000000000).code, '69279037');
      expect(at(sha1Secret, 20000000000).code, '65353130');
    });

    test('SHA-256', () {
      expect(
        at(sha256Secret, 59, algo: TotpAlgorithm.sha256).code,
        '46119246',
      );
      expect(
        at(sha256Secret, 1111111109, algo: TotpAlgorithm.sha256).code,
        '68084774',
      );
      expect(
        at(sha256Secret, 2000000000, algo: TotpAlgorithm.sha256).code,
        '90698825',
      );
    });
  });

  group('base32', () {
    test('décode un secret classique', () {
      expect(Totp.decodeBase32('JBSWY3DPEHPK3PXP'),
          Uint8List.fromList([72, 101, 108, 108, 111, 33, 222, 173, 190, 239]));
    });

    test('tolère la casse, les espaces et le remplissage', () {
      final expected = Totp.decodeBase32('JBSWY3DPEHPK3PXP');
      expect(Totp.decodeBase32('jbswy3dp ehpk3pxp'), expected);
      expect(Totp.decodeBase32('JBSW Y3DP EHPK 3PXP'), expected);
      expect(Totp.decodeBase32('JBSWY3DPEHPK3PXP===='), expected);
      expect(Totp.decodeBase32('JBSWY3DP-EHPK3PXP'), expected);
    });

    test('rejette un caractère hors alphabet', () {
      // 0, 1 et 8 n'existent pas en base32 RFC 4648.
      expect(() => Totp.decodeBase32('JBSW1234'),
          throwsA(isA<TotpFormatException>()));
    });

    test('rejette une chaîne vide', () {
      expect(() => Totp.decodeBase32('   '),
          throwsA(isA<TotpFormatException>()));
    });
  });

  group('URI otpauth', () {
    test('extrait secret, émetteur et compte', () {
      final config = Totp.parse(
        'otpauth://totp/GitHub:tannou?secret=JBSWY3DPEHPK3PXP&issuer=GitHub',
      );
      expect(config.issuer, 'GitHub');
      expect(config.account, 'tannou');
      expect(config.digits, 6);
      expect(config.periodSeconds, 30);
    });

    test('respecte digits, period et algorithm', () {
      final config = Totp.parse(
        'otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP&digits=8&period=60&algorithm=SHA256',
      );
      expect(config.digits, 8);
      expect(config.periodSeconds, 60);
      expect(config.algorithm, TotpAlgorithm.sha256);
    });

    test('gère un libellé encodé', () {
      final config = Totp.parse(
        'otpauth://totp/Mon%20Service:a%40b.c?secret=JBSWY3DPEHPK3PXP',
      );
      expect(config.issuer, 'Mon Service');
      expect(config.account, 'a@b.c');
    });

    test('rejette une URI sans secret', () {
      expect(() => Totp.parse('otpauth://totp/Test?issuer=X'),
          throwsA(isA<TotpFormatException>()));
    });
  });

  group('fenêtre de validité', () {
    test('le temps restant décroît sur la période', () {
      final config = TotpConfig(secret: Totp.decodeBase32('JBSWY3DPEHPK3PXP'));
      final debut = Totp.generate(config,
          at: DateTime.fromMillisecondsSinceEpoch(30000, isUtc: true));
      final fin = Totp.generate(config,
          at: DateTime.fromMillisecondsSinceEpoch(59000, isUtc: true));

      expect(debut.remaining.inSeconds, 30);
      expect(debut.progress, closeTo(1.0, 0.01));
      expect(fin.remaining.inSeconds, 1);
      expect(fin.progress, closeTo(0.033, 0.01));
      // Même fenêtre, donc même code.
      expect(debut.code, fin.code);
    });

    test('le code change de fenêtre en fenêtre', () {
      final config = TotpConfig(secret: Totp.decodeBase32('JBSWY3DPEHPK3PXP'));
      final a = Totp.generate(config,
          at: DateTime.fromMillisecondsSinceEpoch(30000, isUtc: true));
      final b = Totp.generate(config,
          at: DateTime.fromMillisecondsSinceEpoch(60000, isUtc: true));
      expect(a.code, isNot(b.code));
    });

    test('groupe le code pour la relecture', () {
      const six = TotpCode(
          code: '418249', remaining: Duration(seconds: 5), periodSeconds: 30);
      expect(six.grouped, '418 249');
      const eight = TotpCode(
          code: '94287082', remaining: Duration(seconds: 5), periodSeconds: 30);
      expect(eight.grouped, '9428 7082');
    });
  });

  group('validation de saisie', () {
    test('accepte les formes utilisables', () {
      expect(Totp.isValid('JBSWY3DPEHPK3PXP'), isTrue);
      expect(Totp.isValid('jbsw y3dp ehpk 3pxp'), isTrue);
      expect(
        Totp.isValid('otpauth://totp/X?secret=JBSWY3DPEHPK3PXP'),
        isTrue,
      );
    });

    test('refuse les formes inutilisables', () {
      expect(Totp.isValid(''), isFalse);
      expect(Totp.isValid('pas-un-secret!'), isFalse);
      expect(Totp.isValid('otpauth://totp/X'), isFalse);
    });

    test('décrit un secret pour l’affichage', () {
      expect(
        Totp.describe('otpauth://totp/GitHub:tannou?secret=JBSWY3DPEHPK3PXP'),
        'GitHub · tannou',
      );
      expect(Totp.describe('JBSWY3DPEHPK3PXP'), isNull);
    });
  });
}
