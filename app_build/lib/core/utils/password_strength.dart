import 'dart:math' as math;

/// Estimation de la robustesse d'un mot de passe.
///
/// Ce n'est pas zxcvbn : on ne transporte pas un dictionnaire de 30 000 mots
/// dans l'app. C'est une estimation d'entropie par jeu de caractères, corrigée
/// par les motifs qui font qu'un mot de passe « long » n'est pas fort pour
/// autant — répétitions, suites, années, dispositions de clavier, mots courants.
///
/// Le score alimente la jauge de saisie et le rapport de sécurité de l'étape 5.

enum StrengthLevel {
  empty('Vide'),
  veryWeak('Très faible'),
  weak('Faible'),
  fair('Moyen'),
  strong('Fort'),
  veryStrong('Excellent');

  const StrengthLevel(this.label);
  final String label;

  /// Position sur la jauge, de 0 à 1.
  double get fraction => switch (this) {
        StrengthLevel.empty => 0,
        StrengthLevel.veryWeak => 0.16,
        StrengthLevel.weak => 0.36,
        StrengthLevel.fair => 0.58,
        StrengthLevel.strong => 0.8,
        StrengthLevel.veryStrong => 1,
      };
}

class PasswordStrength {
  const PasswordStrength({
    required this.level,
    required this.entropyBits,
    required this.warnings,
  });

  final StrengthLevel level;

  /// Entropie estimée en bits, après pénalités.
  final double entropyBits;

  /// Ce qui affaiblit le mot de passe, en clair, pour que l'utilisateur sache
  /// quoi corriger au lieu de voir une barre rouge sans explication.
  final List<String> warnings;

  bool get isCompromisedShape => level.index <= StrengthLevel.weak.index;
}

/// Mots de passe et racines qu'on retrouve en tête de toutes les fuites, plus
/// quelques entrées propres au clavier AZERTY.
const _commonRoots = <String>[
  'password', 'motdepasse', 'azerty', 'qwerty', 'qwertz', '123456', '12345678',
  '111111', '000000', 'iloveyou', 'admin', 'administrateur', 'root', 'letmein',
  'welcome', 'bienvenue', 'monkey', 'dragon', 'soleil', 'bonjour', 'chocolat',
  'football', 'princess', 'sunshine', 'master', 'abc123', 'passw0rd',
  'motdepasse1', 'secret', 'test', 'demo', 'changeme', 'default',
];

const _sequences = <String>[
  'abcdefghijklmnopqrstuvwxyz',
  '01234567890',
  'azertyuiop',
  'qwertyuiop',
  'qsdfghjklm',
  'asdfghjkl',
  'wxcvbn',
  'zxcvbnm',
];

abstract final class PasswordStrengthEvaluator {
  static PasswordStrength evaluate(String password) {
    if (password.isEmpty) {
      return const PasswordStrength(
        level: StrengthLevel.empty,
        entropyBits: 0,
        warnings: [],
      );
    }

    final warnings = <String>[];
    final lower = password.toLowerCase();

    // ── Entropie brute : longueur × log2(taille du jeu de caractères) ──
    var charset = 0;
    if (RegExp(r'[a-z]').hasMatch(password)) charset += 26;
    if (RegExp(r'[A-Z]').hasMatch(password)) charset += 26;
    if (RegExp(r'[0-9]').hasMatch(password)) charset += 10;
    if (RegExp(r'''[!-/:-@\[-`{-~]''').hasMatch(password)) charset += 33;
    // Au-delà de l'ASCII imprimable : accents, émojis.
    if (RegExp(r'[^\x00-\x7F]').hasMatch(password)) charset += 100;
    if (charset == 0) charset = 26;

    var bits = password.length * (math.log(charset) / math.ln2);

    // ── Pénalités ──

    // Un seul type de caractère : le jeu réel est bien plus petit que la
    // longueur ne le suggère.
    final families = [
      RegExp(r'[a-z]').hasMatch(password),
      RegExp(r'[A-Z]').hasMatch(password),
      RegExp(r'[0-9]').hasMatch(password),
      RegExp(r'''[!-/:-@\[-`{-~]''').hasMatch(password),
    ].where((v) => v).length;
    if (families == 1) {
      bits *= 0.62;
      warnings.add('Un seul type de caractère');
    } else if (families == 2 && password.length < 12) {
      bits *= 0.85;
    }

    // Racine connue : quelle que soit la longueur, une attaque par
    // dictionnaire la trouve immédiatement.
    for (final root in _commonRoots) {
      if (lower.contains(root)) {
        bits = math.min(bits, 18);
        warnings.add('Contient « $root », qui figure dans toutes les fuites');
        break;
      }
    }

    // Suite de clavier ou d'alphabet de 4 caractères ou plus.
    for (final seq in _sequences) {
      if (_containsRun(lower, seq, 4)) {
        bits -= 12;
        warnings.add('Contient une suite de touches ou de lettres');
        break;
      }
    }

    // Caractère répété : « aaaa », « !!!! ».
    if (RegExp(r'(.)\1{2,}').hasMatch(password)) {
      bits -= 8;
      warnings.add('Contient un caractère répété');
    }

    // Motif entièrement répété : « abcabcabc ».
    final repeated = RegExp(r'^(.{2,})\1+$').firstMatch(password);
    if (repeated != null) {
      bits *= 0.5;
      warnings.add('Répétition d’un même motif');
    }

    // Année en fin de mot de passe : le suffixe le plus prévisible qui existe.
    if (RegExp(r'(19|20)\d{2}$').hasMatch(password)) {
      bits -= 6;
      warnings.add('Se termine par une année');
    }

    // Substitutions « l33t » : elles n'ajoutent presque rien face à un
    // attaquant qui les connaît.
    final deLeet = lower
        .replaceAll('0', 'o')
        .replaceAll('1', 'i')
        .replaceAll('3', 'e')
        .replaceAll('4', 'a')
        .replaceAll('5', 's')
        .replaceAll('7', 't')
        .replaceAll('@', 'a')
        .replaceAll(r'$', 's');
    if (deLeet != lower) {
      for (final root in _commonRoots) {
        if (deLeet.contains(root)) {
          bits = math.min(bits, 22);
          warnings.add('Mot courant à peine déguisé (0 pour o, 3 pour e…)');
          break;
        }
      }
    }

    // Trop court : rien ne compense.
    if (password.length < 8) {
      bits = math.min(bits, 24);
      warnings.add('Moins de 8 caractères');
    }

    bits = math.max(0, bits);

    return PasswordStrength(
      level: _levelFor(bits),
      entropyBits: bits,
      warnings: warnings,
    );
  }

  /// Seuils en bits. 60 bits est le seuil au-delà duquel une attaque hors ligne
  /// devient coûteuse pour un mot de passe correctement haché ; 80 la met hors
  /// de portée pratique.
  static StrengthLevel _levelFor(double bits) {
    if (bits <= 0) return StrengthLevel.empty;
    if (bits < 28) return StrengthLevel.veryWeak;
    if (bits < 42) return StrengthLevel.weak;
    if (bits < 60) return StrengthLevel.fair;
    if (bits < 80) return StrengthLevel.strong;
    return StrengthLevel.veryStrong;
  }

  /// Vrai si `value` contient au moins `minRun` caractères consécutifs de
  /// `sequence`, dans un sens ou dans l'autre.
  static bool _containsRun(String value, String sequence, int minRun) {
    final reversed = sequence.split('').reversed.join();
    for (var i = 0; i + minRun <= sequence.length; i++) {
      if (value.contains(sequence.substring(i, i + minRun))) return true;
    }
    for (var i = 0; i + minRun <= reversed.length; i++) {
      if (value.contains(reversed.substring(i, i + minRun))) return true;
    }
    return false;
  }
}
