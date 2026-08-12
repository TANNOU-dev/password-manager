import 'bitwarden_importer.dart';
import 'csv_importer.dart';
import 'import_result.dart';
import 'keepass_xml_importer.dart';
import 'v1_importer.dart';

export 'bitwarden_importer.dart';
export 'csv_importer.dart';
export 'import_result.dart';
export 'keepass_xml_importer.dart';
export 'v1_importer.dart';

/// Registre des formats reconnus.
///
/// L'ordre est significatif : du plus spécifique au plus général. `CsvImporter`
/// accepterait le CSV de la v1, donc il passe en dernier ; sinon on perdrait
/// l'étiquette exacte du format d'origine dans le récapitulatif.
const List<VaultImporter> allImporters = [
  BitwardenImporter(),
  V1JsonImporter(),
  KeepassXmlImporter(),
  V1CsvImporter(),
  CsvImporter(),
];

/// Choisit l'importateur d'un contenu, ou `null` si aucun ne le reconnaît.
///
/// La détection porte sur le contenu, pas sur l'extension : les gens renomment
/// leurs fichiers, et un `.txt` peut très bien contenir du CSV.
VaultImporter? detectImporter(String content, {String? fileName}) {
  for (final importer in allImporters) {
    try {
      if (importer.canParse(content, fileName)) return importer;
    } catch (_) {
      // Un importateur qui échoue à se prononcer ne doit pas bloquer les
      // suivants.
      continue;
    }
  }
  return null;
}

/// Détecte puis parse. Lève `ImportFormatException` si aucun format ne colle.
ParsedImport parseImport(String content, {String? fileName}) {
  if (content.trim().isEmpty) {
    throw const ImportFormatException('Le fichier est vide.');
  }
  final importer = detectImporter(content, fileName: fileName);
  if (importer == null) {
    throw const ImportFormatException(
      'Format non reconnu. Coffort lit les exports Bitwarden (JSON), '
      'KeePass (XML) et les CSV de Chrome, Firefox, LastPass, 1Password, '
      'KeePassXC et Dashlane.',
    );
  }
  return importer.parse(content);
}

/// Extensions à proposer au sélecteur de fichiers.
List<String> get importExtensions {
  final all = <String>{};
  for (final importer in allImporters) {
    all.addAll(importer.extensions);
  }
  return all.toList(growable: false);
}
