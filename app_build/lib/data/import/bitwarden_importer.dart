import 'dart:convert';

import '../models/cipher.dart';
import 'import_result.dart';

/// Import d'un export Bitwarden JSON **non chiffré**.
///
/// Le format est stable et couvre les mêmes quatre types d'éléments que
/// PassVault, donc c'est le chemin de migration qui perd le moins d'information :
/// URIs multiples, TOTP, champs personnalisés, historique des mots de passe et
/// dossiers passent tous.
///
/// Un export Bitwarden *chiffré* n'est pas pris en charge : il faudrait rejouer
/// leur dérivation de clé, et l'utilisateur a de toute façon la possibilité
/// d'exporter en clair depuis leur app.
class BitwardenImporter extends VaultImporter {
  const BitwardenImporter();

  @override
  String get label => 'Bitwarden (JSON)';

  @override
  List<String> get extensions => const ['json'];

  @override
  bool canParse(String content, String? fileName) {
    final trimmed = content.trimLeft();
    if (!trimmed.startsWith('{')) return false;
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return false;
      // La marque du format : une liste `items` dont les entrées portent un
      // `type` numérique. `encrypted` distingue l'export chiffré.
      return decoded.containsKey('items') && decoded['items'] is List;
    } catch (_) {
      return false;
    }
  }

  @override
  ParsedImport parse(String content) {
    final Map<String, dynamic> root;
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        throw const ImportFormatException('Objet JSON attendu à la racine');
      }
      root = decoded;
    } on FormatException catch (e) {
      throw ImportFormatException('JSON illisible : ${e.message}');
    }

    if (root['encrypted'] == true) {
      throw const ImportFormatException(
        'Cet export Bitwarden est chiffré. Réexportez-le en JSON non chiffré '
        'depuis Bitwarden — PassVault le rechiffrera avec votre propre clé.',
      );
    }

    final rawItems = root['items'];
    if (rawItems is! List) {
      throw const ImportFormatException('Champ « items » absent ou invalide');
    }

    // Table des dossiers : Bitwarden référence les éléments par folderId.
    final folderNames = <String, String>{};
    final rawFolders = root['folders'];
    if (rawFolders is List) {
      for (final folder in rawFolders.whereType<Map<String, dynamic>>()) {
        final id = folder['id'];
        final name = folder['name'];
        if (id is String && name is String && name.trim().isNotEmpty) {
          folderNames[id] = name.trim();
        }
      }
    }

    final items = <CipherItem>[];
    final skipped = <String>[];
    // Dossiers réellement utilisés : on ne recrée pas des dossiers vides.
    final usedFolders = <String>{};

    for (var i = 0; i < rawItems.length; i++) {
      final raw = rawItems[i];
      if (raw is! Map<String, dynamic>) {
        skipped.add('élément ${i + 1} : objet attendu');
        continue;
      }
      try {
        final item = _toItem(raw, folderNames);
        if (item == null) {
          skipped.add(
            'élément ${i + 1} : type ${raw['type']} non pris en charge',
          );
          continue;
        }
        items.add(item);
        if (item.folderId != null) usedFolders.add(item.folderId!);
      } catch (e) {
        skipped.add('élément ${i + 1} : $e');
      }
    }

    return requireSomething(
      label,
      items,
      skipped,
      folderNames: usedFolders.toList(growable: false),
    );
  }

  /// `folderId` porte ici le *nom* du dossier, pas son identifiant : le dépôt
  /// créera les dossiers puis résoudra les noms en identifiants réels.
  CipherItem? _toItem(
    Map<String, dynamic> raw,
    Map<String, String> folderNames,
  ) {
    String str(dynamic value) => value == null ? '' : value.toString().trim();

    final name = str(raw['name']);
    final notes = raw['notes'] == null ? '' : raw['notes'].toString();
    final favorite = raw['favorite'] == true;
    // 1 = redemander le mot de passe maître, dans les deux modèles.
    final reprompt = raw['reprompt'] == 1 || raw['reprompt'] == true;
    final folderName = folderNames[raw['folderId']];
    final fields = _fields(raw['fields']);

    final type = raw['type'];
    final CipherData data;

    switch (type) {
      case 1: // identifiant
        final login = raw['login'];
        if (login is! Map<String, dynamic>) {
          data = LoginData(name: name, notes: notes, fields: fields);
          break;
        }
        final rawUris = login['uris'];
        final uris = <LoginUri>[];
        if (rawUris is List) {
          for (final entry in rawUris.whereType<Map<String, dynamic>>()) {
            final uri = str(entry['uri']);
            if (uri.isEmpty) continue;
            uris.add(LoginUri(
              uri: uri,
              match: UriMatchType.fromWire(entry['match'] as int?),
            ));
          }
        }
        data = LoginData(
          name: name,
          username: str(login['username']),
          password: login['password'] == null
              ? ''
              : login['password'].toString(),
          totp: str(login['totp']),
          notes: notes,
          uris: uris,
          fields: fields,
          passwordHistory: _history(raw['passwordHistory']),
          // Bitwarden ne donne pas la date du dernier changement, seulement
          // celles de l'historique. On ne l'invente pas : le rapport de sécurité
          // afficherait sinon des mots de passe anciens comme récents.
          passwordUpdatedAt: null,
        );

      case 2: // note sécurisée
        data = SecureNoteData(name: name, notes: notes, fields: fields);

      case 3: // carte
        final card = raw['card'];
        final m = card is Map<String, dynamic> ? card : const {};
        data = CardData(
          name: name,
          cardholderName: str(m['cardholderName']),
          brand: str(m['brand']),
          number: str(m['number']),
          expMonth: str(m['expMonth']),
          expYear: str(m['expYear']),
          code: str(m['code']),
          notes: notes,
          fields: fields,
        );

      case 4: // identité
        final id = raw['identity'];
        final m = id is Map<String, dynamic> ? id : const {};
        data = IdentityData(
          name: name,
          title: str(m['title']),
          firstName: str(m['firstName']),
          middleName: str(m['middleName']),
          lastName: str(m['lastName']),
          company: str(m['company']),
          email: str(m['email']),
          phone: str(m['phone']),
          username: str(m['username']),
          ssn: str(m['ssn']),
          passportNumber: str(m['passportNumber']),
          licenseNumber: str(m['licenseNumber']),
          address1: str(m['address1']),
          address2: str(m['address2']),
          city: str(m['city']),
          state: str(m['state']),
          postalCode: str(m['postalCode']),
          country: str(m['country']),
          notes: notes,
          fields: fields,
        );

      default:
        return null;
    }

    return CipherItem(
      data: data,
      favorite: favorite,
      reprompt: reprompt,
      folderId: folderName,
    );
  }

  List<CustomField> _fields(dynamic raw) {
    if (raw is! List) return const [];
    final out = <CustomField>[];
    for (final entry in raw.whereType<Map<String, dynamic>>()) {
      final name = entry['name']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      out.add(CustomField(
        name: name,
        value: entry['value']?.toString() ?? '',
        type: CustomFieldType.fromWire(entry['type'] as int?),
      ));
    }
    return out;
  }

  List<PasswordHistoryEntry> _history(dynamic raw) {
    if (raw is! List) return const [];
    final out = <PasswordHistoryEntry>[];
    for (final entry in raw.whereType<Map<String, dynamic>>()) {
      final password = entry['password']?.toString() ?? '';
      if (password.isEmpty) continue;
      out.add(PasswordHistoryEntry(
        password: password,
        replacedAt:
            DateTime.tryParse(entry['lastUsedDate']?.toString() ?? '')?.toUtc() ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      ));
    }
    return out;
  }
}
