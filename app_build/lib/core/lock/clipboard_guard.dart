import 'dart:async';

import 'package:flutter/services.dart';

import '../settings/app_settings.dart';

/// Copie une valeur sensible et la retire du presse-papiers après un délai.
///
/// Pourquoi c'est nécessaire : sur Android, le presse-papiers est lisible par
/// **toute** application installée, et son contenu y reste jusqu'au prochain
/// remplacement. Un mot de passe copié à 9 h y est encore à 18 h.
///
/// Deux précautions dans l'effacement :
///
/// * on ne remet pas une chaîne vide, mais un espace. Sur certaines versions
///   d'Android, vider le presse-papiers déclenche un avertissement système, et
///   certaines applications rétablissent l'ancien contenu ;
/// * on vérifie que le presse-papiers contient **encore ce qu'on y a mis** avant
///   d'effacer. Sinon on écraserait ce que l'utilisateur a copié entre-temps
///   depuis une autre app.
class ClipboardGuard {
  ClipboardGuard(this._settings);

  final AppSettings _settings;

  Timer? _pending;

  /// Valeur écrite par nous, pour ne pas effacer celle de quelqu'un d'autre.
  String? _ours;

  /// Copie et programme l'effacement selon le réglage courant.
  Future<void> copy(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    _ours = value;
    _schedule();
  }

  void _schedule() {
    _pending?.cancel();
    _pending = null;

    final delay = _settings.clipboardClear.duration;
    if (delay == null) return;

    _pending = Timer(delay, clearIfOurs);
  }

  /// Efface, mais seulement si le presse-papiers contient toujours notre valeur.
  Future<void> clearIfOurs() async {
    final ours = _ours;
    if (ours == null) return;

    try {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text != ours) {
        // L'utilisateur a copié autre chose : ce n'est plus à nous d'y toucher.
        _ours = null;
        return;
      }
      await Clipboard.setData(const ClipboardData(text: ' '));
    } on PlatformException {
      // Certaines plateformes refusent la lecture du presse-papiers. On préfère
      // ne rien faire plutôt que d'écraser un contenu inconnu.
    } finally {
      _ours = null;
    }
  }

  /// Appelé au verrouillage : on n'attend pas la fin du délai pour retirer un
  /// secret du presse-papiers si le coffre se referme.
  Future<void> onLock() => clearIfOurs();

  void dispose() {
    _pending?.cancel();
    _pending = null;
    _ours = null;
  }

  /// Description du réglage courant, pour l'interface.
  String get describeDelay => _settings.clipboardClear.isNever
      ? 'Le presse-papiers n’est pas effacé'
      : _settings.clipboardClear.label.toLowerCase();
}
