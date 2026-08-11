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

/// Lien Markdown `[libellé](url)`.
///
/// Des coffres réels en contiennent : un `[www.paypal.com](https://www.paypal.com)`
/// arrive quand la source a été copiée depuis un document. Sans ce traitement, la
/// chaîne entière finit comme adresse — donc une URI que le remplissage
/// automatique ne fera jamais correspondre.
final _markdownLink = RegExp(r'^\s*\[([^\]]*)\]\(\s*([^)\s]+)\s*\)\s*$');

/// Extrait `(libellé, url)` d'un lien Markdown, ou `null` si ce n'en est pas un.
({String label, String url})? unwrapMarkdownLink(String value) {
  final match = _markdownLink.firstMatch(value);
  if (match == null) return null;
  final label = match.group(1)!.trim();
  final url = match.group(2)!.trim();
  if (url.isEmpty) return null;
  return (label: label, url: url);
}

/// Nettoie un nom d'élément venu d'une source approximative.
///
/// Un lien Markdown est réduit à son libellé, ou à son URL si le libellé est
/// vide. Le reste est renvoyé tel quel : on ne réécrit pas ce que l'utilisateur
/// a saisi volontairement.
String cleanItemName(String value) {
  final link = unwrapMarkdownLink(value);
  if (link == null) return value.trim();
  return link.label.isNotEmpty ? link.label : link.url;
}

/// Promeut une chaîne en URI si elle ressemble à une adresse. « Ma banque » n'en
/// est pas une ; « github.com » oui.
List<LoginUri> urisFrom(Iterable<String> candidates) {
  final out = <LoginUri>[];
  for (final raw in candidates) {
    var value = raw.trim();
    if (value.isEmpty) continue;

    // Déballe d'abord : sinon le `://` du lien Markdown ferait passer toute la
    // chaîne pour une URL.
    final link = unwrapMarkdownLink(value);
    if (link != null) value = link.url;

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
