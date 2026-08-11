import '../models/cipher.dart';
import 'csv_table.dart';
import 'import_result.dart';

/// Import CSV générique.
///
/// Un seul parseur plutôt qu'un par gestionnaire : tous exportent les mêmes
/// colonnes sous des noms différents. On fait donc de la correspondance de
/// libellés, ce qui couvre du même coup les variantes régionales et les
/// nouveaux venus non listés.
///
/// Formats vérifiés par les tests : Chrome, Firefox, LastPass, 1Password,
/// KeePassXC, Dashlane, Safari.
class CsvImporter extends VaultImporter {
  const CsvImporter();

  @override
  String get label => 'CSV';

  @override
  List<String> get extensions => const ['csv', 'txt', 'tsv'];

  /// Libellés reconnus par rôle, en minuscules. L'ordre compte : le premier
  /// trouvé gagne.
  static const _aliases = <String, List<String>>{
    'name': [
      'name', 'title', 'account', 'item name', 'nom', 'display name', 'entry',
    ],
    'url': [
      'url', 'urls', 'website', 'web site', 'login_uri', 'site', 'uri',
      'login uri', 'adresse',
    ],
    'username': [
      'username', 'login_username', 'user name', 'login', 'user', 'email',
      'e-mail', 'identifiant', "nom d'utilisateur", 'login name',
    ],
    'password': [
      'password', 'login_password', 'pass', 'mot de passe', 'motdepasse',
    ],
    'notes': [
      'notes', 'note', 'extra', 'comments', 'comment', 'commentaire',
    ],
    'totp': [
      'totp', 'otpauth', 'login_totp', 'otp secret', 'otpsecret', 'two factor',
      'otp', 'login_totp_secret',
    ],
    'folder': [
      'folder', 'grouping', 'group', 'category', 'collection', 'dossier',
      'groupe',
    ],
    'favorite': ['favorite', 'fav', 'favourite', 'favori'],
  };

  /// Signatures d'en-tête permettant de nommer la source dans le récapitulatif.
  /// Purement informatif : le mappage ne dépend pas de cette reconnaissance.
  static const _signatures = <String, List<String>>{
    'Chrome / Edge': ['name', 'url', 'username', 'password'],
    'Firefox': ['url', 'username', 'password', 'httprealm'],
    'LastPass': ['url', 'username', 'password', 'extra', 'grouping'],
    '1Password': ['title', 'url', 'username', 'password', 'otpauth'],
    'KeePassXC': ['group', 'title', 'username', 'password', 'url'],
    'Dashlane': ['title', 'password', 'note', 'category'],
  };

  @override
  bool canParse(String content, String? fileName) {
    if (content.trim().isEmpty) return false;
    final trimmed = content.trimLeft();
    // Écarte le JSON, qui a ses propres importateurs.
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) return false;
    if (trimmed.startsWith('<')) return false;

    final table = CsvTable.parseAuto(content);
    if (table.isEmpty) return false;
    final columns = table.columns;
    if (columns.isEmpty) return false;

    // Il faut au minimum de quoi reconstituer un identifiant.
    final hasPassword = _indexOf(columns, 'password') != null;
    final hasIdentity = _indexOf(columns, 'name') != null ||
        _indexOf(columns, 'url') != null ||
        _indexOf(columns, 'username') != null;
    return hasPassword && hasIdentity;
  }

  @override
  ParsedImport parse(String content) {
    if (content.trim().isEmpty) {
      throw const ImportFormatException('Fichier CSV vide');
    }

    final table = CsvTable.parseAuto(content);
    final columns = table.columns;

    if (columns.isEmpty) {
      throw const ImportFormatException(
        'Aucune ligne d’en-tête reconnue. PassVault a besoin des noms de '
        'colonnes pour savoir où sont l’identifiant et le mot de passe.',
      );
    }

    final iName = _indexOf(columns, 'name');
    final iUrl = _indexOf(columns, 'url');
    final iUser = _indexOf(columns, 'username');
    final iPass = _indexOf(columns, 'password');
    final iNotes = _indexOf(columns, 'notes');
    final iTotp = _indexOf(columns, 'totp');
    final iFolder = _indexOf(columns, 'folder');
    final iFav = _indexOf(columns, 'favorite');

    if (iPass == null) {
      throw const ImportFormatException(
        'Aucune colonne de mot de passe trouvée dans l’en-tête.',
      );
    }

    final items = <CipherItem>[];
    final skipped = <String>[];
    final folders = <String>{};
    final body = table.body;
    // +2 : une ligne d'en-tête, et un numéro de ligne qui commence à 1.
    final lineOffset = table.header == null ? 1 : 2;

    for (var i = 0; i < body.length; i++) {
      final row = body[i];
      String cell(int? index) {
        if (index == null || index >= row.length) return '';
        return row[index].trim();
      }

      final url = cell(iUrl);
      final username = cell(iUser);
      final password = cell(iPass);
      var name = cell(iName);

      if (name.isEmpty) {
        // Chrome et Firefox n'ont pas toujours de colonne de nom : on retombe
        // sur l'hôte, qui est le repère naturel.
        final host = urisFrom([url]).firstOrNull?.host;
        name = host ?? username;
      }

      if (name.isEmpty && username.isEmpty && password.isEmpty) {
        skipped.add('ligne ${i + lineOffset} : ni nom, ni identifiant, ni '
            'mot de passe');
        continue;
      }

      final folder = cell(iFolder);
      if (folder.isNotEmpty) folders.add(folder);

      final favRaw = cell(iFav).toLowerCase();
      final favorite = favRaw == '1' || favRaw == 'true' || favRaw == 'yes' ||
          favRaw == 'oui';

      items.add(CipherItem(
        folderId: folder.isEmpty ? null : folder,
        favorite: favorite,
        data: LoginData(
          name: name.isEmpty ? 'Sans nom' : name,
          username: username,
          password: password,
          totp: cell(iTotp),
          notes: cell(iNotes),
          uris: urisFrom([url]),
          // Aucun export CSV ne donne la date du dernier changement.
          passwordUpdatedAt: null,
        ),
      ));
    }

    return requireSomething(
      _labelFor(columns),
      items,
      skipped,
      folderNames: folders.toList(growable: false),
    );
  }

  static int? _indexOf(Map<String, int> columns, String role) {
    for (final alias in _aliases[role]!) {
      final index = columns[alias];
      if (index != null) return index;
    }
    return null;
  }

  /// Retient la signature la plus spécifique, pas la première trouvée.
  ///
  /// Celle de Chrome (`name,url,username,password`) est un sous-ensemble de
  /// celle de LastPass, qui ajoute `extra` et `grouping` : à parcourir dans
  /// l'ordre de déclaration, tout export LastPass serait étiqueté « Chrome ».
  String _labelFor(Map<String, int> columns) {
    String? best;
    var bestLength = 0;
    for (final entry in _signatures.entries) {
      if (entry.value.length > bestLength &&
          entry.value.every(columns.containsKey)) {
        best = entry.key;
        bestLength = entry.value.length;
      }
    }
    return best == null ? 'CSV générique' : 'CSV $best';
  }
}
