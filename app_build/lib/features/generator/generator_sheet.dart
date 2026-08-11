import 'package:flutter/material.dart';

import '../../core/design/app_theme.dart';
import '../../core/design/tokens.dart';
import '../../core/utils/password_generator.dart';
import '../../core/utils/password_strength.dart';
import '../../widgets/common.dart';
import '../../widgets/strength_meter.dart';

/// Générateur de mots de passe.
///
/// Tout est calculé sur l'appareil avec `Random.secure()`. La v1 demandait le
/// mot de passe au serveur, qui le renvoyait en HTTP clair — le mot de passe
/// était compromis avant même d'être enregistré.
///
/// Trois usages, un seul panneau : l'onglet Générateur, la feuille appelée
/// depuis l'édition d'un élément, et le bouton « régénérer ».
class GeneratorPanel extends StatefulWidget {
  const GeneratorPanel({super.key, this.onUse, this.compact = false});

  /// Fourni quand le panneau sert à remplir un champ. Absent dans l'onglet, où
  /// l'action est simplement « copier ».
  final ValueChanged<String>? onUse;

  /// En mode compact (feuille modale), on resserre les marges.
  final bool compact;

  @override
  State<GeneratorPanel> createState() => _GeneratorPanelState();
}

class _GeneratorPanelState extends State<GeneratorPanel> {
  GeneratorMode _mode = GeneratorMode.characters;
  CharacterOptions _charOptions = const CharacterOptions();
  PassphraseOptions _phraseOptions = const PassphraseOptions();

  String _value = '';

  /// Historique de session uniquement. Il n'est pas persisté : garder une liste
  /// de mots de passe générés en clair sur le disque annulerait l'intérêt du
  /// coffre chiffré.
  final List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _regenerate();
  }

  void _regenerate() {
    setState(() {
      if (_value.isNotEmpty) {
        _history.insert(0, _value);
        if (_history.length > 10) _history.removeLast();
      }
      _value = switch (_mode) {
        GeneratorMode.characters => _charOptions.hasAnyType
            ? PasswordGenerator.characters(_charOptions)
            : '',
        GeneratorMode.passphrase =>
          PasswordGenerator.passphrase(_phraseOptions),
      };
    });
  }

  /// L'estimateur par caractères sous-estime très fortement une phrase de
  /// passe : il ne voit pas les mots. Pour une phrase, l'entropie vient donc du
  /// calcul combinatoire sur la taille de la liste.
  PasswordStrength get _strength {
    if (_mode == GeneratorMode.passphrase) {
      final bits = PasswordGenerator.passphraseEntropy(_phraseOptions);
      return PasswordStrength(
        level: switch (bits) {
          < 28 => StrengthLevel.veryWeak,
          < 42 => StrengthLevel.weak,
          < 60 => StrengthLevel.fair,
          < 80 => StrengthLevel.strong,
          _ => StrengthLevel.veryStrong,
        },
        entropyBits: bits,
        warnings: const [],
      );
    }
    return PasswordStrengthEvaluator.evaluate(_value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    final pad = widget.compact ? Gap.xl : Gap.xl;

    return ListView(
      shrinkWrap: widget.compact,
      padding: EdgeInsets.fromLTRB(pad, Gap.sm, pad, widget.compact ? Gap.xl : 120),
      children: [
        _ResultCard(
          value: _value,
          onRegenerate: _regenerate,
          monospace: _mode == GeneratorMode.characters,
        ),
        const SizedBox(height: Gap.md),
        StrengthMeter(strength: _strength, showWarnings: false),

        if (_mode == GeneratorMode.passphrase) ...[
          const SizedBox(height: Gap.sm),
          Text(
            'Entropie calculée sur ${frenchWordList.length} mots : '
            '${(PasswordGenerator.passphraseEntropy(_phraseOptions) / _phraseOptions.wordCount).toStringAsFixed(1)} '
            'bits par mot.',
            style: text.bodySmall?.copyWith(color: c.textTertiary, fontSize: 11),
          ),
        ],

        const SizedBox(height: Gap.xxl),
        _ModeSelector(
          mode: _mode,
          onChanged: (m) {
            setState(() => _mode = m);
            _regenerate();
          },
        ),
        const SizedBox(height: Gap.xl),

        if (_mode == GeneratorMode.characters)
          _CharacterControls(
            options: _charOptions,
            onChanged: (o) {
              setState(() => _charOptions = o);
              _regenerate();
            },
          )
        else
          _PassphraseControls(
            options: _phraseOptions,
            onChanged: (o) {
              setState(() => _phraseOptions = o);
              _regenerate();
            },
          ),

        const SizedBox(height: Gap.xxl),
        if (widget.onUse != null)
          FilledButton.icon(
            onPressed: _value.isEmpty ? null : () => widget.onUse!(_value),
            icon: const Icon(Icons.check_rounded, size: 20),
            label: const Text('Utiliser ce mot de passe'),
          )
        else
          FilledButton.icon(
            onPressed: _value.isEmpty
                ? null
                : () => AppFeedback.copyValue(context, _value, 'Mot de passe'),
            icon: const Icon(Icons.content_copy_outlined, size: 20),
            label: const Text('Copier'),
          ),

        if (_history.isNotEmpty && !widget.compact) ...[
          const SizedBox(height: Gap.giant),
          const SectionLabel('Générés dans cette session'),
          Text(
            'Effacés à la fermeture de l’app : rien n’est écrit sur le disque.',
            style: text.bodySmall?.copyWith(color: c.textTertiary),
          ),
          const SizedBox(height: Gap.md),
          for (final past in _history)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: HairlineCard(
                sunken: true,
                padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.sm, Gap.sm, Gap.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        past,
                        style: SecretText.of(context, size: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copier',
                      onPressed: () =>
                          AppFeedback.copyValue(context, past, 'Mot de passe'),
                      icon: const Icon(Icons.content_copy_outlined, size: 18),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.value,
    required this.onRegenerate,
    required this.monospace,
  });

  final String value;
  final VoidCallback onRegenerate;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(Gap.xl),
      decoration: BoxDecoration(
        borderRadius: Radii.all(Radii.lg),
        color: c.surfaceSunken,
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('PROPOSITION', style: text.labelSmall),
              const Spacer(),
              IconButton(
                tooltip: 'Regénérer',
                onPressed: onRegenerate,
                icon: Icon(Icons.refresh_rounded, size: 20, color: c.primary),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          SelectableText(
            value.isEmpty ? 'Activez au moins un type de caractère' : value,
            style: monospace
                ? SecretText.of(context, size: 18)
                : text.titleLarge?.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.mode, required this.onChanged});

  final GeneratorMode mode;
  final ValueChanged<GeneratorMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Container(
      padding: const EdgeInsets.all(Gap.xs),
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.hairline),
      ),
      child: Row(
        children: [
          _segment(context, GeneratorMode.characters, 'Caractères', Icons.password_rounded),
          _segment(context, GeneratorMode.passphrase, 'Phrase', Icons.short_text_rounded),
        ],
      ),
    );
  }

  Widget _segment(
    BuildContext context,
    GeneratorMode value,
    String label,
    IconData icon,
  ) {
    final c = context.palette;
    final selected = mode == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.standard,
          padding: const EdgeInsets.symmetric(vertical: Gap.md),
          decoration: BoxDecoration(
            color: selected ? c.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: selected ? c.onPrimary : c.textTertiary,
              ),
              const SizedBox(width: Gap.sm),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: selected ? c.onPrimary : c.textSecondary,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CharacterControls extends StatelessWidget {
  const _CharacterControls({required this.options, required this.onChanged});

  final CharacterOptions options;
  final ValueChanged<CharacterOptions> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Longueur', style: text.titleMedium)),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.md,
                vertical: Gap.xs,
              ),
              decoration: BoxDecoration(
                color: c.primaryWash,
                borderRadius: BorderRadius.circular(Radii.xs),
              ),
              child: Text(
                '${options.length}',
                style: SecretText.of(context, size: 14)
                    .copyWith(color: c.primary, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        Slider(
          value: options.length.toDouble(),
          min: 8,
          max: 64,
          divisions: 56,
          onChanged: (v) => onChanged(options.copyWith(length: v.round())),
        ),
        const SizedBox(height: Gap.lg),

        HairlineCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _toggle(
                context,
                'Majuscules',
                'A – Z',
                options.uppercase,
                (v) => onChanged(options.copyWith(uppercase: v)),
              ),
              Divider(height: 1, color: c.hairline),
              _toggle(
                context,
                'Minuscules',
                'a – z',
                options.lowercase,
                (v) => onChanged(options.copyWith(lowercase: v)),
              ),
              Divider(height: 1, color: c.hairline),
              _toggle(
                context,
                'Chiffres',
                '0 – 9',
                options.digits,
                (v) => onChanged(options.copyWith(digits: v)),
              ),
              Divider(height: 1, color: c.hairline),
              _toggle(
                context,
                'Symboles',
                r'! @ # $ % …',
                options.symbols,
                (v) => onChanged(options.copyWith(symbols: v)),
              ),
            ],
          ),
        ),

        const SizedBox(height: Gap.lg),
        HairlineCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _toggle(
                context,
                'Éviter les caractères ambigus',
                'Écarte 0 O o 1 l I | — utile si vous devrez le recopier',
                options.avoidAmbiguous,
                (v) => onChanged(options.copyWith(avoidAmbiguous: v)),
              ),
              Divider(height: 1, color: c.hairline),
              _toggle(
                context,
                'Au moins un de chaque type',
                'Évite un tirage refusé par le site faute de chiffre',
                options.requireEachType,
                (v) => onChanged(options.copyWith(requireEachType: v)),
              ),
            ],
          ),
        ),

        if (!options.hasAnyType) ...[
          const SizedBox(height: Gap.lg),
          const InlineError(
            message: 'Activez au moins un type de caractère.',
          ),
        ],
      ],
    );
  }

  Widget _toggle(
    BuildContext context,
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onToggle,
  ) {
    return SwitchListTile(
      value: value,
      onChanged: onToggle,
      title: Text(title, style: Theme.of(context).textTheme.bodyLarge),
      subtitle: Text(
        subtitle,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: context.palette.textTertiary),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: Gap.lg),
    );
  }
}

class _PassphraseControls extends StatelessWidget {
  const _PassphraseControls({required this.options, required this.onChanged});

  final PassphraseOptions options;
  final ValueChanged<PassphraseOptions> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Nombre de mots', style: text.titleMedium)),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.md,
                vertical: Gap.xs,
              ),
              decoration: BoxDecoration(
                color: c.primaryWash,
                borderRadius: BorderRadius.circular(Radii.xs),
              ),
              child: Text(
                '${options.wordCount}',
                style: SecretText.of(context, size: 14)
                    .copyWith(color: c.primary, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        Slider(
          value: options.wordCount.toDouble(),
          min: 3,
          max: 12,
          divisions: 9,
          onChanged: (v) => onChanged(options.copyWith(wordCount: v.round())),
        ),
        const SizedBox(height: Gap.lg),

        Text('Séparateur', style: text.titleMedium),
        const SizedBox(height: Gap.md),
        Wrap(
          spacing: Gap.sm,
          children: [
            for (final sep in const ['-', '.', '_', ' ', ''])
              ChoiceChip(
                selected: options.separator == sep,
                onSelected: (_) => onChanged(options.copyWith(separator: sep)),
                label: Text(
                  switch (sep) {
                    '' => 'aucun',
                    ' ' => 'espace',
                    _ => sep,
                  },
                  style: SecretText.of(context, size: 13),
                ),
              ),
          ],
        ),

        const SizedBox(height: Gap.lg),
        HairlineCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              SwitchListTile(
                value: options.capitalize,
                onChanged: (v) => onChanged(options.copyWith(capitalize: v)),
                title: Text('Initiales en majuscule',
                    style: Theme.of(context).textTheme.bodyLarge),
                contentPadding: const EdgeInsets.symmetric(horizontal: Gap.lg),
              ),
              Divider(height: 1, color: c.hairline),
              SwitchListTile(
                value: options.includeNumber,
                onChanged: (v) => onChanged(options.copyWith(includeNumber: v)),
                title: Text('Ajouter un chiffre',
                    style: Theme.of(context).textTheme.bodyLarge),
                subtitle: Text(
                  'Pour les sites qui l’exigent',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: c.textTertiary),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: Gap.lg),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Feuille modale : renvoie le mot de passe choisi au champ appelant.
class GeneratorSheet extends StatelessWidget {
  const GeneratorSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Générer un mot de passe',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: GeneratorPanel(
                compact: true,
                onUse: (value) => Navigator.of(context).pop(value),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Onglet Générateur.
class GeneratorScreen extends StatelessWidget {
  const GeneratorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: context.palette.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xl, Gap.xl, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Générateur', style: text.headlineMedium),
                  const SizedBox(height: Gap.xxs),
                  Text(
                    'Tiré au sort sur cet appareil, jamais côté serveur.',
                    style: text.bodySmall
                        ?.copyWith(color: context.palette.textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Gap.xl),
            const Expanded(child: GeneratorPanel()),
          ],
        ),
      ),
    );
  }
}
