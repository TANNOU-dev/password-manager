// Diagnostic d'un fichier d'import : pourquoi telle entrée n'est-elle pas
// reconnue comme un doublon ?
//
//   dart run tool/diagnose_import.dart <fichier>
//
// Le point important : **aucune valeur secrète n'est affichée**. On montre le
// nom des champs qui diffèrent, jamais leur contenu. La sortie peut donc être
// recopiée telle quelle dans une conversation.
//
// Le code exécuté ici est exactement celui de l'application — même parseur,
// même empreinte de contenu. Un diagnostic qui réimplémenterait la logique
// pourrait conclure juste alors que l'app se trompe, ou l'inverse.

// Outil en ligne de commande : écrire sur la sortie standard est sa raison
// d'être, pas une négligence.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:password_manager/data/import/importers.dart';
import 'package:password_manager/data/models/cipher.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage : dart run tool/diagnose_import.dart <fichier>');
    exit(64);
  }

  final file = File(args.first);
  if (!file.existsSync()) {
    stderr.writeln('Fichier introuvable : ${args.first}');
    exit(66);
  }

  final ParsedImport parsed;
  try {
    parsed = parseImport(file.readAsStringSync(), fileName: file.uri.pathSegments.last);
  } on ImportFormatException catch (e) {
    stderr.writeln('Fichier illisible : ${e.message}');
    exit(65);
  }

  print('Format reconnu      : ${parsed.sourceLabel}');
  print('Entrées conservées  : ${parsed.count}');
  print('Doublons écartés    : ${parsed.duplicatesInFile}');
  print('Lignes ignorées     : ${parsed.skipped.length}');
  print('');

  // Regroupe par « même compte apparent » : nom + identifiant. Deux entrées de
  // ce groupe qui ont des empreintes différentes sont les cas intéressants —
  // celles que l'utilisateur croit identiques et que l'app distingue.
  final groups = <String, List<CipherItem>>{};
  for (final item in parsed.items) {
    groups.putIfAbsent(_apparentKey(item), () => []).add(item);
  }

  final suspects = groups.entries.where((e) => e.value.length > 1).toList();
  if (suspects.isEmpty) {
    print('Aucune entrée ne partage nom + identifiant avec une autre.');
    print('Les doublons visibles à l’œil doivent donc différer sur le nom');
    print('ou sur l’identifiant lui-même.');
    return;
  }

  print('${suspects.length} groupe(s) partagent nom + identifiant mais ont');
  print('survécu à la déduplication. Champs qui les séparent :');
  print('');

  final tally = <String, int>{};
  for (final group in suspects) {
    final differing = _differingFields(group.value);
    for (final field in differing) {
      tally[field] = (tally[field] ?? 0) + 1;
    }
    print('  • ${group.value.length} exemplaires — diffèrent par : '
        '${differing.isEmpty ? "(rien ?! à signaler)" : differing.join(", ")}');
  }

  print('');
  print('Récapitulatif des champs responsables :');
  final sorted = tally.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  for (final entry in sorted) {
    print('  ${entry.value.toString().padLeft(4)} × ${entry.key}');
  }
}

/// Ce qu'un humain regarde pour dire « c'est le même compte ».
String _apparentKey(CipherItem item) {
  final data = item.data;
  final username = data is LoginData ? data.username : '';
  return '${item.type.wire}|${data.name.toLowerCase()}|${username.toLowerCase()}';
}

/// Noms des champs sur lesquels les entrées d'un groupe divergent.
///
/// Ne rend que des **noms de champs**. Les valeurs restent sur la machine.
List<String> _differingFields(List<CipherItem> group) {
  final reference = group.first.data.toJson();
  final differing = <String>{};

  for (final item in group.skip(1)) {
    final other = item.data.toJson();
    for (final key in {...reference.keys, ...other.keys}) {
      final a = jsonEncode(reference[key]);
      final b = jsonEncode(other[key]);
      if (a != b) {
        // Précise quand c'est une liste : « 2 vs 3 adresses » explique mieux
        // qu'un simple nom de champ.
        final ra = reference[key];
        final rb = other[key];
        if (ra is List && rb is List && ra.length != rb.length) {
          differing.add('$key (${ra.length} vs ${rb.length})');
        } else {
          differing.add(key);
        }
      }
    }
  }
  return differing.toList()..sort();
}
