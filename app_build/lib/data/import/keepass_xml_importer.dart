import 'package:xml/xml.dart';

import '../models/cipher.dart';
import 'import_result.dart';

/// Import d'un export XML KeePass 2 / KeePassXC.
///
/// Structure du format : `KeePassFile > Root > Group*` récursif, chaque `Entry`
/// portant des paires `String > Key/Value`. Les clés standard sont `Title`,
/// `UserName`, `Password`, `URL`, `Notes` ; tout le reste est un champ
/// personnalisé, et `Value` peut porter `ProtectedInMemory="True"` — ce qui
/// désigne un champ à masquer.
///
/// La hiérarchie de groupes est aplatie en un seul niveau, séparé par « / » :
/// Coffort n'a qu'un niveau de dossiers, et perdre le chemin serait pire que
/// le concaténer.
class KeepassXmlImporter extends VaultImporter {
  const KeepassXmlImporter();

  @override
  String get label => 'KeePass (XML)';

  @override
  List<String> get extensions => const ['xml'];

  @override
  bool canParse(String content, String? fileName) {
    final head = content.trimLeft();
    if (!head.startsWith('<')) return false;
    // Test textuel avant de payer un parsing complet.
    return head.contains('KeePassFile') || head.contains('<Root>');
  }

  @override
  ParsedImport parse(String content) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(content);
    } on XmlException catch (e) {
      throw ImportFormatException('XML illisible : ${e.message}');
    }

    final root = doc.findAllElements('Root').firstOrNull;
    if (root == null) {
      throw const ImportFormatException(
        'Élément « Root » absent : ce fichier n’est pas un export KeePass XML.',
      );
    }

    final items = <CipherItem>[];
    final skipped = <String>[];
    final folders = <String>{};

    // Les groupes de premier niveau portent souvent le nom de la base
    // (« Database », « NewDatabase ») : on ne le garde pas comme dossier.
    for (final group in root.findElements('Group')) {
      _walk(group, const [], 0, items, skipped, folders);
    }
    // Entrées posées directement sous Root, sans groupe.
    _entriesOf(root, null, items, skipped);

    return requireSomething(
      label,
      items,
      skipped,
      folderNames: folders.toList(growable: false),
    );
  }

  /// `depth` compte les groupes traversés. Il est indispensable : tester
  /// `path.isEmpty` pour reconnaître la racine faisait perdre son nom à tout
  /// groupe dont le parent était lui-même à la racine.
  void _walk(
    XmlElement group,
    List<String> path,
    int depth,
    List<CipherItem> items,
    List<String> skipped,
    Set<String> folders,
  ) {
    final name = group.findElements('Name').firstOrNull?.innerText.trim() ?? '';

    // On ne réimporte pas ce que l'utilisateur avait jeté.
    const bins = {'recycle bin', 'corbeille', 'trash'};
    if (bins.contains(name.toLowerCase())) return;

    // Le groupe de premier niveau porte le nom de la base, pas un dossier.
    final nextPath = depth == 0
        ? const <String>[]
        : [...path, if (name.isNotEmpty) name];

    final folderName = nextPath.isEmpty ? null : nextPath.join(' / ');
    if (folderName != null) folders.add(folderName);

    _entriesOf(group, folderName, items, skipped);

    for (final child in group.findElements('Group')) {
      _walk(child, nextPath, depth + 1, items, skipped, folders);
    }
  }

  void _entriesOf(
    XmlElement parent,
    String? folderName,
    List<CipherItem> items,
    List<String> skipped,
  ) {
    for (final entry in parent.findElements('Entry')) {
      try {
        final item = _toItem(entry, folderName);
        if (item != null) items.add(item);
      } catch (e) {
        skipped.add('entrée « ${_titleOf(entry)} » : $e');
      }
    }
  }

  String _titleOf(XmlElement entry) {
    for (final field in entry.findElements('String')) {
      if (field.findElements('Key').firstOrNull?.innerText == 'Title') {
        return field.findElements('Value').firstOrNull?.innerText ?? 'sans titre';
      }
    }
    return 'sans titre';
  }

  CipherItem? _toItem(XmlElement entry, String? folderName) {
    final standard = <String, String>{};
    final custom = <CustomField>[];

    for (final field in entry.findElements('String')) {
      final key = field.findElements('Key').firstOrNull?.innerText.trim() ?? '';
      final valueNode = field.findElements('Value').firstOrNull;
      final value = valueNode?.innerText ?? '';
      if (key.isEmpty) continue;

      switch (key) {
        case 'Title' || 'UserName' || 'Password' || 'URL' || 'Notes':
          standard[key] = value;
        case 'otp' || 'TOTP Seed' || 'TOTP' || 'otpauth':
          standard['TOTP'] = value;
        default:
          if (value.trim().isEmpty) break;
          // `ProtectedInMemory` marque les champs que KeePass masque : on
          // conserve cette intention.
          final protected =
              valueNode?.getAttribute('ProtectedInMemory')?.toLowerCase() ==
                  'true';
          custom.add(CustomField(
            name: key,
            value: value,
            type: protected ? CustomFieldType.hidden : CustomFieldType.text,
          ));
      }
    }

    final title = standard['Title']?.trim() ?? '';
    final username = standard['UserName']?.trim() ?? '';
    final password = standard['Password'] ?? '';
    final url = standard['URL']?.trim() ?? '';

    if (title.isEmpty && username.isEmpty && password.isEmpty && url.isEmpty) {
      return null;
    }

    return CipherItem(
      folderId: folderName,
      data: LoginData(
        name: title.isNotEmpty
            ? title
            : (urisFrom([url]).firstOrNull?.host ?? username),
        username: username,
        password: password,
        totp: standard['TOTP']?.trim() ?? '',
        notes: standard['Notes'] ?? '',
        uris: urisFrom([url]),
        fields: custom,
        // KeePass porte une date de modification, mais elle couvre l'entrée
        // entière, pas le mot de passe. On ne la détourne pas.
        passwordUpdatedAt: null,
      ),
    );
  }
}
