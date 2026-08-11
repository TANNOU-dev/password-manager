/// Paramètres de dérivation de la clé maître.
///
/// Ils sont servis par le serveur *avant* authentification, puisque le client en
/// a besoin pour recalculer la clé. Ils sont donc publics par construction :
/// leur secret n'est jamais supposé.
enum KdfType {
  argon2id('argon2id'),
  pbkdf2('pbkdf2');

  const KdfType(this.wireName);
  final String wireName;

  static KdfType fromWire(String value) {
    return KdfType.values.firstWhere(
      (t) => t.wireName == value,
      orElse: () => throw ArgumentError('KDF inconnu : $value'),
    );
  }
}

class KdfParams {
  final KdfType type;

  /// Nombre de passes.
  final int iterations;

  /// Argon2id uniquement : nombre de blocs de 1 kio.
  final int? memory;

  /// Argon2id uniquement : nombre de voies parallèles.
  final int? parallelism;

  const KdfParams({
    required this.type,
    required this.iterations,
    this.memory,
    this.parallelism,
  });

  /// Mesuré sur ce projet : ~950 ms en pur Dart sur un CPU de bureau, contre
  /// ~4400 ms pour PBKDF2 à 600 000 itérations, pour une résistance GPU bien
  /// supérieure. Voir `tool/bench_kdf.dart` pour rejouer la mesure.
  static const KdfParams argon2idDefault = KdfParams(
    type: KdfType.argon2id,
    iterations: 3,
    memory: 65536, // 64 MiB
    parallelism: 4,
  );

  /// Repli pour un appareil trop lent. Reste au-dessus des recommandations
  /// OWASP (19 MiB, t=2).
  static const KdfParams argon2idLight = KdfParams(
    type: KdfType.argon2id,
    iterations: 2,
    memory: 19456,
    parallelism: 1,
  );

  factory KdfParams.fromJson(Map<String, dynamic> json) {
    return KdfParams(
      type: KdfType.fromWire(json['type'] as String),
      iterations: json['iterations'] as int,
      memory: json['memory'] as int?,
      parallelism: json['parallelism'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.wireName,
        'iterations': iterations,
        if (memory != null) 'memory': memory,
        if (parallelism != null) 'parallelism': parallelism,
      };

  /// Libellé affichable dans les réglages, pour que l'utilisateur sache ce qui
  /// protège réellement son coffre.
  String get label => switch (type) {
        KdfType.argon2id =>
          'Argon2id · ${(memory! / 1024).round()} Mio · $iterations passe(s) · $parallelism voie(s)',
        KdfType.pbkdf2 => 'PBKDF2-SHA256 · $iterations itérations',
      };

  @override
  bool operator ==(Object other) =>
      other is KdfParams &&
      other.type == type &&
      other.iterations == iterations &&
      other.memory == memory &&
      other.parallelism == parallelism;

  @override
  int get hashCode => Object.hash(type, iterations, memory, parallelism);
}
