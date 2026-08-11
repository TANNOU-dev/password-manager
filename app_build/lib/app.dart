import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/design/app_theme.dart';
import 'core/design/tokens.dart';
import 'core/lock/biometric_unlock.dart';
import 'core/lock/clipboard_guard.dart';
import 'core/lock/lock_controller.dart';
import 'core/settings/app_settings.dart';
import 'data/vault_repository.dart';
import 'features/auth/unlock_screen.dart';
import 'features/autofill/autofill_screen.dart';
import 'features/shell/app_shell.dart';

class PassVaultApp extends StatefulWidget {
  const PassVaultApp({
    super.key,
    required this.settings,
    required this.deviceName,
    this.launchedForAutofill = false,
  });

  final AppSettings settings;
  final String deviceName;

  /// Vrai quand le processus a été lancé par le service de remplissage Android
  /// plutôt que par l'utilisateur. L'app n'affiche alors que le sélecteur
  /// d'identifiant, pas le coffre complet.
  final bool launchedForAutofill;

  @override
  State<PassVaultApp> createState() => _PassVaultAppState();
}

class _PassVaultAppState extends State<PassVaultApp> {
  late final VaultRepository _vault;
  late final LockController _lock;
  late final ClipboardGuard _clipboard;
  late final BiometricUnlockStore _biometrics;

  @override
  void initState() {
    super.initState();
    // Ces objets vivent aussi longtemps que l'app : le dépôt détient la clé du
    // coffre en mémoire, et le contrôleur de verrouillage observe le cycle de vie.
    // Les recréer au fil de la navigation rouvrirait le coffre par accident.
    _vault = VaultRepository(deviceName: widget.deviceName);
    _clipboard = ClipboardGuard(widget.settings);
    _biometrics = BiometricUnlockStore();
    _lock = LockController(vault: _vault, settings: widget.settings);

    // Au verrouillage, on ne laisse pas un secret traîner dans le presse-papiers.
    _vault.addListener(_onVaultStatusChanged);
  }

  bool _wasUnlocked = false;

  void _onVaultStatusChanged() {
    final unlocked = _vault.isUnlocked;
    if (_wasUnlocked && !unlocked) {
      _clipboard.onLock();
    }
    _wasUnlocked = unlocked;
  }

  @override
  void dispose() {
    _vault.removeListener(_onVaultStatusChanged);
    _lock.dispose();
    _clipboard.dispose();
    _vault.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.settings),
        ChangeNotifierProvider.value(value: _vault),
        Provider.value(value: _lock),
        Provider.value(value: _clipboard),
        Provider.value(value: _biometrics),
      ],
      child: Consumer<AppSettings>(
        builder: (context, settings, _) => MaterialApp(
          title: 'PassVault',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: settings.themeMode,
          // Toute interaction repousse le verrouillage par inactivité. Un seul
          // écouteur au sommet de l'arbre, plutôt qu'un par écran.
          builder: (context, child) => ActivityDetector(
            controller: _lock,
            child: child ?? const SizedBox.shrink(),
          ),
          home: widget.launchedForAutofill
              ? const AutofillScreen()
              : const _VaultGate(),
        ),
      ),
    );
  }
}

/// Porte d'entrée : choisit l'écran selon l'état du coffre.
///
/// Un seul endroit décide. Ça évite la situation de la v1, où chaque écran
/// poussait lui-même un `LoginScreen` avec `pushAndRemoveUntil` et où le
/// verrouillage dépendait du chemin de navigation emprunté.
class _VaultGate extends StatelessWidget {
  const _VaultGate();

  @override
  Widget build(BuildContext context) {
    final status = context.select<VaultRepository, VaultStatus>((r) => r.status);

    return AnimatedSwitcher(
      duration: Motion.normal,
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      // Fondu simple : un glissement suggérerait une navigation, alors qu'ici
      // l'app change d'état.
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: switch (status) {
        // `unlocking` reste sur l'écran de déverrouillage : c'est lui qui montre
        // la progression de la dérivation Argon2id.
        VaultStatus.locked || VaultStatus.unlocking =>
          const UnlockScreen(key: ValueKey('unlock')),
        VaultStatus.unlocked => const AppShell(key: ValueKey('shell')),
      },
    );
  }
}
