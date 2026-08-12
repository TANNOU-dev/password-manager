import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/settings/app_settings.dart';

/// Point d'entrée appelé par le service de remplissage Android.
///
/// C'est un second `runApp` dans un processus séparé, lancé par le système quand
/// une application demande un identifiant. `@pragma('vm:entry-point')` est
/// obligatoire : sans lui, la compilation en mode release élague cette fonction
/// puisque rien ne l'appelle depuis Dart, et le remplissage échoue silencieusement.
@pragma('vm:entry-point')
Future<void> autofillEntryPoint() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  runApp(CoffortApp(
    settings: settings,
    deviceName: _deviceName(),
    launchedForAutofill: true,
  ));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Note : `cryptography_flutter` fournit les implémentations natives d'AES-GCM
  // et de HMAC, et s'enregistre désormais tout seul — l'appel explicite à
  // FlutterCryptography.enable() est déprécié. Argon2id reste en pur Dart, non
  // accéléré, d'où sa dérivation dans un isolat (voir VaultCrypto).

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ),
  );

  final settings = await AppSettings.load();

  runApp(CoffortApp(settings: settings, deviceName: _deviceName()));
}

/// Nom affiché dans la liste des appareils connectés. Volontairement grossier :
/// il sert à reconnaître ses propres sessions, pas à identifier la machine.
String _deviceName() {
  if (kIsWeb) return 'Navigateur';
  try {
    return switch (Platform.operatingSystem) {
      'android' => 'Android',
      'ios' => 'iPhone',
      'linux' => 'Linux',
      'macos' => 'macOS',
      'windows' => 'Windows',
      final other => other,
    };
  } catch (_) {
    return 'Appareil';
  }
}
