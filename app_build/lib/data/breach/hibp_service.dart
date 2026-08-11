import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

/// Confrontation des mots de passe aux fuites connues, via Have I Been Pwned.
///
/// ## Ce qui sort de l'appareil
///
/// On calcule le SHA-1 du mot de passe, et on n'envoie que **les 5 premiers
/// caractères hexadécimaux** de l'empreinte. Le serveur renvoie tous les
/// condensés commençant par ce préfixe — environ 800 sur les 850 millions de sa
/// base — et la comparaison finale se fait ici. C'est le protocole
/// « k-anonymity » de HIBP.
///
/// Conséquence : le mot de passe ne quitte jamais l'appareil, et son empreinte
/// complète non plus. Le préfixe désigne un seau d'environ 800 mots de passe
/// possibles, ce qui n'identifie rien.
///
/// Ce que ça reste malgré tout : **un appel réseau à un tiers**. Il révèle qu'un
/// utilisateur de cette adresse IP vérifie des mots de passe, et combien. C'est
/// pour ça que la vérification est déclenchée à la demande et jamais en tâche de
/// fond — voir l'écran Sécurité.
///
/// L'en-tête `Add-Padding` demande à HIBP de compléter la réponse avec des
/// entrées factices, pour que sa taille ne trahisse pas le préfixe demandé à un
/// observateur du réseau.
class HibpService {
  HibpService({http.Client? client, this.endpoint = _defaultEndpoint})
      : _http = client ?? http.Client();

  static const String _defaultEndpoint = 'https://api.pwnedpasswords.com/range';

  final http.Client _http;
  final String endpoint;

  /// Cache par préfixe, valable le temps de la session. Deux mots de passe
  /// faibles tombent souvent dans le même seau, et on évite ainsi de répéter la
  /// requête — moins de trafic, donc moins de signal envoyé.
  final Map<String, Map<String, int>> _cache = {};

  /// Nombre d'apparitions du mot de passe dans les fuites connues. 0 signifie
  /// « absent de cette base », pas « sûr ».
  Future<int> countFor(String password) async {
    if (password.isEmpty) return 0;

    final digest = crypto.sha1
        .convert(utf8.encode(password))
        .toString()
        .toUpperCase();
    final prefix = digest.substring(0, 5);
    final suffix = digest.substring(5);

    final bucket = await _bucket(prefix);
    return bucket[suffix] ?? 0;
  }

  /// Vérifie un lot de mots de passe distincts.
  ///
  /// Renvoie le nombre d'apparitions par mot de passe. Les doublons sont
  /// dédupliqués avant l'appel : un mot de passe réutilisé sur cinq comptes ne
  /// génère qu'une requête.
  Future<Map<String, int>> countForAll(
    Iterable<String> passwords, {
    void Function(int done, int total)? onProgress,
  }) async {
    final distinct = passwords.where((p) => p.isNotEmpty).toSet().toList();
    final results = <String, int>{};

    for (var i = 0; i < distinct.length; i++) {
      final password = distinct[i];
      try {
        results[password] = await countFor(password);
      } on HibpFailure {
        // Un préfixe qui échoue ne doit pas annuler tout le rapport : on laisse
        // ce mot de passe non renseigné plutôt que de le déclarer sain à tort.
        rethrow;
      }
      onProgress?.call(i + 1, distinct.length);
    }
    return results;
  }

  Future<Map<String, int>> _bucket(String prefix) async {
    final cached = _cache[prefix];
    if (cached != null) return cached;

    final http.Response response;
    try {
      response = await _http.get(
        Uri.parse('$endpoint/$prefix'),
        headers: const {
          'Add-Padding': 'true',
          'User-Agent': 'PassVault',
        },
      );
    } catch (e) {
      throw HibpFailure('Service de vérification injoignable : $e');
    }

    if (response.statusCode != 200) {
      throw HibpFailure(
        'Le service de vérification a répondu ${response.statusCode}',
      );
    }

    final bucket = <String, int>{};
    for (final line in const LineSplitter().convert(response.body)) {
      final parts = line.trim().split(':');
      if (parts.length != 2) continue;
      final count = int.tryParse(parts[1].trim());
      // Le remplissage de `Add-Padding` arrive avec un compte de 0 : on le garde
      // tel quel, il ne fera correspondre aucun vrai mot de passe.
      if (count == null) continue;
      bucket[parts[0].trim().toUpperCase()] = count;
    }

    _cache[prefix] = bucket;
    return bucket;
  }

  void clearCache() => _cache.clear();

  void close() => _http.close();
}

class HibpFailure implements Exception {
  final String message;
  const HibpFailure(this.message);
  @override
  String toString() => message;
}
