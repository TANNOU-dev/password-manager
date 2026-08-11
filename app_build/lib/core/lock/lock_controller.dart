import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../data/vault_repository.dart';
import '../settings/app_settings.dart';

/// Verrouille le coffre quand il n'est plus surveillé.
///
/// Deux déclencheurs, pour deux risques distincts :
///
/// * **inactivité** — le téléphone reste déverrouillé sur une table. Un minuteur
///   compare l'horloge à la dernière interaction.
/// * **passage en arrière-plan** — l'app quitte le premier plan. Sur Android, son
///   contenu reste alors visible dans le sélecteur de tâches, et le système peut
///   la tuer à tout moment sans lui laisser exécuter quoi que ce soit.
///
/// Le minuteur ne fait que comparer des dates : il ne pilote pas le
/// verrouillage à l'expiration d'un `Timer` unique. C'est important, parce qu'un
/// `Timer` ne progresse pas pendant que le processus est suspendu — un coffre
/// laissé 8 heures en arrière-plan reviendrait déverrouillé.
class LockController with WidgetsBindingObserver {
  LockController({
    required VaultRepository vault,
    required AppSettings settings,
    Duration tick = const Duration(seconds: 15),
    DateTime Function()? clock,
  })  : _vault = vault,
        _settings = settings,
        _tick = tick,
        _now = clock ?? DateTime.now {
    _lastActivity = _now();
    WidgetsBinding.instance.addObserver(this);
    _settings.addListener(_onSettingsChanged);
    _vault.addListener(_onVaultChanged);
    _syncTimer();
  }

  final VaultRepository _vault;
  final AppSettings _settings;
  final Duration _tick;
  final DateTime Function() _now;

  Timer? _timer;
  late DateTime _lastActivity;

  /// Instant où l'app est passée en arrière-plan. Sert à rattraper le temps
  /// écoulé pendant une suspension, que le minuteur n'a pas pu compter.
  DateTime? _backgroundedAt;

  /// À appeler à chaque interaction. Branché sur les événements de pointeur au
  /// sommet de l'arbre, pas sur chaque widget.
  void registerActivity() {
    _lastActivity = _now();
  }

  /// Temps restant avant verrouillage, pour l'affichage. `null` si sans objet.
  Duration? get remaining {
    final delay = _settings.autoLock.duration;
    if (delay == null || !_vault.isUnlocked) return null;
    final elapsed = _now().difference(_lastActivity);
    final left = delay - elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  void _onSettingsChanged() => _syncTimer();

  void _onVaultChanged() {
    if (_vault.isUnlocked) {
      // Une ouverture compte comme une activité, sinon un déverrouillage juste
      // après une longue absence se refermerait aussitôt.
      _lastActivity = _now();
    }
    _syncTimer();
  }

  /// Le minuteur ne tourne que quand il a une raison de tourner : coffre ouvert
  /// et délai fini. Un `Timer.periodic` qui s'exécute sur un coffre verrouillé
  /// réveille le processeur pour rien.
  void _syncTimer() {
    final needed = _vault.isUnlocked && _settings.autoLock.duration != null;
    if (needed && _timer == null) {
      _timer = Timer.periodic(_tick, (_) => _checkIdle());
    } else if (!needed && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  void _checkIdle() {
    final delay = _settings.autoLock.duration;
    if (delay == null || !_vault.isUnlocked) return;
    if (_now().difference(_lastActivity) >= delay) {
      _vault.lock();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      // `hidden` précède `paused` sur les versions récentes ; `inactive` arrive
      // aussi pour un simple panneau système, donc on ne verrouille pas dessus.
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _backgroundedAt = _now();
        if (_settings.lockOnBackground || _settings.autoLock.isImmediate) {
          _vault.lock();
        }
      case AppLifecycleState.resumed:
        _onResumed();
      case AppLifecycleState.inactive:
        break;
    }
  }

  /// Au retour au premier plan, on rattrape le temps que le minuteur n'a pas
  /// compté pendant la suspension. Sans ça, une nuit en arrière-plan ne
  /// verrouillerait rien.
  void _onResumed() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since == null || !_vault.isUnlocked) {
      _syncTimer();
      return;
    }

    final delay = _settings.autoLock.duration;
    if (delay != null && _now().difference(_lastActivity) >= delay) {
      _vault.lock();
      return;
    }
    _syncTimer();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
    _settings.removeListener(_onSettingsChanged);
    _vault.removeListener(_onVaultChanged);
  }
}

/// Signale toute interaction au contrôleur de verrouillage.
///
/// Placé au sommet de l'arbre : un seul écouteur pour toute l'app. `Listener`
/// avec `HitTestBehavior.translucent` observe sans intercepter, donc les widgets
/// en dessous reçoivent leurs événements normalement.
class ActivityDetector extends StatelessWidget {
  const ActivityDetector({
    super.key,
    required this.controller,
    required this.child,
  });

  final LockController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => controller.registerActivity(),
      onPointerSignal: (_) => controller.registerActivity(),
      child: child,
    );
  }
}
