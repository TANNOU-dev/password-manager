import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'lock_settings.dart';

/// Préférences de l'app.
///
/// Règle : rien n'entre ici qui ne soit réellement relu par du code qui agit.
/// L'ancien écran de réglages affichait des interrupteurs « biométrie » et
/// « verrouillage automatique » qui ne changeaient qu'un booléen local que
/// personne ne consultait.
///
/// Rien de sensible ici : ni mot de passe maître, ni jeton de session, ni clé.
/// `SharedPreferences` n'est pas un stockage sécurisé — les clés vont dans
/// `BiometricUnlockStore`, adossé au trousseau du système.
class AppSettings extends ChangeNotifier {
  AppSettings._(this._prefs)
      : _themeMode = _readThemeMode(_prefs),
        _lastEmail = _prefs.getString(_kLastEmail),
        _autoLock = AutoLockDelay.fromMinutes(_prefs.getInt(_kAutoLock)),
        _lockOnBackground = _prefs.getBool(_kLockOnBackground) ?? true,
        _clipboardClear =
            ClipboardClearDelay.fromSeconds(_prefs.getInt(_kClipboardClear)),
        _biometricUnlock = _prefs.getBool(_kBiometricUnlock) ?? false;

  static const _kThemeMode = 'theme_mode';
  static const _kLastEmail = 'last_email';
  static const _kAutoLock = 'auto_lock_minutes';
  static const _kLockOnBackground = 'lock_on_background';
  static const _kClipboardClear = 'clipboard_clear_seconds';
  static const _kBiometricUnlock = 'biometric_unlock';

  final SharedPreferences _prefs;

  static Future<AppSettings> load() async {
    return AppSettings._(await SharedPreferences.getInstance());
  }

  static ThemeMode _readThemeMode(SharedPreferences prefs) {
    return switch (prefs.getString(_kThemeMode)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  ThemeMode _themeMode;
  ThemeMode get themeMode => _themeMode;

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _prefs.setString(_kThemeMode, switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }

  /// Dernier e-mail utilisé, pour ne pas le retaper à chaque déverrouillage.
  /// C'est un identifiant de compte, pas un secret.
  String? _lastEmail;
  String? get lastEmail => _lastEmail;

  Future<void> rememberEmail(String email) async {
    final trimmed = email.trim().toLowerCase();
    if (_lastEmail == trimmed) return;
    _lastEmail = trimmed;
    notifyListeners();
    await _prefs.setString(_kLastEmail, trimmed);
  }

  Future<void> forgetEmail() async {
    _lastEmail = null;
    notifyListeners();
    await _prefs.remove(_kLastEmail);
  }

  // ==================== VERROUILLAGE ====================

  /// Relu par `LockController`, qui arme son minuteur d'inactivité dessus.
  AutoLockDelay _autoLock;
  AutoLockDelay get autoLock => _autoLock;

  Future<void> setAutoLock(AutoLockDelay value) async {
    if (_autoLock == value) return;
    _autoLock = value;
    notifyListeners();
    await _prefs.setInt(_kAutoLock, value.minutes);
  }

  /// Verrouiller dès que l'app quitte le premier plan.
  ///
  /// Actif par défaut : sur Android, une app en arrière-plan reste visible dans
  /// le sélecteur de tâches et peut être tuée sans prévenir, laissant la clé en
  /// mémoire jusque-là.
  bool _lockOnBackground;
  bool get lockOnBackground => _lockOnBackground;

  Future<void> setLockOnBackground(bool value) async {
    if (_lockOnBackground == value) return;
    _lockOnBackground = value;
    notifyListeners();
    await _prefs.setBool(_kLockOnBackground, value);
  }

  /// Relu par `ClipboardGuard` après chaque copie.
  ClipboardClearDelay _clipboardClear;
  ClipboardClearDelay get clipboardClear => _clipboardClear;

  Future<void> setClipboardClear(ClipboardClearDelay value) async {
    if (_clipboardClear == value) return;
    _clipboardClear = value;
    notifyListeners();
    await _prefs.setInt(_kClipboardClear, value.seconds);
  }

  /// Déverrouillage biométrique. Ce drapeau n'est qu'un indicateur d'interface :
  /// la vraie source de vérité est la présence d'une clé dans
  /// `BiometricUnlockStore`, qui vit dans le trousseau du système.
  bool _biometricUnlock;
  bool get biometricUnlock => _biometricUnlock;

  Future<void> setBiometricUnlock(bool value) async {
    if (_biometricUnlock == value) return;
    _biometricUnlock = value;
    notifyListeners();
    await _prefs.setBool(_kBiometricUnlock, value);
  }
}
