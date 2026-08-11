import '../../data/models/cipher.dart';

/// Décide si un identifiant du coffre correspond à ce que l'application ou le
/// navigateur demande.
///
/// C'est le cœur de la justesse du remplissage automatique, et il se trompe dans
/// deux directions :
///
/// * **trop permissif** — proposer les identifiants de `mabanque.ci` sur
///   `mabanque.ci.phishing.example` remplit un formulaire d'attaquant ;
/// * **trop strict** — ne rien proposer sur `www.github.com` parce que l'entrée
///   dit `github.com` rend la fonction inutilisable.
///
/// D'où le mode par défaut « domaine de base » : on compare le domaine
/// enregistrable, pas l'hôte complet, et jamais un simple `contains`.
abstract final class UriMatcher {
  /// Suffixes à deux niveaux les plus courants, pour ne pas réduire
  /// `exemple.co.uk` à `co.uk` — ce qui ferait correspondre *tous* les sites
  /// britanniques entre eux.
  ///
  /// Ce n'est pas la Public Suffix List complète : l'embarquer coûterait
  /// plusieurs centaines de kio pour un gain marginal ici. La liste couvre les
  /// cas qu'on rencontre en pratique ; un suffixe absent rend la comparaison
  /// plus stricte, jamais plus permissive.
  static const Set<String> _twoLevelSuffixes = {
    'co.uk', 'org.uk', 'ac.uk', 'gov.uk', 'me.uk', 'net.uk', 'sch.uk',
    'com.au', 'net.au', 'org.au', 'edu.au', 'gov.au',
    'co.nz', 'net.nz', 'org.nz', 'govt.nz',
    'co.za', 'org.za', 'web.za',
    'com.br', 'net.br', 'org.br', 'gov.br',
    'co.jp', 'ne.jp', 'or.jp', 'ac.jp', 'go.jp',
    'com.cn', 'net.cn', 'org.cn', 'gov.cn',
    'co.in', 'net.in', 'org.in', 'gov.in', 'ac.in',
    'com.mx', 'com.ar', 'com.tr', 'com.sg', 'com.hk', 'com.tw',
    // Afrique de l'Ouest, où l'app est utilisée.
    'co.ci', 'com.ci', 'org.ci', 'gouv.ci', 'net.ci',
    'com.ng', 'org.ng', 'gov.ng',
    'com.gh', 'org.gh', 'gov.gh',
    'com.sn', 'org.sn', 'gouv.sn',
  };

  /// Hôte extrait d'une chaîne, tolérant l'absence de schéma.
  static String? hostOf(String value) {
    final raw = value.trim().toLowerCase();
    if (raw.isEmpty) return null;

    // Un identifiant de paquet Android n'est pas une URL.
    if (raw.startsWith('androidapp://')) {
      return raw.substring('androidapp://'.length);
    }

    final candidate = raw.contains('://') ? raw : 'https://$raw';
    final parsed = Uri.tryParse(candidate);
    var host = parsed?.host;
    if (host == null || host.isEmpty) return null;
    if (host.startsWith('www.')) host = host.substring(4);
    return host;
  }

  /// Domaine enregistrable : `mail.google.com` → `google.com`,
  /// `boutique.exemple.co.uk` → `exemple.co.uk`.
  static String? baseDomain(String value) {
    final host = hostOf(value);
    if (host == null) return null;

    // Une adresse IP n'a pas de domaine de base : on la compare telle quelle.
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) return host;

    final parts = host.split('.').where((p) => p.isNotEmpty).toList();
    if (parts.length <= 2) return host;

    final lastTwo = parts.sublist(parts.length - 2).join('.');
    if (_twoLevelSuffixes.contains(lastTwo) && parts.length >= 3) {
      return parts.sublist(parts.length - 3).join('.');
    }
    return lastTwo;
  }

  /// Vrai si `stored` correspond à `requested` selon `match`.
  ///
  /// `requested` peut être une URL (navigateur) ou un identifiant de paquet
  /// Android (`androidapp://com.exemple.app`).
  static bool matches({
    required LoginUri stored,
    required String requested,
    UriMatchType? overrideMatch,
  }) {
    final rule = overrideMatch ?? stored.match;
    if (rule == UriMatchType.never) return false;

    final storedValue = stored.uri.trim().toLowerCase();
    final requestedValue = requested.trim().toLowerCase();
    if (storedValue.isEmpty || requestedValue.isEmpty) return false;

    // Les paquets Android se comparent à l'identique, quelle que soit la règle :
    // il n'y a pas de notion de sous-domaine pour un nom de paquet.
    final storedIsPackage = storedValue.startsWith('androidapp://');
    final requestedIsPackage = requestedValue.startsWith('androidapp://');
    if (storedIsPackage || requestedIsPackage) {
      return storedIsPackage &&
          requestedIsPackage &&
          storedValue == requestedValue;
    }

    return switch (rule) {
      UriMatchType.never => false,
      UriMatchType.exact => storedValue == requestedValue,
      UriMatchType.startsWith => requestedValue.startsWith(storedValue),
      UriMatchType.host => _hostMatch(storedValue, requestedValue),
      UriMatchType.domain => _domainMatch(storedValue, requestedValue),
    };
  }

  static bool _hostMatch(String stored, String requested) {
    final a = hostOf(stored);
    final b = hostOf(requested);
    return a != null && b != null && a == b;
  }

  static bool _domainMatch(String stored, String requested) {
    final a = baseDomain(stored);
    final b = baseDomain(requested);
    if (a == null || b == null) return false;
    // Comparaison d'égalité, jamais d'inclusion : `contains` ferait correspondre
    // `mabanque.ci` avec `mabanque.ci.attaquant.example`.
    return a == b;
  }

  /// Éléments du coffre à proposer pour `requested`, du plus pertinent au moins.
  ///
  /// Le tri place les correspondances d'hôte exact avant celles de domaine : sur
  /// `mail.google.com`, une entrée enregistrée pour cet hôte précis passe devant
  /// une entrée générique `google.com`.
  static List<CipherItem> candidatesFor(
    List<CipherItem> items,
    String requested, {
    String? packageName,
  }) {
    final scored = <(int, CipherItem)>[];

    for (final item in items) {
      final data = item.data;
      if (data is! LoginData) continue;
      if (data.username.isEmpty && data.password.isEmpty) continue;

      var best = -1;
      for (final uri in data.uris) {
        // L'identifiant de paquet est essayé en plus de l'URL : un navigateur
        // fournit la seconde, une app native le premier.
        for (final target in [
          requested,
          if (packageName != null) 'androidapp://$packageName',
        ]) {
          if (!matches(stored: uri, requested: target)) continue;
          final score = switch (uri.match) {
            UriMatchType.exact => 4,
            UriMatchType.host => 3,
            UriMatchType.startsWith => 2,
            UriMatchType.domain => 1,
            UriMatchType.never => -1,
          };
          if (score > best) best = score;
        }
      }

      if (best >= 0) {
        // Les favoris remontent à score égal : ce sont les comptes principaux.
        scored.add((best * 2 + (item.favorite ? 1 : 0), item));
      }
    }

    scored.sort((a, b) {
      if (a.$1 != b.$1) return b.$1.compareTo(a.$1);
      return a.$2.data.name.toLowerCase().compareTo(b.$2.data.name.toLowerCase());
    });

    return scored.map((e) => e.$2).toList(growable: false);
  }
}
