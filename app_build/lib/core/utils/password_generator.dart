import 'dart:math';

/// Génération de mots de passe, entièrement sur l'appareil.
///
/// La v1 appelait `GET /api/generate` : le serveur fabriquait le mot de passe et
/// le renvoyait en HTTP clair. Autant afficher le coffre en public. Ici tout
/// vient de `Random.secure()`, qui puise dans le générateur du système.

enum GeneratorMode { characters, passphrase }

class CharacterOptions {
  final int length;
  final bool uppercase;
  final bool lowercase;
  final bool digits;
  final bool symbols;

  /// Écarte `0 O o 1 l I |` : indispensable pour un mot de passe qu'on devra
  /// recopier à la main depuis un écran.
  final bool avoidAmbiguous;

  /// Garantit au moins un caractère de chaque famille cochée. Sans ça, un tirage
  /// de 8 caractères peut ne contenir aucun chiffre et être refusé par le site.
  final bool requireEachType;

  const CharacterOptions({
    this.length = 20,
    this.uppercase = true,
    this.lowercase = true,
    this.digits = true,
    this.symbols = true,
    this.avoidAmbiguous = false,
    this.requireEachType = true,
  });

  CharacterOptions copyWith({
    int? length,
    bool? uppercase,
    bool? lowercase,
    bool? digits,
    bool? symbols,
    bool? avoidAmbiguous,
    bool? requireEachType,
  }) =>
      CharacterOptions(
        length: length ?? this.length,
        uppercase: uppercase ?? this.uppercase,
        lowercase: lowercase ?? this.lowercase,
        digits: digits ?? this.digits,
        symbols: symbols ?? this.symbols,
        avoidAmbiguous: avoidAmbiguous ?? this.avoidAmbiguous,
        requireEachType: requireEachType ?? this.requireEachType,
      );

  /// Au moins une famille doit être active, sinon il n'y a rien à tirer.
  bool get hasAnyType => uppercase || lowercase || digits || symbols;
}

class PassphraseOptions {
  final int wordCount;
  final String separator;
  final bool capitalize;
  final bool includeNumber;

  const PassphraseOptions({
    // 6 et non 5 : voir la note d'entropie sur `frenchWordList`.
    this.wordCount = 6,
    this.separator = '-',
    this.capitalize = true,
    this.includeNumber = false,
  });

  PassphraseOptions copyWith({
    int? wordCount,
    String? separator,
    bool? capitalize,
    bool? includeNumber,
  }) =>
      PassphraseOptions(
        wordCount: wordCount ?? this.wordCount,
        separator: separator ?? this.separator,
        capitalize: capitalize ?? this.capitalize,
        includeNumber: includeNumber ?? this.includeNumber,
      );
}

abstract final class PasswordGenerator {
  static final Random _random = Random.secure();

  static const String _upper = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const String _lower = 'abcdefghijklmnopqrstuvwxyz';
  static const String _digits = '0123456789';
  static const String _symbols = '!@#\$%^&*()_+-=[]{};:,.<>?';

  // Caractères qu'on confond à l'œil nu.
  static const String _ambiguous = '0O o1lI|';

  static String _strip(String source) {
    if (source.isEmpty) return source;
    final buffer = StringBuffer();
    for (final ch in source.split('')) {
      if (!_ambiguous.contains(ch)) buffer.write(ch);
    }
    return buffer.toString();
  }

  static String characters(CharacterOptions options) {
    if (!options.hasAnyType) {
      throw ArgumentError('Au moins un type de caractère doit être activé');
    }

    final pools = <String>[
      if (options.uppercase)
        options.avoidAmbiguous ? _strip(_upper) : _upper,
      if (options.lowercase)
        options.avoidAmbiguous ? _strip(_lower) : _lower,
      if (options.digits)
        options.avoidAmbiguous ? _strip(_digits) : _digits,
      if (options.symbols)
        options.avoidAmbiguous ? _strip(_symbols) : _symbols,
    ].where((p) => p.isNotEmpty).toList();

    if (pools.isEmpty) {
      throw ArgumentError('Aucun caractère disponible avec ces options');
    }

    final all = pools.join();
    final length = max(options.length, options.requireEachType ? pools.length : 1);
    final chars = <String>[];

    // Un caractère par famille d'abord, pour tenir la garantie.
    if (options.requireEachType) {
      for (final pool in pools) {
        chars.add(pool[_random.nextInt(pool.length)]);
      }
    }
    while (chars.length < length) {
      chars.add(all[_random.nextInt(all.length)]);
    }

    // Mélange de Fisher-Yates : sans lui, les caractères imposés resteraient en
    // tête et la position des familles serait prévisible.
    for (var i = chars.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final tmp = chars[i];
      chars[i] = chars[j];
      chars[j] = tmp;
    }

    return chars.join();
  }

  static String passphrase(PassphraseOptions options) {
    final words = <String>[];
    for (var i = 0; i < options.wordCount; i++) {
      var word = frenchWordList[_random.nextInt(frenchWordList.length)];
      if (options.capitalize) {
        word = word[0].toUpperCase() + word.substring(1);
      }
      words.add(word);
    }

    if (options.includeNumber && words.isNotEmpty) {
      // Un chiffre collé à un mot au hasard, pas systématiquement le dernier.
      final index = _random.nextInt(words.length);
      words[index] = '${words[index]}${_random.nextInt(10)}';
    }

    return words.join(options.separator);
  }

  /// Entropie d'une phrase de passe : `wordCount × log2(taille de la liste)`.
  /// Calculée séparément de l'estimateur de robustesse, qui raisonne par
  /// caractères et sous-estime très fortement une phrase.
  static double passphraseEntropy(PassphraseOptions options) {
    final perWord = log(frenchWordList.length) / ln2;
    var bits = options.wordCount * perWord;
    if (options.includeNumber) bits += log(10) / ln2;
    return bits;
  }
}

/// Liste de mots pour les phrases de passe.
///
/// Mots français courts, sans accent ni homophone gênant : une phrase de passe
/// doit se retenir *et* se retaper sans hésiter sur l'orthographe.
///
/// Attention à ne pas surestimer ce que ça donne : 278 mots ne font que
/// **8,1 bits par mot**, contre 12,9 pour la liste EFF de 7776 mots utilisée par
/// les vrais générateurs diceware. D'où le défaut à 6 mots (~49 bits) et non 5
/// (~41 bits). L'écran du générateur affiche l'entropie réellement calculée sur
/// la longueur de cette liste, jamais une valeur annoncée : si la liste grandit,
/// le chiffre suit tout seul.
///
/// Élargir cette liste à un millier de mots est le moyen le plus simple de
/// gagner en robustesse sans rallonger la phrase.
const List<String> frenchWordList = [
  'abri', 'acier', 'action', 'adresse', 'agenda', 'aigle', 'aiguille', 'aile',
  'album', 'alerte', 'algue', 'allure', 'amande', 'ancre', 'angle', 'animal',
  'anneau', 'arbre', 'arcade', 'archer', 'ardoise', 'argile', 'armure', 'arome',
  'arrivee', 'artiste', 'aspect', 'atelier', 'atlas', 'aurore', 'avenue',
  'avion', 'bagage', 'balcon', 'baleine', 'bambou', 'bandeau', 'banque',
  'barque', 'bassin', 'bateau', 'bijou', 'biscuit', 'blason', 'bocal', 'bois',
  'bonbon', 'bordure', 'bouchon', 'boucle', 'bougie', 'boussole', 'branche',
  'brique', 'brise', 'bronze', 'brosse', 'bruit', 'bureau', 'cabane', 'cactus',
  'cadeau', 'cadran', 'cahier', 'calcul', 'camion', 'campagne', 'canal',
  'canard', 'capitale', 'carbone', 'carotte', 'carre', 'carton', 'cascade',
  'casque', 'cavalier', 'cerise', 'cercle', 'chaine', 'chaise', 'chalet',
  'chameau', 'chapeau', 'charbon', 'chariot', 'chateau', 'chemin', 'cheval',
  'chiffre', 'chocolat', 'ciment', 'cinema', 'citron', 'clairon', 'clavier',
  'cloche', 'colline', 'colonne', 'combat', 'comete', 'compas', 'concert',
  'copie', 'corail', 'corde', 'cornet', 'costume', 'coton', 'coude', 'couleur',
  'coupole', 'courage', 'couronne', 'cousin', 'couteau', 'crayon', 'creme',
  'cristal', 'cuivre', 'cuisine', 'cygne', 'dauphin', 'dessin', 'diamant',
  'digue', 'dimanche', 'domaine', 'donjon', 'dossier', 'douane', 'drapeau',
  'ecaille', 'echelle', 'eclair', 'ecole', 'ecran', 'ecurie', 'effort',
  'elephant', 'emeraude', 'empire', 'energie', 'enigme', 'entree', 'epaule',
  'epice', 'epingle', 'equipe', 'escalier', 'espace', 'etage', 'etain',
  'etoile', 'etude', 'examen', 'exemple', 'facteur', 'falaise', 'famille',
  'fanion', 'farine', 'fauteuil', 'fenetre', 'ferme', 'festin', 'feuille',
  'ficelle', 'figure', 'filet', 'flacon', 'flamme', 'fleche', 'fleur', 'flocon',
  'foret', 'fortune', 'fossile', 'foulard', 'fourmi', 'fraise', 'frere',
  'fromage', 'fruit', 'fusee', 'galerie', 'galet', 'gant', 'garage', 'gateau',
  'gazon', 'geant', 'genie', 'girafe', 'givre', 'glace', 'gobelet', 'golfe',
  'gomme', 'gorge', 'goutte', 'grange', 'granit', 'grenier', 'griffe',
  'guitare', 'hameau', 'harpe', 'hauteur', 'herbe', 'heure', 'hibou',
  'histoire', 'hiver', 'horizon', 'horloge', 'hotel', 'huile', 'ile', 'image',
  'immeuble', 'indice', 'insecte', 'jambon', 'jardin', 'jaune', 'jeton',
  'jongleur', 'jouet', 'journal', 'jungle', 'jupon', 'kiosque', 'lagune',
  'lampe', 'lanterne', 'lapin', 'largeur', 'lettre', 'levier', 'lezard',
  'liberte', 'lierre', 'ligne', 'limace', 'lingot', 'lion', 'liquide', 'livre',
  'losange', 'lumiere', 'lunette', 'machine', 'madone', 'magasin', 'maison',
  'manche', 'mandarine', 'manoir', 'marbre', 'marche', 'marin', 'marteau',
  'masque', 'matelas', 'melodie', 'menthe', 'mercure', 'meridien', 'mesure',
  'metal', 'meuble', 'micro', 'miel', 'mimosa', 'minute', 'miroir', 'module',
];
