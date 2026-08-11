import '../../core/utils/password_strength.dart';
import '../../data/models/cipher.dart';

/// Analyse de santé du coffre.
///
/// Locale par défaut : elle travaille sur le coffre déjà déchiffré en mémoire, et
/// ne fait aucun appel réseau. Le serveur ne pourrait pas la produire — il ne
/// voit que des blobs — et c'est précisément l'intérêt.
///
/// La confrontation aux fuites connues est le seul volet qui sort de l'appareil.
/// Elle est donc facultative : passer `breachCounts` l'active, l'omettre laisse
/// l'analyse entièrement hors ligne. Voir `HibpService` pour ce qui transite
/// réellement.

/// L'ordre détermine la gravité : `primaryIssue` renvoie le premier trouvé.
/// Une fuite confirmée passe avant tout le reste — un mot de passe déjà publié
/// est compromis quelle que soit sa complexité.
enum HealthIssue {
  breached(
    'Mot de passe exposé',
    'Apparaît dans une fuite de données connue : il est à changer, même s’il '
        'paraît complexe',
  ),
  weak('Mot de passe faible', 'Facile à retrouver par force brute ou dictionnaire'),
  reused('Mot de passe réutilisé', 'Une seule fuite compromet tous les comptes concernés'),
  old('Mot de passe ancien', 'Inchangé depuis plus d’un an'),
  empty('Aucun mot de passe', 'L’entrée n’en contient pas');

  const HealthIssue(this.label, this.explanation);
  final String label;
  final String explanation;
}

class ItemHealth {
  final CipherItem item;
  final Set<HealthIssue> issues;
  final PasswordStrength? strength;

  /// Nombre d'entrées partageant ce mot de passe, celle-ci comprise.
  final int reuseCount;

  /// Nombre d'apparitions du mot de passe dans les fuites connues, si la
  /// vérification a été faite. `null` = non vérifié, ce qui n'est pas « sain ».
  final int? breachCount;

  const ItemHealth({
    required this.item,
    required this.issues,
    this.strength,
    this.reuseCount = 1,
    this.breachCount,
  });

  bool get isHealthy => issues.isEmpty;

  /// Problème le plus grave, pour l'afficher en pastille sur la ligne du coffre.
  /// L'ordre de `HealthIssue` fait foi.
  HealthIssue? get primaryIssue {
    for (final issue in HealthIssue.values) {
      if (issues.contains(issue)) return issue;
    }
    return null;
  }
}

class VaultHealthReport {
  final List<ItemHealth> analysed;

  const VaultHealthReport(this.analysed);

  static const VaultHealthReport empty = VaultHealthReport([]);

  List<ItemHealth> withIssue(HealthIssue issue) =>
      analysed.where((h) => h.issues.contains(issue)).toList(growable: false);

  int countOf(HealthIssue issue) => withIssue(issue).length;

  List<ItemHealth> get problematic =>
      analysed.where((h) => !h.isHealthy).toList(growable: false);

  int get totalAnalysed => analysed.length;
  int get totalProblems => problematic.length;

  bool get isClean => totalProblems == 0;

  /// Note sur 100. Pondérée : la réutilisation et la faiblesse pèsent lourd,
  /// l'ancienneté est un avertissement de confort.
  int get score {
    if (analysed.isEmpty) return 100;
    var penalty = 0.0;
    for (final health in analysed) {
      // Une fuite confirmée pèse plus lourd que tout : le mot de passe est
      // déjà public.
      if (health.issues.contains(HealthIssue.breached)) penalty += 1.6;
      if (health.issues.contains(HealthIssue.empty)) penalty += 0.5;
      if (health.issues.contains(HealthIssue.weak)) penalty += 1.0;
      if (health.issues.contains(HealthIssue.reused)) penalty += 1.0;
      if (health.issues.contains(HealthIssue.old)) penalty += 0.35;
    }
    final ratio = penalty / analysed.length;
    return (100 - (ratio * 45)).clamp(0, 100).round();
  }

  /// Résumé d'une ligne pour le bandeau du coffre.
  String get summaryLine {
    final parts = <String>[];
    final breached = countOf(HealthIssue.breached);
    if (breached > 0) parts.add('$breached exposé${breached > 1 ? 's' : ''}');
    final weak = countOf(HealthIssue.weak);
    final reused = countOf(HealthIssue.reused);
    final old = countOf(HealthIssue.old);
    if (weak > 0) parts.add('$weak faible${weak > 1 ? 's' : ''}');
    if (reused > 0) parts.add('$reused réutilisé${reused > 1 ? 's' : ''}');
    if (old > 0) parts.add('$old ancien${old > 1 ? 's' : ''}');
    return parts.join(' · ');
  }
}

abstract final class VaultHealth {
  /// Au-delà, un mot de passe mérite d'être renouvelé.
  static const Duration ageThreshold = Duration(days: 365);

  /// `breachCounts` associe un mot de passe à son nombre d'apparitions dans les
  /// fuites connues. Il vient de `HibpService`, et reste optionnel : sans lui
  /// l'analyse est purement locale et ne fait aucun appel réseau.
  static VaultHealthReport analyse(
    List<CipherItem> items, {
    DateTime? now,
    Map<String, int>? breachCounts,
  }) {
    final reference = now ?? DateTime.now();

    // Comptage des réutilisations. On compare les mots de passe entre eux, en
    // mémoire, sans jamais les écrire ni les transmettre.
    final occurrences = <String, int>{};
    for (final item in items) {
      final data = item.data;
      if (data is! LoginData) continue;
      if (data.password.isEmpty) continue;
      occurrences[data.password] = (occurrences[data.password] ?? 0) + 1;
    }

    final analysed = <ItemHealth>[];

    for (final item in items) {
      final data = item.data;
      // Seuls les identifiants portent un mot de passe : une note ou une
      // identité ne peut être ni faible ni réutilisée.
      if (data is! LoginData) continue;

      final issues = <HealthIssue>{};

      if (data.password.isEmpty) {
        issues.add(HealthIssue.empty);
        analysed.add(ItemHealth(item: item, issues: issues));
        continue;
      }

      final strength = PasswordStrengthEvaluator.evaluate(data.password);
      if (strength.isCompromisedShape) issues.add(HealthIssue.weak);

      final breachCount = breachCounts?[data.password];
      if (breachCount != null && breachCount > 0) {
        issues.add(HealthIssue.breached);
      }

      final reuse = occurrences[data.password] ?? 1;
      if (reuse > 1) issues.add(HealthIssue.reused);

      // Sans date de changement connue on ne conclut rien : l'import v1 ne la
      // fournit pas, et inventer « récent » serait mensonger.
      final changedAt = data.passwordUpdatedAt;
      if (changedAt != null &&
          reference.difference(changedAt) > ageThreshold) {
        issues.add(HealthIssue.old);
      }

      analysed.add(ItemHealth(
        item: item,
        issues: issues,
        strength: strength,
        reuseCount: reuse,
        breachCount: breachCount,
      ));
    }

    return VaultHealthReport(analysed);
  }
}
