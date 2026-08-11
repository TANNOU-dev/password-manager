// Banc d'essai : compare le coût des KDF candidats en pur Dart.
// dart run tool/bench_kdf.dart
//
// À rejouer sur un vrai téléphone avant de changer les paramètres par défaut :
// les chiffres d'un CPU de bureau sous-estiment nettement le coût sur mobile.
//
// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:cryptography/cryptography.dart';

Future<Duration> time(String label, Future<void> Function() body) async {
  final sw = Stopwatch()..start();
  await body();
  sw.stop();
  print('${label.padRight(46)} ${sw.elapsedMilliseconds} ms');
  return sw.elapsed;
}

Future<void> main() async {
  const password = 'un-mot-de-passe-maitre-assez-long-2026';
  final salt = utf8.encode('tannouab@gmail.com');

  print('--- PBKDF2-HMAC-SHA256 ---');
  for (final iters in [100000, 300000, 600000]) {
    await time('pbkdf2 $iters iterations', () async {
      final kdf = Pbkdf2.hmacSha256(iterations: iters, bits: 256);
      await kdf.deriveKeyFromPassword(password: password, nonce: salt);
    });
  }

  print('--- Argon2id (hashLength 32) ---');
  final configs = [
    (m: 19456, t: 2, p: 1, label: 'OWASP 19 MiB, t=2, p=1'),
    (m: 65536, t: 3, p: 4, label: 'Bitwarden 64 MiB, t=3, p=4'),
    (m: 65536, t: 3, p: 1, label: '64 MiB, t=3, p=1'),
  ];
  for (final c in configs) {
    await time('argon2id ${c.label}', () async {
      final kdf = Argon2id(
        memory: c.m,
        iterations: c.t,
        parallelism: c.p,
        hashLength: 32,
      );
      await kdf.deriveKeyFromPassword(password: password, nonce: salt);
    });
  }
}
