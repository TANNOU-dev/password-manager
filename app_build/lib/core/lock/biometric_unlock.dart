import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

/// Déverrouillage biométrique.
///
/// ## Ce qui est stocké, et où
///
/// Deux valeurs : la clé du coffre et le jeton de session. Elles vont dans
/// `flutter_secure_storage`, qui utilise `EncryptedSharedPreferences` adossé au
/// Keystore matériel sur Android, et le Keychain sur iOS. Le mot de passe maître
/// n'y est **jamais** écrit.
///
/// La v1 stockait le jeton de session dans `SharedPreferences` en clair — un
/// fichier XML lisible par `adb backup` ou par n'importe quelle app sur un
/// appareil rooté. Ce jeton ouvrait tout le coffre.
///
/// ## Ce que ça protège, et ce que ça ne protège pas
///
/// Protégé : un accès en lecture au système de fichiers ne suffit plus, le
/// contenu est chiffré par une clé du Keystore qui ne sort pas du matériel.
///
/// **Non protégé** : `flutter_secure_storage` ne permet pas de lier sa clé
/// Keystore à une authentification utilisateur (`setUserAuthenticationRequired`).
/// La vérification biométrique est donc appliquée *par l'app* avant la lecture,
/// pas *par le système* au moment de déchiffrer. Un attaquant capable d'exécuter
/// du code en tant que cette app sur un appareil rooté peut lire la clé sans
/// passer la biométrie.
///
/// Pour la même raison, un nouveau doigt enrôlé sur l'appareil n'invalide pas la
/// clé stockée, là où `setInvalidatedByBiometricEnrollment` le ferait. Fermer
/// complètement ces deux écarts demande du code Kotlin natif ; c'est noté comme
/// une limite connue plutôt que présenté comme résolu.
///
/// Le déverrouillage biométrique reste, dans tous les cas, un raccourci : le mot
/// de passe maître fonctionne toujours, et il reste le seul chemin après un
/// redémarrage si la clé a été invalidée.
class BiometricUnlockStore {
  BiometricUnlockStore({
    FlutterSecureStorage? storage,
    LocalAuthentication? localAuth,
  })  : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            ),
        _auth = localAuth ?? LocalAuthentication();

  static const _kVaultKey = 'biometric_vault_key';
  static const _kToken = 'biometric_session_token';
  static const _kEmail = 'biometric_email';

  final FlutterSecureStorage _storage;
  final LocalAuthentication _auth;

  /// Vrai si l'appareil peut authentifier l'utilisateur *et* qu'au moins une
  /// empreinte ou un visage est enrôlé. Les deux conditions comptent : un
  /// appareil compatible sans empreinte enrôlée ne peut rien vérifier.
  Future<bool> get isAvailable async {
    // Pas de biométrie utilisable sur le web : le stockage sécurisé n'y est
    // qu'un chiffrement dans le navigateur, sans matériel derrière.
    if (kIsWeb) return false;
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } on Exception {
      return false;
    }
  }

  /// Liste lisible des méthodes disponibles, pour l'écran de réglages.
  Future<String> describeAvailable() async {
    try {
      final kinds = await _auth.getAvailableBiometrics();
      final labels = <String>[
        if (kinds.contains(BiometricType.face)) 'reconnaissance faciale',
        if (kinds.contains(BiometricType.fingerprint)) 'empreinte digitale',
        if (kinds.contains(BiometricType.iris)) 'iris',
        if (kinds.contains(BiometricType.strong) ||
            kinds.contains(BiometricType.weak))
          'biométrie de l’appareil',
      ];
      return labels.isEmpty ? 'aucune méthode enrôlée' : labels.join(', ');
    } on Exception {
      return 'indéterminé';
    }
  }

  Future<bool> get hasStoredKey async {
    if (kIsWeb) return false;
    try {
      return await _storage.read(key: _kVaultKey) != null;
    } on Exception {
      return false;
    }
  }

  /// E-mail associé à la clé stockée, pour préremplir l'écran de déverrouillage.
  Future<String?> get storedEmail async {
    if (kIsWeb) return null;
    try {
      return await _storage.read(key: _kEmail);
    } on Exception {
      return null;
    }
  }

  /// Active le déverrouillage biométrique.
  ///
  /// Demande d'abord une authentification : c'est ce qui prouve que la personne
  /// devant l'appareil est bien celle qui vient d'ouvrir le coffre, et pas
  /// quelqu'un qui a récupéré un téléphone déverrouillé.
  Future<bool> enable({
    required String email,
    required String sessionToken,
    required Uint8List vaultKeyBytes,
  }) async {
    if (!await isAvailable) return false;

    final confirmed = await _authenticate(
      'Confirmez pour activer le déverrouillage biométrique',
    );
    if (!confirmed) return false;

    try {
      await _storage.write(key: _kEmail, value: email);
      await _storage.write(key: _kToken, value: sessionToken);
      await _storage.write(
        key: _kVaultKey,
        value: base64.encode(vaultKeyBytes),
      );
      return true;
    } on Exception {
      // Un écrasement partiel laisserait un état incohérent : on nettoie.
      await disable();
      return false;
    }
  }

  /// Demande la biométrie puis rend la clé et le jeton.
  ///
  /// `null` si l'authentification échoue ou si rien n'est stocké. Aucune
  /// distinction n'est faite entre les deux vers l'appelant : dans les deux cas
  /// il faut retomber sur le mot de passe maître.
  Future<BiometricUnlockData?> unlock() async {
    if (!await hasStoredKey) return null;

    final confirmed = await _authenticate('Déverrouillez votre coffre');
    if (!confirmed) return null;

    try {
      final encoded = await _storage.read(key: _kVaultKey);
      final token = await _storage.read(key: _kToken);
      final email = await _storage.read(key: _kEmail);
      if (encoded == null || token == null || email == null) return null;

      return BiometricUnlockData(
        email: email,
        sessionToken: token,
        vaultKeyBytes: Uint8List.fromList(base64.decode(encoded)),
      );
    } on Exception {
      return null;
    }
  }

  /// Retire la clé stockée. Appelé au verrouillage explicite, à la déconnexion,
  /// au changement de mot de passe maître, et si le jeton s'avère invalide.
  Future<void> disable() async {
    if (kIsWeb) return;
    try {
      await _storage.delete(key: _kVaultKey);
      await _storage.delete(key: _kToken);
      await _storage.delete(key: _kEmail);
    } on Exception {
      // Rien à rattraper : l'appelant remettra le drapeau de réglage à faux.
    }
  }

  Future<bool> _authenticate(String reason) async {
    try {
      // API plate de local_auth 3.x : `AuthenticationOptions` a disparu de la
      // surface publique, ses champs sont passés directement.
      return await _auth.authenticate(
        localizedReason: reason,
        // Seuls les messages Android sont fournis : c'est la plateforme visée.
        // Ailleurs, la boîte système garde ses libellés par défaut.
        authMessages: [
          AndroidAuthMessages(
            signInTitle: 'Coffort',
            signInHint: reason,
            cancelButton: 'Annuler',
          ),
        ],
        // Refuse le repli sur le code de déverrouillage de l'appareil : le
        // raccourci doit exiger la biométrie, sinon il ramène la sécurité du
        // coffre au niveau du code à quatre chiffres du téléphone.
        biometricOnly: true,
        // L'app ne doit pas rester bloquée sur la boîte système si l'utilisateur
        // part ailleurs.
        persistAcrossBackgrounding: false,
      );
    } on Exception {
      return false;
    }
  }
}

/// Ce que le déverrouillage biométrique rend à l'app.
class BiometricUnlockData {
  final String email;
  final String sessionToken;
  final Uint8List vaultKeyBytes;

  const BiometricUnlockData({
    required this.email,
    required this.sessionToken,
    required this.vaultKeyBytes,
  });
}
