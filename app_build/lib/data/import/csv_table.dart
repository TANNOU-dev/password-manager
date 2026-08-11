/// Parseur CSV partagé par tous les importateurs.
///
/// Écrit à la main plutôt que pris en dépendance parce qu'il doit tolérer ce que
/// les gestionnaires de mots de passe produisent réellement : guillemets
/// doublés, sauts de ligne *dans* un champ (les notes multilignes de KeePass et
/// de 1Password), fins de ligne Windows, et en-têtes de casse variable.
///
/// L'implémentation du serveur v1 découpait sur `\n` sans tenir compte des
/// guillemets : toute note multiligne y perdait tout après sa première ligne.
class CsvTable {
  const CsvTable(this.rows);

  final List<List<String>> rows;

  bool get isEmpty => rows.isEmpty;

  /// Première ligne si elle ressemble à un en-tête, sinon `null`.
  ///
  /// L'heuristique : un en-tête ne contient pas de champ qui ressemble à une
  /// URL, et au moins un de ses libellés est un nom de colonne connu.
  List<String>? get header {
    if (rows.isEmpty) return null;
    final first = rows.first.map((c) => c.trim().toLowerCase()).toList();
    if (first.any((c) => c.startsWith('http://') || c.startsWith('https://'))) {
      return null;
    }
    const known = {
      'name', 'title', 'url', 'urls', 'username', 'login_username', 'password',
      'login_password', 'notes', 'note', 'site', 'website', 'service', 'type',
      'folder', 'grouping', 'group', 'totp', 'otpauth', 'login_uri', 'extra',
      'account', 'login_totp', 'favorite', 'reprompt', 'card_number',
    };
    return first.any(known.contains) ? rows.first : null;
  }

  /// Lignes de données, en-tête exclu s'il y en a un.
  List<List<String>> get body {
    final head = header;
    final start = head == null ? 0 : 1;
    return rows
        .sublist(start)
        .where((r) => r.any((c) => c.trim().isNotEmpty))
        .toList(growable: false);
  }

  /// Index des colonnes par nom normalisé. Vide s'il n'y a pas d'en-tête.
  Map<String, int> get columns {
    final head = header;
    if (head == null) return const {};
    final map = <String, int>{};
    for (var i = 0; i < head.length; i++) {
      final key = head[i].trim().toLowerCase();
      // Première occurrence gagnante : certains exports répètent une colonne.
      map.putIfAbsent(key, () => i);
    }
    return map;
  }

  static CsvTable parse(String source, {String delimiter = ','}) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < source.length; i++) {
      final c = source[i];

      if (inQuotes) {
        if (c == '"') {
          // Guillemet doublé = guillemet littéral.
          if (i + 1 < source.length && source[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(c);
        }
        continue;
      }

      if (c == '"') {
        inQuotes = true;
      } else if (c == delimiter) {
        row.add(field.toString());
        field.clear();
      } else if (c == '\r') {
        // Ignoré : les fins de ligne Windows arrivent en \r\n.
      } else if (c == '\n') {
        row.add(field.toString());
        field.clear();
        rows.add(row);
        row = <String>[];
      } else {
        field.write(c);
      }
    }

    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      rows.add(row);
    }

    return CsvTable(rows);
  }

  /// Devine le séparateur. Les exports européens sortent parfois en
  /// point-virgule, et un CSV lu avec le mauvais séparateur donne une seule
  /// colonne — donc un import muet et vide.
  static String detectDelimiter(String source) {
    final sample = source.split('\n').take(5).join('\n');
    var best = ',';
    var bestCount = 0;
    for (final candidate in [',', ';', '\t']) {
      // On compte hors guillemets, sinon une note contenant des virgules
      // faussersait le vote.
      var count = 0;
      var inQuotes = false;
      for (final ch in sample.split('')) {
        if (ch == '"') {
          inQuotes = !inQuotes;
        } else if (!inQuotes && ch == candidate) {
          count++;
        }
      }
      if (count > bestCount) {
        bestCount = count;
        best = candidate;
      }
    }
    return best;
  }

  /// Parse en devinant le séparateur.
  static CsvTable parseAuto(String source) =>
      parse(source, delimiter: detectDelimiter(source));
}
