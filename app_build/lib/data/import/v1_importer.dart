import 'dart:convert';

import '../models/cipher.dart';
import 'csv_table.dart';
import 'import_result.dart';

/// Import des exports PassVault v1, pour la migration vers le coffre chiffré.
///
/// La v1 ne connaissait qu'un type d'entrée : site / e-mail / mot de passe /
/// note. Chaque entrée devient donc un identifiant, avec le site promu en URI
/// quand il ressemble à un domaine.
///
/// Deux formes circulent :
///   • `{"version":1,"entries":[…]}` — sortie de `backend/tools/export-v1.js`
///   • `[…]` — sortie du bouton « Exporter JSON » de l'ancienne app
class V1JsonImporter extends VaultImporter {
  const V1JsonImporter();

  @override
  String get label => 'PassVault v1 (JSON)';

  @override
  List<String> get extensions => const ['json'];

  @override
  bool canParse(String content, String? fileName) {
    final trimmed = content.trimLeft();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return false;
    try {
      final decoded = jsonDecode(content);
      if (decoded is List) {
        // Un tableau nu dont les entrées portent « site » : la marque de la v1.
        final first = decoded.whereType<Map<String, dynamic>>().firstOrNull;
        return first != null && first.containsKey('site');
      }
      if (decoded is Map<String, dynamic>) {
        return decoded['version'] == 1 && decoded['entries'] is List;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  ParsedImport parse(String content) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException catch (e) {
      throw ImportFormatException('JSON illisible : ${e.message}');
    }

    final List<dynamic> raw;
    if (decoded is List) {
      raw = decoded;
    } else if (decoded is Map<String, dynamic> && decoded['entries'] is List) {
      raw = decoded['entries'] as List;
    } else {
      throw const ImportFormatException(
        'Format inattendu : un tableau d’entrées ou un objet {"entries":[…]} '
        'est attendu',
      );
    }

    final items = <CipherItem>[];
    final skipped = <String>[];

    for (var i = 0; i < raw.length; i++) {
      final entry = raw[i];
      if (entry is! Map<String, dynamic>) {
        skipped.add('entrée ${i + 1} : objet attendu');
        continue;
      }
      final item = v1EntryToItem(entry);
      if (item == null) {
        skipped.add('entrée ${i + 1} : ni site ni identifiant exploitable');
        continue;
      }
      items.add(item);
    }

    return requireSomething(label, items, skipped);
  }
}

/// CSV v1 : en-tête `site,email,password,note`, facultatif.
class V1CsvImporter extends VaultImporter {
  const V1CsvImporter();

  @override
  String get label => 'PassVault v1 (CSV)';

  @override
  List<String> get extensions => const ['csv'];

  /// Volontairement restrictif : ce format n'a pas de signature propre, donc on
  /// ne le revendique que si l'en-tête est exactement celui de la v1. Sinon
  /// c'est `CsvImporter`, plus général, qui prend la main.
  @override
  bool canParse(String content, String? fileName) {
    if (content.trim().isEmpty) return false;
    final first = content.split('\n').first.trim().toLowerCase();
    return first.startsWith('site,email,password');
  }

  @override
  ParsedImport parse(String content) {
    if (content.trim().isEmpty) {
      throw const ImportFormatException('Fichier CSV vide');
    }

    final table = CsvTable.parse(content);
    var start = 0;
    if (table.rows.isNotEmpty) {
      final head = table.rows.first.first.trim().toLowerCase();
      if (head == 'site' || head == 'website' || head == 'service') start = 1;
    }

    final items = <CipherItem>[];
    final skipped = <String>[];

    for (var i = start; i < table.rows.length; i++) {
      final row = table.rows[i];
      if (row.every((c) => c.trim().isEmpty)) continue;
      if (row.length < 3) {
        skipped.add('ligne ${i + 1} : moins de trois colonnes');
        continue;
      }
      final item = v1EntryToItem({
        'site': row[0],
        'email': row[1],
        'password': row[2],
        'note': row.length > 3 ? row.sublist(3).join(', ') : '',
      });
      if (item == null) {
        skipped.add('ligne ${i + 1} : ni site ni identifiant exploitable');
        continue;
      }
      items.add(item);
    }

    return requireSomething(label, items, skipped);
  }
}

/// Conversion d'une entrée v1 en élément de coffre. Partagée par les deux
/// variantes du format.
CipherItem? v1EntryToItem(Map<String, dynamic> entry) {
  String read(String key) {
    final value = entry[key];
    return value == null ? '' : value.toString().trim();
  }

  final site = read('site');
  final username = read('email').isNotEmpty ? read('email') : read('username');
  final password = read('password');
  final note = read('note').isNotEmpty ? read('note') : read('notes');

  if (site.isEmpty && username.isEmpty && password.isEmpty) return null;

  return CipherItem(
    data: LoginData(
      name: site.isNotEmpty ? site : (username.isNotEmpty ? username : 'Sans nom'),
      username: username,
      password: password,
      notes: note,
      uris: urisFrom([site]),
      // La v1 ne gardait pas de date de changement : on ne l'invente pas, sinon
      // le rapport de sécurité présenterait des mots de passe vieux de plusieurs
      // années comme récents.
      passwordUpdatedAt: null,
    ),
    createdAt: DateTime.tryParse(read('createdAt')),
  );
}
