// Réglages de verrouillage.
//
// Chacun est relu par `LockController` ou par `ClipboardGuard` : aucun n'est
// décoratif. C'est le contraire de l'écran de réglages de la v1, où
// « verrouillage automatique » n'était qu'un entier local que personne ne
// consultait.

/// Délai d'inactivité avant verrouillage.
enum AutoLockDelay {
  immediate(0, 'Immédiatement'),
  oneMinute(1, 'Après 1 minute'),
  fiveMinutes(5, 'Après 5 minutes'),
  fifteenMinutes(15, 'Après 15 minutes'),
  thirtyMinutes(30, 'Après 30 minutes'),
  oneHour(60, 'Après 1 heure'),
  never(-1, 'Jamais');

  const AutoLockDelay(this.minutes, this.label);

  /// -1 signifie « jamais ». 0 signifie « dès que l'app passe en arrière-plan »,
  /// ce qui ne dépend alors plus du minuteur d'inactivité.
  final int minutes;
  final String label;

  bool get isNever => minutes < 0;
  bool get isImmediate => minutes == 0;

  Duration? get duration => minutes > 0 ? Duration(minutes: minutes) : null;

  static AutoLockDelay fromMinutes(int? value) {
    return AutoLockDelay.values.firstWhere(
      (d) => d.minutes == value,
      orElse: () => AutoLockDelay.fifteenMinutes,
    );
  }
}

/// Délai avant effacement automatique du presse-papiers.
///
/// Le presse-papiers est lisible par toute application installée, et Android le
/// conserve jusqu'au prochain remplacement. Un mot de passe copié y reste donc
/// indéfiniment si personne ne le retire.
enum ClipboardClearDelay {
  tenSeconds(10, 'Après 10 secondes'),
  twentySeconds(20, 'Après 20 secondes'),
  thirtySeconds(30, 'Après 30 secondes'),
  twoMinutes(120, 'Après 2 minutes'),
  never(-1, 'Jamais');

  const ClipboardClearDelay(this.seconds, this.label);

  final int seconds;
  final String label;

  bool get isNever => seconds < 0;
  Duration? get duration => seconds > 0 ? Duration(seconds: seconds) : null;

  static ClipboardClearDelay fromSeconds(int? value) {
    return ClipboardClearDelay.values.firstWhere(
      (d) => d.seconds == value,
      orElse: () => ClipboardClearDelay.thirtySeconds,
    );
  }
}
