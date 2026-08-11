import 'dart:convert';

/// Modèle des éléments du coffre.
///
/// Tout ce qui est dans `CipherData` finit dans un unique blob chiffré. Seuls le
/// type, le dossier et les deux drapeaux restent en clair, parce que le serveur
/// doit pouvoir synchroniser et filtrer sans rien comprendre du contenu.

enum CipherType {
  login(1, 'Identifiant'),
  secureNote(2, 'Note sécurisée'),
  card(3, 'Carte bancaire'),
  identity(4, 'Identité');

  const CipherType(this.wire, this.label);
  final int wire;
  final String label;

  static CipherType fromWire(int value) {
    return CipherType.values.firstWhere(
      (t) => t.wire == value,
      orElse: () => throw ArgumentError('type d’élément inconnu : $value'),
    );
  }
}

enum CustomFieldType {
  text(0, 'Texte'),
  hidden(1, 'Masqué'),
  boolean(2, 'Oui / non');

  const CustomFieldType(this.wire, this.label);
  final int wire;
  final String label;

  static CustomFieldType fromWire(int? value) {
    return CustomFieldType.values.firstWhere(
      (t) => t.wire == value,
      orElse: () => CustomFieldType.text,
    );
  }
}

class CustomField {
  final String name;
  final String value;
  final CustomFieldType type;

  const CustomField({
    required this.name,
    required this.value,
    this.type = CustomFieldType.text,
  });

  factory CustomField.fromJson(Map<String, dynamic> json) => CustomField(
        name: (json['name'] ?? '') as String,
        value: (json['value'] ?? '') as String,
        type: CustomFieldType.fromWire(json['type'] as int?),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
        'type': type.wire,
      };

  CustomField copyWith({String? name, String? value, CustomFieldType? type}) =>
      CustomField(
        name: name ?? this.name,
        value: value ?? this.value,
        type: type ?? this.type,
      );
}

/// Règle d'association entre une URI enregistrée et la page visitée. Sert à
/// l'autofill : c'est elle qui décide si un identifiant est proposé ou non.
enum UriMatchType {
  domain(0, 'Domaine de base'),
  host(1, 'Hôte exact'),
  startsWith(2, 'Commence par'),
  exact(3, 'URL exacte'),
  never(4, 'Jamais');

  const UriMatchType(this.wire, this.label);
  final int wire;
  final String label;

  static UriMatchType fromWire(int? value) {
    return UriMatchType.values.firstWhere(
      (t) => t.wire == value,
      orElse: () => UriMatchType.domain,
    );
  }
}

class LoginUri {
  final String uri;
  final UriMatchType match;

  const LoginUri({required this.uri, this.match = UriMatchType.domain});

  factory LoginUri.fromJson(Map<String, dynamic> json) => LoginUri(
        uri: (json['uri'] ?? '') as String,
        match: UriMatchType.fromWire(json['match'] as int?),
      );

  Map<String, dynamic> toJson() => {'uri': uri, 'match': match.wire};

  /// Hôte extrait de l'URI, pour l'affichage et la pastille monogramme.
  /// Tolère une saisie sans schéma, cas courant quand on tape « github.com ».
  String? get host {
    final raw = uri.trim();
    if (raw.isEmpty) return null;
    final candidate = raw.contains('://') ? raw : 'https://$raw';
    final parsed = Uri.tryParse(candidate);
    final host = parsed?.host;
    if (host == null || host.isEmpty) return null;
    return host.startsWith('www.') ? host.substring(4) : host;
  }
}

class PasswordHistoryEntry {
  final String password;
  final DateTime replacedAt;

  const PasswordHistoryEntry({required this.password, required this.replacedAt});

  factory PasswordHistoryEntry.fromJson(Map<String, dynamic> json) =>
      PasswordHistoryEntry(
        password: (json['password'] ?? '') as String,
        replacedAt:
            DateTime.tryParse((json['replacedAt'] ?? '') as String)?.toUtc() ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

  Map<String, dynamic> toJson() => {
        'password': password,
        'replacedAt': replacedAt.toUtc().toIso8601String(),
      };
}

/// Contenu déchiffré d'un élément. Une variante par type.
sealed class CipherData {
  const CipherData();

  /// Libellé affiché dans la liste.
  String get name;

  String get notes;

  List<CustomField> get fields;

  CipherType get type;

  Map<String, dynamic> toJson();

  /// Texte sur lequel porte la recherche. Construit après déchiffrement, en
  /// mémoire uniquement — le serveur ne peut pas chercher dans un coffre opaque.
  String get searchHaystack;

  static CipherData fromJson(CipherType type, Map<String, dynamic> json) {
    return switch (type) {
      CipherType.login => LoginData.fromJson(json),
      CipherType.secureNote => SecureNoteData.fromJson(json),
      CipherType.card => CardData.fromJson(json),
      CipherType.identity => IdentityData.fromJson(json),
    };
  }

  static List<CustomField> _fieldsOf(Map<String, dynamic> json) {
    final raw = json['fields'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(CustomField.fromJson)
        .toList(growable: false);
  }
}

class LoginData extends CipherData {
  @override
  final String name;
  final String username;
  final String password;
  final List<LoginUri> uris;

  /// Secret TOTP en base32, ou URI `otpauth://`. Chiffré comme le reste.
  final String totp;

  @override
  final String notes;
  @override
  final List<CustomField> fields;

  /// Anciens mots de passe, du plus récent au plus ancien.
  final List<PasswordHistoryEntry> passwordHistory;

  /// Date du dernier changement de mot de passe. Alimente le rapport de
  /// sécurité (« mot de passe ancien »).
  final DateTime? passwordUpdatedAt;

  const LoginData({
    required this.name,
    this.username = '',
    this.password = '',
    this.uris = const [],
    this.totp = '',
    this.notes = '',
    this.fields = const [],
    this.passwordHistory = const [],
    this.passwordUpdatedAt,
  });

  @override
  CipherType get type => CipherType.login;

  bool get hasTotp => totp.trim().isNotEmpty;

  /// Hôte principal, pour l'icône et le regroupement.
  String? get primaryHost {
    for (final u in uris) {
      final h = u.host;
      if (h != null) return h;
    }
    return null;
  }

  factory LoginData.fromJson(Map<String, dynamic> json) {
    final rawUris = json['uris'];
    final rawHistory = json['passwordHistory'];
    return LoginData(
      name: (json['name'] ?? '') as String,
      username: (json['username'] ?? '') as String,
      password: (json['password'] ?? '') as String,
      uris: rawUris is List
          ? rawUris
              .whereType<Map<String, dynamic>>()
              .map(LoginUri.fromJson)
              .toList(growable: false)
          : const [],
      totp: (json['totp'] ?? '') as String,
      notes: (json['notes'] ?? '') as String,
      fields: CipherData._fieldsOf(json),
      passwordHistory: rawHistory is List
          ? rawHistory
              .whereType<Map<String, dynamic>>()
              .map(PasswordHistoryEntry.fromJson)
              .toList(growable: false)
          : const [],
      passwordUpdatedAt:
          DateTime.tryParse((json['passwordUpdatedAt'] ?? '') as String)?.toUtc(),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'name': name,
        'username': username,
        'password': password,
        'uris': uris.map((u) => u.toJson()).toList(),
        'totp': totp,
        'notes': notes,
        'fields': fields.map((f) => f.toJson()).toList(),
        'passwordHistory': passwordHistory.map((h) => h.toJson()).toList(),
        if (passwordUpdatedAt != null)
          'passwordUpdatedAt': passwordUpdatedAt!.toUtc().toIso8601String(),
      };

  @override
  String get searchHaystack => [
        name,
        username,
        notes,
        ...uris.map((u) => u.uri),
        ...fields.where((f) => f.type != CustomFieldType.hidden).map((f) => f.name),
      ].join(' ').toLowerCase();

  /// Remplace le mot de passe en poussant l'ancien dans l'historique.
  /// L'historique est plafonné : il n'a pas vocation à grossir sans fin.
  LoginData withNewPassword(String next, {int historyLimit = 20}) {
    if (next == password) return this;
    final history = <PasswordHistoryEntry>[
      if (password.isNotEmpty)
        PasswordHistoryEntry(password: password, replacedAt: DateTime.now().toUtc()),
      ...passwordHistory,
    ];
    return copyWith(
      password: next,
      passwordHistory: history.take(historyLimit).toList(growable: false),
      passwordUpdatedAt: DateTime.now().toUtc(),
    );
  }

  LoginData copyWith({
    String? name,
    String? username,
    String? password,
    List<LoginUri>? uris,
    String? totp,
    String? notes,
    List<CustomField>? fields,
    List<PasswordHistoryEntry>? passwordHistory,
    DateTime? passwordUpdatedAt,
  }) =>
      LoginData(
        name: name ?? this.name,
        username: username ?? this.username,
        password: password ?? this.password,
        uris: uris ?? this.uris,
        totp: totp ?? this.totp,
        notes: notes ?? this.notes,
        fields: fields ?? this.fields,
        passwordHistory: passwordHistory ?? this.passwordHistory,
        passwordUpdatedAt: passwordUpdatedAt ?? this.passwordUpdatedAt,
      );
}

class SecureNoteData extends CipherData {
  @override
  final String name;
  @override
  final String notes;
  @override
  final List<CustomField> fields;

  const SecureNoteData({
    required this.name,
    this.notes = '',
    this.fields = const [],
  });

  @override
  CipherType get type => CipherType.secureNote;

  factory SecureNoteData.fromJson(Map<String, dynamic> json) => SecureNoteData(
        name: (json['name'] ?? '') as String,
        notes: (json['notes'] ?? '') as String,
        fields: CipherData._fieldsOf(json),
      );

  @override
  Map<String, dynamic> toJson() => {
        'name': name,
        'notes': notes,
        'fields': fields.map((f) => f.toJson()).toList(),
      };

  @override
  String get searchHaystack => '$name $notes'.toLowerCase();

  SecureNoteData copyWith({
    String? name,
    String? notes,
    List<CustomField>? fields,
  }) =>
      SecureNoteData(
        name: name ?? this.name,
        notes: notes ?? this.notes,
        fields: fields ?? this.fields,
      );
}

class CardData extends CipherData {
  @override
  final String name;
  final String cardholderName;
  final String brand;
  final String number;
  final String expMonth;
  final String expYear;
  final String code;
  @override
  final String notes;
  @override
  final List<CustomField> fields;

  const CardData({
    required this.name,
    this.cardholderName = '',
    this.brand = '',
    this.number = '',
    this.expMonth = '',
    this.expYear = '',
    this.code = '',
    this.notes = '',
    this.fields = const [],
  });

  @override
  CipherType get type => CipherType.card;

  /// Quatre derniers chiffres, pour identifier la carte sans l'exposer.
  String get last4 {
    final digits = number.replaceAll(RegExp(r'\D'), '');
    return digits.length <= 4 ? digits : digits.substring(digits.length - 4);
  }

  /// Réseau déduit du numéro quand l'utilisateur n'a rien saisi. Les préfixes
  /// suffisent pour les cartes courantes.
  String get inferredBrand {
    if (brand.isNotEmpty) return brand;
    final d = number.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('4')) return 'Visa';
    if (RegExp(r'^5[1-5]').hasMatch(d) || RegExp(r'^2[2-7]').hasMatch(d)) {
      return 'Mastercard';
    }
    if (RegExp(r'^3[47]').hasMatch(d)) return 'American Express';
    if (d.startsWith('6')) return 'Discover';
    return '';
  }

  String get expiry {
    if (expMonth.isEmpty && expYear.isEmpty) return '';
    final m = expMonth.padLeft(2, '0');
    final y = expYear.length == 4 ? expYear.substring(2) : expYear;
    return '$m/$y';
  }

  factory CardData.fromJson(Map<String, dynamic> json) => CardData(
        name: (json['name'] ?? '') as String,
        cardholderName: (json['cardholderName'] ?? '') as String,
        brand: (json['brand'] ?? '') as String,
        number: (json['number'] ?? '') as String,
        expMonth: (json['expMonth'] ?? '') as String,
        expYear: (json['expYear'] ?? '') as String,
        code: (json['code'] ?? '') as String,
        notes: (json['notes'] ?? '') as String,
        fields: CipherData._fieldsOf(json),
      );

  @override
  Map<String, dynamic> toJson() => {
        'name': name,
        'cardholderName': cardholderName,
        'brand': brand,
        'number': number,
        'expMonth': expMonth,
        'expYear': expYear,
        'code': code,
        'notes': notes,
        'fields': fields.map((f) => f.toJson()).toList(),
      };

  // Ni le numéro ni le code ne rentrent dans l'index de recherche : on ne veut
  // pas qu'une frappe partielle dans la barre de recherche révèle une carte.
  @override
  String get searchHaystack =>
      '$name $cardholderName $brand $notes'.toLowerCase();

  CardData copyWith({
    String? name,
    String? cardholderName,
    String? brand,
    String? number,
    String? expMonth,
    String? expYear,
    String? code,
    String? notes,
    List<CustomField>? fields,
  }) =>
      CardData(
        name: name ?? this.name,
        cardholderName: cardholderName ?? this.cardholderName,
        brand: brand ?? this.brand,
        number: number ?? this.number,
        expMonth: expMonth ?? this.expMonth,
        expYear: expYear ?? this.expYear,
        code: code ?? this.code,
        notes: notes ?? this.notes,
        fields: fields ?? this.fields,
      );
}

class IdentityData extends CipherData {
  @override
  final String name;
  final String title;
  final String firstName;
  final String middleName;
  final String lastName;
  final String email;
  final String phone;
  final String company;
  final String username;
  final String ssn;
  final String passportNumber;
  final String licenseNumber;
  final String address1;
  final String address2;
  final String city;
  final String state;
  final String postalCode;
  final String country;
  @override
  final String notes;
  @override
  final List<CustomField> fields;

  const IdentityData({
    required this.name,
    this.title = '',
    this.firstName = '',
    this.middleName = '',
    this.lastName = '',
    this.email = '',
    this.phone = '',
    this.company = '',
    this.username = '',
    this.ssn = '',
    this.passportNumber = '',
    this.licenseNumber = '',
    this.address1 = '',
    this.address2 = '',
    this.city = '',
    this.state = '',
    this.postalCode = '',
    this.country = '',
    this.notes = '',
    this.fields = const [],
  });

  @override
  CipherType get type => CipherType.identity;

  String get fullName =>
      [title, firstName, middleName, lastName].where((s) => s.isNotEmpty).join(' ');

  factory IdentityData.fromJson(Map<String, dynamic> json) {
    String s(String key) => (json[key] ?? '') as String;
    return IdentityData(
      name: s('name'),
      title: s('title'),
      firstName: s('firstName'),
      middleName: s('middleName'),
      lastName: s('lastName'),
      email: s('email'),
      phone: s('phone'),
      company: s('company'),
      username: s('username'),
      ssn: s('ssn'),
      passportNumber: s('passportNumber'),
      licenseNumber: s('licenseNumber'),
      address1: s('address1'),
      address2: s('address2'),
      city: s('city'),
      state: s('state'),
      postalCode: s('postalCode'),
      country: s('country'),
      notes: s('notes'),
      fields: CipherData._fieldsOf(json),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'name': name,
        'title': title,
        'firstName': firstName,
        'middleName': middleName,
        'lastName': lastName,
        'email': email,
        'phone': phone,
        'company': company,
        'username': username,
        'ssn': ssn,
        'passportNumber': passportNumber,
        'licenseNumber': licenseNumber,
        'address1': address1,
        'address2': address2,
        'city': city,
        'state': state,
        'postalCode': postalCode,
        'country': country,
        'notes': notes,
        'fields': fields.map((f) => f.toJson()).toList(),
      };

  // Ni numéro de sécurité sociale, ni passeport, ni permis dans l'index.
  @override
  String get searchHaystack =>
      '$name $fullName $email $phone $company $username $city $country'
          .toLowerCase();

  IdentityData copyWith({
    String? name,
    String? title,
    String? firstName,
    String? middleName,
    String? lastName,
    String? email,
    String? phone,
    String? company,
    String? username,
    String? ssn,
    String? passportNumber,
    String? licenseNumber,
    String? address1,
    String? address2,
    String? city,
    String? state,
    String? postalCode,
    String? country,
    String? notes,
    List<CustomField>? fields,
  }) =>
      IdentityData(
        name: name ?? this.name,
        title: title ?? this.title,
        firstName: firstName ?? this.firstName,
        middleName: middleName ?? this.middleName,
        lastName: lastName ?? this.lastName,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        company: company ?? this.company,
        username: username ?? this.username,
        ssn: ssn ?? this.ssn,
        passportNumber: passportNumber ?? this.passportNumber,
        licenseNumber: licenseNumber ?? this.licenseNumber,
        address1: address1 ?? this.address1,
        address2: address2 ?? this.address2,
        city: city ?? this.city,
        state: state ?? this.state,
        postalCode: postalCode ?? this.postalCode,
        country: country ?? this.country,
        notes: notes ?? this.notes,
        fields: fields ?? this.fields,
      );
}

/// Un élément du coffre, une fois déchiffré. `id` est nul tant qu'il n'a pas été
/// envoyé au serveur.
class CipherItem {
  final String? id;
  final String? folderId;
  final bool favorite;

  /// Redemander le mot de passe maître avant de révéler le contenu.
  final bool reprompt;

  final CipherData data;
  final DateTime? createdAt;
  final DateTime? revisionDate;
  final DateTime? deletedAt;

  const CipherItem({
    this.id,
    this.folderId,
    this.favorite = false,
    this.reprompt = false,
    required this.data,
    this.createdAt,
    this.revisionDate,
    this.deletedAt,
  });

  CipherType get type => data.type;
  bool get isDeleted => deletedAt != null;

  CipherItem copyWith({
    String? id,
    String? folderId,
    bool clearFolder = false,
    bool? favorite,
    bool? reprompt,
    CipherData? data,
    DateTime? createdAt,
    DateTime? revisionDate,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) =>
      CipherItem(
        id: id ?? this.id,
        folderId: clearFolder ? null : (folderId ?? this.folderId),
        favorite: favorite ?? this.favorite,
        reprompt: reprompt ?? this.reprompt,
        data: data ?? this.data,
        createdAt: createdAt ?? this.createdAt,
        revisionDate: revisionDate ?? this.revisionDate,
        deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
      );

  /// Sérialisation du contenu à chiffrer. Volontairement séparée des métadonnées
  /// en clair : ce qui sort d'ici est ce que le serveur ne verra jamais.
  String encodeData() => jsonEncode(data.toJson());
}

/// Dossier. Son nom est chiffré côté client comme le reste.
class FolderItem {
  final String id;
  final String name;
  final DateTime? revisionDate;

  const FolderItem({required this.id, required this.name, this.revisionDate});
}
