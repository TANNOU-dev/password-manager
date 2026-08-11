import '../models/cipher.dart';

/// Résultat d'un import, avant chiffrement et envoi.
class ParsedImport {
  const ParsedImport({
    required this.sourceLabel,
    required this.items,
    this.folderNames = const [],
    this.skipped = const [],
  });

  /// Format reconnu, affiché à l'utilisateur avant qu'il valide.
  final String sourceLabel;

  final List<CipherItem> items;

  /// Dossiers présents dans le fichier source. Le nom du dossier voyage en clair
  /// dans le fichier ; il sera chiffré à la création côté client.
  final List<String> folderNames;

  /// Lignes que le parseur n'a pas su lire, avec leur motif.
  ///
  /// Remontées à l'utilisateur plutôt qu'ignorées : un import silencieusement
  /// partiel est plus dangereux qu'un échec franc, parce qu'on croit avoir
  /// migré et on supprime la source.
  final List<String> skipped;

  int get count => items.length;
  bool get hasSkipped => skipped.isNotEmpty;

  /// Répartition par type, pour le récapitulatif avant validation.
  Map<CipherType, int> get byType {
    final counts = <CipherType, int>{};
    for (final item in items) {
      counts[item.type] = (counts[item.type] ?? 0) + 1;
    }
    return counts;
  }
}

class ImportFormatException implements Exception {
  final String message;
  const ImportFormatException(this.message);
  @override
  String toString() => message;
}

/// Contrat commun aux formats d'import.
abstract class VaultImporter {
  const VaultImporter();

  /// Nom affiché à l'utilisateur.
  String get label;

  /// Extensions plausibles, pour le sélecteur de fichiers.
  List<String> get extensions;

  /// Vrai si ce contenu ressemble au format. Sert à la détection automatique :
  /// l'utilisateur ne devrait pas avoir à savoir dans quel dialecte son
  /// ancien gestionnaire a exporté.
  bool canParse(String content, String? fileName);

  ParsedImport parse(String content);
}

/// Un fichier n'a pas besoin d'être exhaustif pour être exploitable, mais un
/// fichier qui ne donne ni élément ni motif de rejet n'avait rien dedans.
ParsedImport requireSomething(
  String sourceLabel,
  List<CipherItem> items,
  List<String> skipped, {
  List<String> folderNames = const [],
}) {
  if (items.isEmpty && skipped.isEmpty) {
    throw const ImportFormatException('Aucune entrée trouvée dans le fichier');
  }
  return ParsedImport(
    sourceLabel: sourceLabel,
    items: items,
    folderNames: folderNames,
    skipped: skipped,
  );
}

/// Promeut une chaîne en URI si elle ressemble à une adresse. « Ma banque » n'en
/// est pas une ; « github.com » oui.
List<LoginUri> urisFrom(Iterable<String> candidates) {
  final out = <LoginUri>[];
  for (final raw in candidates) {
    final value = raw.trim();
    if (value.isEmpty) continue;
    if (value.contains('://')) {
      out.add(LoginUri(uri: value));
      continue;
    }
    if (!value.contains(' ') && RegExp(r'^[\w-]+(\.[\w-]+)+').hasMatch(value)) {
      out.add(LoginUri(uri: 'https://$value'));
    }
  }
  return out;
}
