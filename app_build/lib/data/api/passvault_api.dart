import '../../core/crypto/kdf_params.dart';
import 'api_client.dart';

/// Réponse de `/api/accounts/prelogin` : ce qu'il faut pour rejouer le KDF.
class PreloginInfo {
  final KdfParams kdf;
  final String kdfSalt;

  const PreloginInfo({required this.kdf, required this.kdfSalt});
}

/// Ce que le serveur sait d'un coffre. `protectedKey` est illisible sans le mot
/// de passe maître.
class VaultProfile {
  final String id;
  final String email;
  final KdfParams kdf;
  final String kdfSalt;
  final String protectedKey;
  final DateTime? createdAt;

  const VaultProfile({
    required this.id,
    required this.email,
    required this.kdf,
    required this.kdfSalt,
    required this.protectedKey,
    this.createdAt,
  });

  factory VaultProfile.fromJson(Map<String, dynamic> json) => VaultProfile(
        id: json['id'] as String,
        email: json['email'] as String,
        kdf: KdfParams.fromJson(json['kdf'] as Map<String, dynamic>),
        kdfSalt: json['kdfSalt'] as String,
        protectedKey: json['protectedKey'] as String,
        createdAt: DateTime.tryParse((json['createdAt'] ?? '') as String),
      );
}

class ServerStatus {
  final int apiVersion;
  final bool zeroKnowledge;
  final bool acceptsRegistration;
  final KdfParams defaultKdf;

  const ServerStatus({
    required this.apiVersion,
    required this.zeroKnowledge,
    required this.acceptsRegistration,
    required this.defaultKdf,
  });
}

class SessionGrant {
  final String token;
  final DateTime expiresAt;
  final VaultProfile profile;

  const SessionGrant({
    required this.token,
    required this.expiresAt,
    required this.profile,
  });

  factory SessionGrant.fromJson(Map<String, dynamic> json) => SessionGrant(
        token: json['token'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        profile: VaultProfile.fromJson(json['profile'] as Map<String, dynamic>),
      );
}

/// Session ouverte sur le compte. Le serveur n'en garde que le sha256 du jeton,
/// donc cette liste décrit des accès sans permettre de les réutiliser.
class VaultSession {
  final String? deviceName;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;
  final DateTime? expiresAt;

  const VaultSession({
    this.deviceName,
    this.createdAt,
    this.lastUsedAt,
    this.expiresAt,
  });

  factory VaultSession.fromJson(Map<String, dynamic> json) => VaultSession(
        deviceName: json['device_name'] as String?,
        createdAt: DateTime.tryParse((json['created_at'] ?? '') as String),
        lastUsedAt: DateTime.tryParse((json['last_used_at'] ?? '') as String),
        expiresAt: DateTime.tryParse((json['expires_at'] ?? '') as String),
      );
}

/// Élément tel qu'il circule : métadonnées en clair, contenu chiffré.
class RemoteCipher {
  final String id;
  final int type;
  final String? folderId;
  final bool favorite;
  final bool reprompt;
  final String data;
  final DateTime? createdAt;
  final DateTime? revisionDate;
  final DateTime? deletedAt;

  const RemoteCipher({
    required this.id,
    required this.type,
    required this.folderId,
    required this.favorite,
    required this.reprompt,
    required this.data,
    this.createdAt,
    this.revisionDate,
    this.deletedAt,
  });

  factory RemoteCipher.fromJson(Map<String, dynamic> json) => RemoteCipher(
        id: json['id'] as String,
        type: json['type'] as int,
        folderId: json['folderId'] as String?,
        favorite: json['favorite'] as bool? ?? false,
        reprompt: json['reprompt'] as bool? ?? false,
        data: json['data'] as String,
        createdAt: DateTime.tryParse((json['createdAt'] ?? '') as String),
        revisionDate: DateTime.tryParse((json['revisionDate'] ?? '') as String),
        deletedAt: DateTime.tryParse((json['deletedAt'] ?? '') as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'folderId': folderId,
        'favorite': favorite,
        'reprompt': reprompt,
        'data': data,
        'createdAt': createdAt?.toIso8601String(),
        'revisionDate': revisionDate?.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
      };
}

class RemoteFolder {
  final String id;
  final String name;
  final DateTime? revisionDate;

  const RemoteFolder({required this.id, required this.name, this.revisionDate});

  factory RemoteFolder.fromJson(Map<String, dynamic> json) => RemoteFolder(
        id: json['id'] as String,
        name: json['name'] as String,
        revisionDate: DateTime.tryParse((json['revisionDate'] ?? '') as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'revisionDate': revisionDate?.toIso8601String(),
      };
}

class SyncPayload {
  final VaultProfile profile;
  final List<RemoteFolder> folders;
  final List<RemoteCipher> ciphers;

  const SyncPayload({
    required this.profile,
    required this.folders,
    required this.ciphers,
  });

  factory SyncPayload.fromJson(Map<String, dynamic> json) => SyncPayload(
        profile: VaultProfile.fromJson(json['profile'] as Map<String, dynamic>),
        folders: (json['folders'] as List)
            .cast<Map<String, dynamic>>()
            .map(RemoteFolder.fromJson)
            .toList(),
        ciphers: (json['ciphers'] as List)
            .cast<Map<String, dynamic>>()
            .map(RemoteCipher.fromJson)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'folders': folders.map((f) => f.toJson()).toList(),
        'ciphers': ciphers.map((c) => c.toJson()).toList(),
      };
}

/// Couche d'appel de l'API. Ne chiffre ni ne déchiffre rien : elle transporte des
/// blobs déjà scellés par `VaultCrypto`.
class PassvaultApi {
  PassvaultApi(this._client);

  final ApiClient _client;

  String get baseUrl => _client.baseUrl;

  // ==================== COMPTE ====================

  Future<ServerStatus> status() async {
    final json = await _client.get('/api/status') as Map<String, dynamic>;
    return ServerStatus(
      apiVersion: json['apiVersion'] as int? ?? 1,
      zeroKnowledge: json['zeroKnowledge'] as bool? ?? false,
      acceptsRegistration: json['acceptsRegistration'] as bool? ?? false,
      defaultKdf: KdfParams.fromJson(json['defaultKdf'] as Map<String, dynamic>),
    );
  }

  Future<PreloginInfo> prelogin(String email) async {
    final json = await _client.post(
      '/api/accounts/prelogin',
      body: {'email': email},
    ) as Map<String, dynamic>;
    return PreloginInfo(
      kdf: KdfParams.fromJson(json['kdf'] as Map<String, dynamic>),
      kdfSalt: json['kdfSalt'] as String,
    );
  }

  Future<SessionGrant> register({
    required String email,
    required String masterPasswordHash,
    required String protectedKey,
    required KdfParams kdf,
    String? deviceName,
    String? registrationToken,
  }) async {
    final json = await _client.post('/api/accounts/register', body: {
      'email': email,
      'masterPasswordHash': masterPasswordHash,
      'protectedKey': protectedKey,
      'kdf': kdf.toJson(),
      'deviceName': ?deviceName,
      'registrationToken': ?registrationToken,
    }) as Map<String, dynamic>;
    return SessionGrant.fromJson(json);
  }

  Future<SessionGrant> login({
    required String email,
    required String masterPasswordHash,
    String? deviceName,
  }) async {
    final json = await _client.post('/api/auth/login', body: {
      'email': email,
      'masterPasswordHash': masterPasswordHash,
      'deviceName': ?deviceName,
    }) as Map<String, dynamic>;
    return SessionGrant.fromJson(json);
  }

  Future<void> logout(String token) => _client.post('/api/auth/logout', token: token);

  Future<List<Map<String, dynamic>>> sessions(String token) async {
    final json = await _client.get('/api/auth/sessions', token: token) as List;
    return json.cast<Map<String, dynamic>>();
  }

  Future<void> revokeOtherSessions(String token) =>
      _client.delete('/api/auth/sessions', token: token);

  Future<void> changeMasterPassword({
    required String token,
    required String currentHash,
    required String newHash,
    required String newProtectedKey,
  }) =>
      _client.post('/api/accounts/password', token: token, body: {
        'masterPasswordHash': currentHash,
        'newMasterPasswordHash': newHash,
        'newProtectedKey': newProtectedKey,
      });

  Future<void> deleteVault({
    required String token,
    required String masterPasswordHash,
  }) =>
      _client.delete('/api/accounts', token: token, body: {
        'masterPasswordHash': masterPasswordHash,
      });

  // ==================== COFFRE ====================

  Future<SyncPayload> sync(String token) async {
    final json = await _client.get('/api/sync', token: token) as Map<String, dynamic>;
    return SyncPayload.fromJson(json);
  }

  Future<RemoteCipher> createCipher(
    String token, {
    required int type,
    required String data,
    String? folderId,
    bool favorite = false,
    bool reprompt = false,
  }) async {
    final json = await _client.post('/api/ciphers', token: token, body: {
      'type': type,
      'data': data,
      'folderId': folderId,
      'favorite': favorite,
      'reprompt': reprompt,
    }) as Map<String, dynamic>;
    return RemoteCipher.fromJson(json);
  }

  Future<RemoteCipher> updateCipher(
    String token,
    String id, {
    required int type,
    required String data,
    String? folderId,
    bool favorite = false,
    bool reprompt = false,
  }) async {
    final json = await _client.put('/api/ciphers/$id', token: token, body: {
      'type': type,
      'data': data,
      'folderId': folderId,
      'favorite': favorite,
      'reprompt': reprompt,
    }) as Map<String, dynamic>;
    return RemoteCipher.fromJson(json);
  }

  Future<void> trashCipher(String token, String id) =>
      _client.delete('/api/ciphers/$id', token: token);

  Future<void> restoreCipher(String token, String id) =>
      _client.put('/api/ciphers/$id/restore', token: token);

  Future<void> purgeCipher(String token, String id) =>
      _client.delete('/api/ciphers/$id/permanent', token: token);

  Future<int> emptyTrash(String token) async {
    final json = await _client.delete('/api/trash', token: token) as Map<String, dynamic>;
    return json['purged'] as int? ?? 0;
  }

  /// Import en lot. Les éléments arrivent déjà chiffrés : c'est le client qui a
  /// lu le fichier source et rechiffré chaque entrée.
  Future<int> importCiphers(
    String token,
    List<Map<String, dynamic>> items,
  ) async {
    final json = await _client.post(
      '/api/ciphers/import',
      token: token,
      body: {'items': items},
    ) as Map<String, dynamic>;
    return json['imported'] as int? ?? 0;
  }

  // ==================== DOSSIERS ====================

  Future<RemoteFolder> createFolder(String token, String encryptedName) async {
    final json = await _client.post(
      '/api/folders',
      token: token,
      body: {'name': encryptedName},
    ) as Map<String, dynamic>;
    return RemoteFolder.fromJson(json);
  }

  Future<RemoteFolder> updateFolder(
    String token,
    String id,
    String encryptedName,
  ) async {
    final json = await _client.put(
      '/api/folders/$id',
      token: token,
      body: {'name': encryptedName},
    ) as Map<String, dynamic>;
    return RemoteFolder.fromJson(json);
  }

  Future<void> deleteFolder(String token, String id) =>
      _client.delete('/api/folders/$id', token: token);
}
