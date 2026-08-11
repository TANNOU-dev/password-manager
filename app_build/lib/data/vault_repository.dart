import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../core/crypto/kdf_params.dart';
import '../core/crypto/vault_crypto.dart';
import 'api/api_client.dart';
import 'api/passvault_api.dart';
import 'import/importers.dart';
import 'models/cipher.dart';

enum VaultStatus {
  /// Aucune session : il faut le mot de passe maître.
  locked,

  /// Dérivation du KDF en cours. Peut durer quelques secondes sur mobile.
  unlocking,

  /// Clé de coffre en mémoire, contenu déchiffré disponible.
  unlocked,
}

/// Un élément qui n'a pas pu être déchiffré. On ne le masque pas : mieux vaut
/// montrer à l'utilisateur qu'une entrée est abîmée que de la faire disparaître
/// silencieusement, comme le faisait la v1.
class UndecryptableCipher {
  final String id;
  final String reason;
  const UndecryptableCipher(this.id, this.reason);
}

/// Détient l'état du coffre pour toute l'app.
///
/// Règle non négociable : la clé de coffre ne vit qu'ici, en mémoire, et
/// `lock()` l'efface. Rien de déchiffré n'est jamais écrit sur le disque.
class VaultRepository extends ChangeNotifier {
  VaultRepository({
    PassvaultApi? api,
    VaultCrypto? crypto,
    this.deviceName,
  })  : _api = api ?? PassvaultApi(ApiClient()),
        _crypto = crypto ?? VaultCrypto();

  final PassvaultApi _api;
  final VaultCrypto _crypto;
  final String? deviceName;

  VaultStatus _status = VaultStatus.locked;
  VaultStatus get status => _status;
  bool get isUnlocked => _status == VaultStatus.unlocked;

  String? _token;
  VaultProfile? _profile;
  VaultProfile? get profile => _profile;

  /// La clé qui ouvre tout. Jamais persistée, jamais transmise.
  VaultKey? _vaultKey;

  List<CipherItem> _items = const [];
  List<FolderItem> _folders = const [];
  List<UndecryptableCipher> _undecryptable = const [];

  /// Éléments actifs, corbeille exclue.
  List<CipherItem> get items =>
      _items.where((i) => !i.isDeleted).toList(growable: false);

  List<CipherItem> get trash =>
      _items.where((i) => i.isDeleted).toList(growable: false);

  List<FolderItem> get folders => _folders;
  List<UndecryptableCipher> get undecryptable => _undecryptable;

  DateTime? _lastSync;
  DateTime? get lastSync => _lastSync;

  String get serverUrl => _api.baseUrl;

  // ==================== OUVERTURE ====================

  Future<ServerStatus> serverStatus() => _api.status();

  /// Crée un coffre : tire une clé de coffre neuve et l'envoie enveloppée.
  Future<void> createVault({
    required String email,
    required String masterPassword,
    KdfParams? kdf,
    String? registrationToken,
  }) async {
    _setStatus(VaultStatus.unlocking);
    try {
      final params = kdf ?? KdfParams.argon2idDefault;

      // Le sel est dérivé de l'e-mail côté serveur, donc /prelogin sert déjà la
      // valeur définitive avant que le compte existe : on dérive une seule fois.
      final pre = await _api.prelogin(email);
      final material = await _crypto.deriveMasterKeyMaterial(
        masterPassword: masterPassword,
        kdfSaltHex: pre.kdfSalt,
        params: params,
      );

      final vaultKey = await _crypto.newVaultKey();
      final protectedKey = await _crypto.wrapVaultKey(
        vaultKey: vaultKey,
        wrapKey: material.wrapKey,
      );

      final grant = await _api.register(
        email: email,
        masterPasswordHash: material.masterPasswordHash,
        protectedKey: protectedKey,
        kdf: params,
        deviceName: deviceName,
        registrationToken: registrationToken,
      );
      _adopt(grant.token, grant.profile, material, vaultKey);

      _items = const [];
      _folders = const [];
      _lastSync = DateTime.now();
      _setStatus(VaultStatus.unlocked);
    } catch (_) {
      _setStatus(VaultStatus.locked);
      rethrow;
    }
  }

  /// Déverrouille : dérive la clé, ouvre une session, déballe la clé de coffre,
  /// puis déchiffre tout le contenu.
  Future<void> unlock({
    required String email,
    required String masterPassword,
  }) async {
    _setStatus(VaultStatus.unlocking);
    try {
      final pre = await _api.prelogin(email);
      final material = await _crypto.deriveMasterKeyMaterial(
        masterPassword: masterPassword,
        kdfSaltHex: pre.kdfSalt,
        params: pre.kdf,
      );

      final SessionGrant grant;
      try {
        grant = await _api.login(
          email: email,
          masterPasswordHash: material.masterPasswordHash,
          deviceName: deviceName,
        );
      } catch (_) {
        material.destroy();
        rethrow;
      }

      // Le serveur a accepté le hash, mais c'est ce déballage qui prouve
      // réellement que le mot de passe est le bon.
      final vaultKey = await _crypto.unwrapVaultKey(
        protectedKey: grant.profile.protectedKey,
        wrapKey: material.wrapKey,
      );

      _adopt(grant.token, grant.profile, material, vaultKey);
      await sync();
      _setStatus(VaultStatus.unlocked);
    } catch (_) {
      _wipe();
      _setStatus(VaultStatus.locked);
      rethrow;
    }
  }

  /// Adopte une session ouverte.
  ///
  /// `material` est effacé immédiatement : une fois la clé de coffre déballée,
  /// la clé d'enveloppe n'a plus d'usage. La garder en mémoire pour toute la
  /// session serait un secret de plus à protéger sans raison — le changement de
  /// mot de passe maître redemande de toute façon le mot de passe actuel et
  /// redérive.
  void _adopt(
    String token,
    VaultProfile profile,
    MasterKeyMaterial material,
    VaultKey vaultKey,
  ) {
    _token = token;
    _profile = profile;
    _vaultKey?.destroy();
    _vaultKey = vaultKey;
    material.destroy();
  }

  /// Rouvre le coffre depuis une clé et un jeton déjà en main, sans mot de passe
  /// maître ni dérivation Argon2id.
  ///
  /// Utilisé par le déverrouillage biométrique. La vérification que ces valeurs
  /// sont bonnes est faite par le serveur (le jeton) et par AES-GCM (la clé) :
  /// si l'une des deux est fausse, `sync()` échoue ou tous les éléments
  /// remontent illisibles, et on relance l'exception plutôt que d'afficher un
  /// coffre vide.
  Future<void> unlockWithStoredKey({
    required String sessionToken,
    required Uint8List vaultKeyBytes,
  }) async {
    if (vaultKeyBytes.length != 32) {
      throw const VaultDataCorruptException(
        'la clé restaurée ne fait pas 32 octets',
      );
    }

    _setStatus(VaultStatus.unlocking);
    try {
      _token = sessionToken;
      _vaultKey?.destroy();
      _vaultKey = VaultKey(
        SecretKeyData(vaultKeyBytes, overwriteWhenDestroyed: true),
      );

      await sync();

      // Un coffre non vide dont *rien* ne se déchiffre signale une mauvaise clé,
      // pas des données abîmées. Mieux vaut retomber sur le mot de passe maître
      // que présenter un coffre en ruine.
      if (_items.isEmpty && _undecryptable.isNotEmpty) {
        throw const WrongMasterPasswordException();
      }

      _setStatus(VaultStatus.unlocked);
    } catch (_) {
      _wipe();
      _setStatus(VaultStatus.locked);
      rethrow;
    }
  }

  /// Copie des octets de la clé de coffre, pour les confier au trousseau du
  /// système lors de l'activation du déverrouillage biométrique.
  ///
  /// Volontairement explicite : c'est le seul endroit d'où la clé sort de ce
  /// dépôt, et l'appelant doit assumer de la stocker correctement.
  Uint8List exportVaultKeyForBiometricStorage() {
    return Uint8List.fromList(_requireKey().key.bytes);
  }

  /// Jeton de session courant, pour la même raison.
  String get sessionTokenForBiometricStorage => _requireToken();

  /// Verrouille : efface la clé de la mémoire et jette tout le contenu
  /// déchiffré. La session serveur reste valable, donc le prochain
  /// déverrouillage ne redemande pas de connexion réseau.
  void lock() {
    _wipe();
    _setStatus(VaultStatus.locked);
  }

  /// Déconnexion complète : révoque aussi la session côté serveur.
  Future<void> logout() async {
    final token = _token;
    if (token != null) {
      try {
        await _api.logout(token);
      } on ApiFailure {
        // Une session déjà morte côté serveur ne doit pas empêcher de
        // verrouiller localement.
      }
    }
    _wipe();
    _setStatus(VaultStatus.locked);
  }

  void _wipe() {
    _vaultKey?.destroy();
    _vaultKey = null;
    _token = null;
    _items = const [];
    _folders = const [];
    _undecryptable = const [];
  }

  /// Place le dépôt dans un état déverrouillé cohérent, sans serveur.
  ///
  /// Réservé aux tests de rendu : les écrans du coffre ne se vérifient
  /// autrement qu'en montant toute la pile réseau. La clé produite est une vraie
  /// clé de coffre, pour que l'état ne soit pas mensonger — un coffre
  /// « déverrouillé » sans clé n'existe pas.
  @visibleForTesting
  Future<void> seedForTest({
    required List<CipherItem> items,
    List<FolderItem> folders = const [],
    VaultProfile? profile,
  }) async {
    _vaultKey?.destroy();
    _vaultKey = await _crypto.newVaultKey();
    _token = 'jeton-de-test';
    _profile = profile;
    _items = items;
    _folders = folders;
    _undecryptable = const [];
    _lastSync = DateTime.now();
    _setStatus(VaultStatus.unlocked);
    notifyListeners();
  }

  // ==================== SESSIONS ====================

  /// Sessions ouvertes sur le compte. Le serveur n'en connaît que l'empreinte du
  /// jeton, jamais le jeton lui-même.
  Future<List<VaultSession>> listSessions() async {
    final raw = await _api.sessions(_requireToken());
    return raw.map(VaultSession.fromJson).toList(growable: false);
  }

  /// Révoque toutes les sessions sauf celle-ci.
  Future<void> revokeOtherSessions() async {
    await _api.revokeOtherSessions(_requireToken());
  }

  // ==================== SYNCHRONISATION ====================

  Future<void> sync() async {
    final token = _requireToken();
    final key = _requireKey();
    final payload = await _api.sync(token);

    final items = <CipherItem>[];
    final broken = <UndecryptableCipher>[];

    for (final remote in payload.ciphers) {
      try {
        final json = await _crypto.decryptJson(remote.data, key);
        items.add(CipherItem(
          id: remote.id,
          folderId: remote.folderId,
          favorite: remote.favorite,
          reprompt: remote.reprompt,
          data: CipherData.fromJson(CipherType.fromWire(remote.type), json),
          createdAt: remote.createdAt,
          revisionDate: remote.revisionDate,
          deletedAt: remote.deletedAt,
        ));
      } catch (e) {
        broken.add(UndecryptableCipher(remote.id, e.toString()));
      }
    }

    final folders = <FolderItem>[];
    for (final remote in payload.folders) {
      try {
        folders.add(FolderItem(
          id: remote.id,
          name: await _crypto.decryptString(remote.name, key),
          revisionDate: remote.revisionDate,
        ));
      } catch (_) {
        folders.add(FolderItem(id: remote.id, name: '⚠ dossier illisible'));
      }
    }

    _profile = payload.profile;
    _items = items;
    _folders = folders;
    _undecryptable = broken;
    _lastSync = DateTime.now();
    notifyListeners();
  }

  // ==================== ÉLÉMENTS ====================

  Future<CipherItem> saveItem(CipherItem item) async {
    final token = _requireToken();
    final key = _requireKey();
    final data = await _crypto.encryptString(item.encodeData(), key);

    final remote = item.id == null
        ? await _api.createCipher(
            token,
            type: item.type.wire,
            data: data,
            folderId: item.folderId,
            favorite: item.favorite,
            reprompt: item.reprompt,
          )
        : await _api.updateCipher(
            token,
            item.id!,
            type: item.type.wire,
            data: data,
            folderId: item.folderId,
            favorite: item.favorite,
            reprompt: item.reprompt,
          );

    final saved = item.copyWith(
      id: remote.id,
      createdAt: remote.createdAt,
      revisionDate: remote.revisionDate,
    );

    final next = [..._items];
    final index = next.indexWhere((i) => i.id == remote.id);
    if (index >= 0) {
      next[index] = saved;
    } else {
      next.insert(0, saved);
    }
    _items = next;
    notifyListeners();
    return saved;
  }

  Future<void> toggleFavorite(CipherItem item) =>
      saveItem(item.copyWith(favorite: !item.favorite));

  Future<void> moveToTrash(CipherItem item) async {
    final token = _requireToken();
    if (item.id == null) return;
    await _api.trashCipher(token, item.id!);
    _replace(item.id!, (i) => i.copyWith(deletedAt: DateTime.now()));
  }

  Future<void> restoreFromTrash(CipherItem item) async {
    final token = _requireToken();
    if (item.id == null) return;
    await _api.restoreCipher(token, item.id!);
    _replace(item.id!, (i) => i.copyWith(clearDeletedAt: true));
  }

  Future<void> deleteForever(CipherItem item) async {
    final token = _requireToken();
    if (item.id == null) return;
    await _api.purgeCipher(token, item.id!);
    _items = _items.where((i) => i.id != item.id).toList(growable: false);
    notifyListeners();
  }

  Future<int> emptyTrash() async {
    final token = _requireToken();
    final purged = await _api.emptyTrash(token);
    _items = _items.where((i) => !i.isDeleted).toList(growable: false);
    notifyListeners();
    return purged;
  }

  void _replace(String id, CipherItem Function(CipherItem) transform) {
    _items = _items
        .map((i) => i.id == id ? transform(i) : i)
        .toList(growable: false);
    notifyListeners();
  }

  // ==================== DOSSIERS ====================

  Future<FolderItem> createFolder(String name) async {
    final token = _requireToken();
    final key = _requireKey();
    final remote = await _api.createFolder(
      token,
      await _crypto.encryptString(name, key),
    );
    final folder = FolderItem(
      id: remote.id,
      name: name,
      revisionDate: remote.revisionDate,
    );
    _folders = [..._folders, folder];
    notifyListeners();
    return folder;
  }

  Future<void> renameFolder(String id, String name) async {
    final token = _requireToken();
    final key = _requireKey();
    await _api.updateFolder(token, id, await _crypto.encryptString(name, key));
    _folders = _folders
        .map((f) => f.id == id
            ? FolderItem(id: f.id, name: name, revisionDate: DateTime.now())
            : f)
        .toList(growable: false);
    notifyListeners();
  }

  /// Les éléments du dossier ne sont pas supprimés : ils retombent « sans
  /// dossier ».
  Future<void> deleteFolder(String id) async {
    final token = _requireToken();
    await _api.deleteFolder(token, id);
    _folders = _folders.where((f) => f.id != id).toList(growable: false);
    _items = _items
        .map((i) => i.folderId == id ? i.copyWith(clearFolder: true) : i)
        .toList(growable: false);
    notifyListeners();
  }

  // ==================== IMPORT ====================

  /// Importe un fichier déjà parsé.
  ///
  /// Les importateurs renvoient des éléments dont `folderId` porte le *nom* du
  /// dossier tel qu'il figurait dans le fichier source — ils n'ont aucun moyen
  /// de connaître les identifiants du coffre. C'est ici qu'on crée les dossiers
  /// manquants et qu'on traduit les noms en identifiants.
  ///
  /// Les noms existants sont réutilisés : réimporter deux fois le même fichier
  /// ne crée pas « Dev » en double.
  Future<int> importParsed(
    ParsedImport parsed, {
    void Function(String step)? onProgress,
  }) async {
    _requireToken();

    final byName = <String, String>{
      for (final folder in _folders) folder.name.toLowerCase(): folder.id,
    };

    for (final name in parsed.folderNames) {
      final key = name.toLowerCase();
      if (byName.containsKey(key)) continue;
      onProgress?.call('Création du dossier « $name »');
      final created = await createFolder(name);
      byName[key] = created.id;
    }

    final resolved = parsed.items.map((item) {
      final name = item.folderId;
      if (name == null) return item;
      final id = byName[name.toLowerCase()];
      // Un dossier introuvable ne doit pas faire perdre l'élément : il retombe
      // sans dossier.
      return id == null ? item.copyWith(clearFolder: true) : item.copyWith(folderId: id);
    }).toList(growable: false);

    onProgress?.call('Chiffrement de ${resolved.length} élément(s)');
    return importItems(resolved);
  }

  /// Chiffre puis envoie un lot d'éléments en une seule requête. C'est le chemin
  /// utilisé par la migration depuis la v1 et par les imports.
  Future<int> importItems(List<CipherItem> incoming) async {
    final token = _requireToken();
    final key = _requireKey();

    final payload = <Map<String, dynamic>>[];
    for (final item in incoming) {
      payload.add({
        'type': item.type.wire,
        'data': await _crypto.encryptString(item.encodeData(), key),
        'folderId': item.folderId,
        'favorite': item.favorite,
        'reprompt': item.reprompt,
      });
    }

    final imported = await _api.importCiphers(token, payload);
    await sync();
    return imported;
  }

  // ==================== MOT DE PASSE MAÎTRE ====================

  /// Réenveloppe la clé de coffre avec une clé dérivée du nouveau mot de passe.
  /// Aucun élément n'est rechiffré : l'opération est instantanée quelle que soit
  /// la taille du coffre. Toutes les sessions tombent, y compris celle-ci.
  Future<void> changeMasterPassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final token = _requireToken();
    final profile = _profile;
    final vaultKey = _requireKey();
    if (profile == null) throw StateError('Aucun profil chargé');

    // On revérifie le mot de passe actuel localement plutôt que de faire
    // confiance à l'état en mémoire.
    final current = await _crypto.deriveMasterKeyMaterial(
      masterPassword: currentPassword,
      kdfSaltHex: profile.kdfSalt,
      params: profile.kdf,
    );
    try {
      await _crypto.unwrapVaultKey(
        protectedKey: profile.protectedKey,
        wrapKey: current.wrapKey,
      );
    } on WrongMasterPasswordException {
      current.destroy();
      rethrow;
    }

    final next = await _crypto.deriveMasterKeyMaterial(
      masterPassword: newPassword,
      kdfSaltHex: profile.kdfSalt,
      params: profile.kdf,
    );
    final rewrapped = await _crypto.wrapVaultKey(
      vaultKey: vaultKey,
      wrapKey: next.wrapKey,
    );

    await _api.changeMasterPassword(
      token: token,
      currentHash: current.masterPasswordHash,
      newHash: next.masterPasswordHash,
      newProtectedKey: rewrapped,
    );

    current.destroy();
    next.destroy();

    // Le serveur a révoqué toutes les sessions : on verrouille pour forcer une
    // réouverture avec le nouveau mot de passe.
    _wipe();
    _setStatus(VaultStatus.locked);
  }

  Future<void> deleteVault(String masterPassword) async {
    final token = _requireToken();
    final profile = _profile;
    if (profile == null) throw StateError('Aucun profil chargé');

    final material = await _crypto.deriveMasterKeyMaterial(
      masterPassword: masterPassword,
      kdfSaltHex: profile.kdfSalt,
      params: profile.kdf,
    );
    try {
      await _api.deleteVault(
        token: token,
        masterPasswordHash: material.masterPasswordHash,
      );
    } finally {
      material.destroy();
    }
    _wipe();
    _setStatus(VaultStatus.locked);
  }

  // ==================== INTERNES ====================

  String _requireToken() {
    final token = _token;
    if (token == null) throw StateError('Coffre verrouillé');
    return token;
  }

  VaultKey _requireKey() {
    final key = _vaultKey;
    if (key == null || key.isDestroyed) throw StateError('Coffre verrouillé');
    return key;
  }

  void _setStatus(VaultStatus next) {
    if (_status == next) return;
    _status = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _wipe();
    super.dispose();
  }
}
