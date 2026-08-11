// Banc de rendu du design system.
//
//   flutter run -t lib/dev/design_gallery.dart -d chrome
//
// Ce fichier ne fait pas partie de l'app : c'est un point d'entrée séparé pour
// regarder les composants côte à côte dans les deux thèmes, sans avoir à
// déverrouiller un coffre.
//
// Attention : les données affichées ici sont des exemples figés, et l'écran
// « coffre » est une reproduction, pas le vrai `VaultScreen`. Il peut donc
// dériver du produit réel — c'est le prix d'un banc d'essai isolé. La référence
// reste l'app elle-même ; en cas de doute, les tests de `test/screens_test.dart`
// font foi.

import 'package:flutter/material.dart';

import '../core/design/app_theme.dart';
import '../core/design/monogram.dart';
import '../core/design/tokens.dart';
import '../core/utils/password_strength.dart';
import '../data/models/cipher.dart';
import '../widgets/secret_field.dart';
import '../widgets/strength_meter.dart';
import '../widgets/vault_item_tile.dart';

void main() => runApp(const GalleryApp());

class GalleryApp extends StatefulWidget {
  const GalleryApp({super.key});

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> {
  ThemeMode _mode = ThemeMode.dark;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PassVault — maquette',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _mode,
      home: GalleryHome(
        isDark: _mode == ThemeMode.dark,
        onToggleTheme: () => setState(
          () => _mode = _mode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
        ),
      ),
    );
  }
}

// ─────────────────────────── données d'exemple ───────────────────────────

final _sampleItems = <CipherItem>[
  const CipherItem(
    favorite: true,
    data: LoginData(
      name: 'GitHub',
      username: 'tannou-dev',
      password: 'K9\$mZq7#vLp2Wx',
      totp: 'JBSWY3DPEHPK3PXP',
      uris: [LoginUri(uri: 'https://github.com')],
    ),
  ),
  const CipherItem(
    data: LoginData(
      name: 'Orange Côte d’Ivoire',
      username: 'tannouab@gmail.com',
      password: 'azerty123',
      uris: [LoginUri(uri: 'https://orange.ci')],
    ),
  ),
  const CipherItem(
    data: CardData(
      name: 'Carte Ecobank',
      cardholderName: 'TANNOU ABOU',
      number: '4539876543219876',
      expMonth: '09',
      expYear: '2029',
      code: '447',
    ),
  ),
  const CipherItem(
    data: LoginData(
      name: 'Université Peleforo Gon',
      username: 'tannou.abou',
      password: 'Xy8!nQ4vB2#rTz',
      uris: [LoginUri(uri: 'https://upgc.edu.ci')],
    ),
  ),
  const CipherItem(
    data: SecureNoteData(
      name: 'Codes de récupération',
      notes: 'Codes de secours à usage unique.',
    ),
  ),
  const CipherItem(
    data: IdentityData(
      name: 'Identité principale',
      firstName: 'Tannou',
      lastName: 'Abou',
      email: 'tannouab@gmail.com',
    ),
  ),
];

// ─────────────────────────── mise en page ───────────────────────────

class GalleryHome extends StatelessWidget {
  const GalleryHome({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
  });

  final bool isDark;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            _GalleryBar(isDark: isDark, onToggleTheme: onToggleTheme),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Au-delà de 1100 px on montre l'écran et la référence côte à
                  // côte ; en dessous, seul l'écran, comme sur un téléphone.
                  final wide = constraints.maxWidth > 1100;
                  final phone = _PhoneFrame(child: const _MockVaultScreen());

                  if (!wide) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(Gap.xxl),
                      child: Center(child: phone),
                    );
                  }

                  return Row(
                    // stretch, pas start : sinon chaque panneau se dimensionne
                    // sur son contenu et le séparateur ne descend pas jusqu'en bas.
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 4,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(Gap.xxxl),
                          child: Center(child: phone),
                        ),
                      ),
                      Container(width: 1, color: c.hairline),
                      const Expanded(flex: 5, child: _ComponentReference()),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GalleryBar extends StatelessWidget {
  const _GalleryBar({required this.isDark, required this.onToggleTheme});

  final bool isDark;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.xxl, vertical: Gap.lg),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: Radii.all(Radii.sm),
              gradient: LinearGradient(
                colors: [c.primary, c.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.shield_rounded, size: 19, color: c.onPrimary),
          ),
          const SizedBox(width: Gap.md),
          Text('PassVault', style: text.titleLarge),
          const SizedBox(width: Gap.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 2),
            decoration: BoxDecoration(
              color: c.primaryWash,
              borderRadius: BorderRadius.circular(Radii.xs),
            ),
            child: Text(
              'maquette',
              style: text.labelMedium?.copyWith(color: c.primary, fontSize: 11),
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: onToggleTheme,
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              size: 18,
            ),
            label: Text(isDark ? 'Thème clair' : 'Thème sombre'),
          ),
        ],
      ),
    );
  }
}

/// Cadre de téléphone, pour juger les proportions réelles plutôt qu'un écran
/// large que l'app ne verra jamais sur Android.
class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Container(
      width: 390,
      height: 810,
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(38),
        border: Border.all(color: c.hairlineStrong, width: 8),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

// ─────────────────────────── écran du coffre ───────────────────────────

class _MockVaultScreen extends StatelessWidget {
  const _MockVaultScreen();

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: c.background,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xl, Gap.xl, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Mon coffre', style: text.headlineMedium),
                            const SizedBox(height: Gap.xxs),
                            Text(
                              '${_sampleItems.length} éléments · synchronisé',
                              style: text.bodySmall
                                  ?.copyWith(color: c.textTertiary),
                            ),
                          ],
                        ),
                      ),
                      _CircleAction(icon: Icons.lock_outline_rounded),
                    ],
                  ),
                  const SizedBox(height: Gap.xl),
                  const _SearchField(),
                  const SizedBox(height: Gap.lg),
                  const _SecurityBanner(),
                  const SizedBox(height: Gap.xl),
                  const _FilterRow(),
                  const SizedBox(height: Gap.lg),
                  Text('TOUS LES ÉLÉMENTS', style: text.labelSmall),
                  const SizedBox(height: Gap.md),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, 120),
            sliver: SliverList.separated(
              itemCount: _sampleItems.length,
              separatorBuilder: (_, _) => const SizedBox(height: Gap.sm),
              itemBuilder: (context, i) {
                final item = _sampleItems[i];
                final data = item.data;
                // Le rapport de sécurité marque les mots de passe faibles
                // directement dans la liste, là où l'utilisateur les voit.
                String? warning;
                if (data is LoginData && data.password.isNotEmpty) {
                  final s =
                      PasswordStrengthEvaluator.evaluate(data.password);
                  if (s.isCompromisedShape) warning = 'Mot de passe faible';
                }
                return VaultItemTile(
                  item: item,
                  warning: warning,
                  onTap: () {},
                  onCopyPassword: () {},
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 68),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: Radii.all(Radii.md),
            // Halo coloré sous l'action principale : c'est le seul endroit de
            // l'interface qui reçoit une ombre, ce qui la désigne sans ambiguïté.
            boxShadow: [
              BoxShadow(
                color: c.primary.withValues(alpha: 0.42),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: FloatingActionButton.extended(
            onPressed: () {},
            backgroundColor: c.primary,
            foregroundColor: c.onPrimary,
            elevation: 0,
            highlightElevation: 0,
            shape: RoundedRectangleBorder(borderRadius: Radii.all(Radii.md)),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Ajouter'),
          ),
        ),
      ),
      bottomNavigationBar: const _BottomNav(),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Container(
      width: TouchTarget.minimum,
      height: TouchTarget.minimum,
      decoration: BoxDecoration(
        color: c.surface,
        shape: BoxShape.circle,
        border: Border.all(color: c.hairline),
      ),
      child: Icon(icon, size: 20, color: c.textSecondary),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return TextField(
      decoration: InputDecoration(
        hintText: 'Rechercher un site, un identifiant…',
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: Gap.sm),
          child: Icon(Icons.mic_none_rounded, size: 20, color: c.textTertiary),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: Gap.md),
      ),
    );
  }
}

/// Bandeau du rapport de sécurité. Il annonce un nombre et une action, pas une
/// alerte vague — l'ancienne version affichait « Analyser » sans rien analyser.
class _SecurityBanner extends StatelessWidget {
  const _SecurityBanner();

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        borderRadius: Radii.all(Radii.lg),
        border: Border.all(color: c.warning.withValues(alpha: 0.34)),
        gradient: LinearGradient(
          colors: [
            c.warning.withValues(alpha: 0.14),
            c.warning.withValues(alpha: 0.04),
          ],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: c.warning.withValues(alpha: 0.18),
              borderRadius: Radii.all(Radii.sm),
            ),
            child: Icon(Icons.health_and_safety_outlined,
                size: 20, color: c.warning),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('2 mots de passe à revoir', style: text.titleMedium),
                const SizedBox(height: Gap.xxs),
                Text(
                  '1 faible · 1 réutilisé',
                  style: text.bodySmall?.copyWith(color: c.textTertiary),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: c.textTertiary),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow();

  @override
  Widget build(BuildContext context) {
    const filters = [
      ('Tous', Icons.apps_rounded, true),
      ('Favoris', Icons.star_rounded, false),
      ('Identifiants', Icons.key_rounded, false),
      ('Cartes', Icons.credit_card_rounded, false),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final (label, icon, selected) in filters)
            Padding(
              padding: const EdgeInsets.only(right: Gap.sm),
              child: _FilterChip(label: label, icon: icon, selected: selected),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.icon,
    required this.selected,
  });

  final String label;
  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    return AnimatedContainer(
      duration: Motion.fast,
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
      decoration: BoxDecoration(
        color: selected ? c.primaryWash : c.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected ? c.primary.withValues(alpha: 0.5) : c.hairline,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: selected ? c.primary : c.textTertiary),
          const SizedBox(width: Gap.sm),
          Text(
            label,
            style: text.labelMedium?.copyWith(
              color: selected ? c.primary : c.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav();

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    const tabs = [
      ('Coffre', Icons.lock_rounded, true),
      ('Générateur', Icons.auto_awesome_rounded, false),
      ('Sécurité', Icons.health_and_safety_rounded, false),
      ('Réglages', Icons.settings_rounded, false),
    ];

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      padding: const EdgeInsets.symmetric(vertical: Gap.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final (label, icon, active) in tabs)
            _NavItem(label: label, icon: icon, active: active),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.active,
  });

  final String label;
  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    final color = active ? c.primary : c.textTertiary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Indicateur en pastille derrière l'icône active : plus lisible qu'un
        // simple changement de teinte sur fond sombre.
        AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.lg,
            vertical: Gap.xs,
          ),
          decoration: BoxDecoration(
            color: active ? c.primaryWash : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Icon(icon, size: 21, color: color),
        ),
        const SizedBox(height: Gap.xxs),
        Text(
          label,
          style: text.labelMedium?.copyWith(color: color, fontSize: 11),
        ),
      ],
    );
  }
}

// ─────────────────────────── référence des composants ───────────────────────────

class _ComponentReference extends StatelessWidget {
  const _ComponentReference();

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(Gap.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Design system', style: text.headlineMedium),
          const SizedBox(height: Gap.xs),
          Text(
            'Plus Jakarta Sans pour les titres, Inter pour l’interface, '
            'JetBrains Mono pour les secrets — les trois réellement chargées.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: Gap.xxxl),

          _Section(
            title: 'Palette',
            child: Wrap(
              spacing: Gap.md,
              runSpacing: Gap.md,
              children: [
                _Swatch('primary', c.primary),
                _Swatch('accent', c.accent),
                _Swatch('success', c.success),
                _Swatch('warning', c.warning),
                _Swatch('danger', c.danger),
                _Swatch('surface', c.surface),
                _Swatch('sunken', c.surfaceSunken),
                _Swatch('background', c.background),
              ],
            ),
          ),

          _Section(
            title: 'Pastilles monogrammes',
            note: 'Teinte dérivée du domaine, calculée sur l’appareil. '
                'Aucune requête réseau, donc aucune fuite de la liste des comptes.',
            child: Wrap(
              spacing: Gap.md,
              runSpacing: Gap.md,
              children: const [
                _MonoSample('github.com'),
                _MonoSample('orange.ci'),
                _MonoSample('upgc.edu.ci'),
                _MonoSample('mail.google.com'),
                _MonoSample('netflix.com'),
                _MonoSample('ecobank.com'),
                _MonoSample('Ma banque'),
                _MonoSample('wave.com'),
              ],
            ),
          ),

          _Section(
            title: 'Valeurs secrètes',
            note: 'Masquées par flou : la longueur reste perceptible, '
                'et la révélation est un mouvement continu.',
            child: Column(
              children: [
                const SecretField(
                  label: 'Mot de passe',
                  value: 'K9\$mZq7#vLp2Wx',
                ),
                const SizedBox(height: Gap.md),
                const SecretField(
                  label: 'Mot de passe',
                  value: 'K9\$mZq7#vLp2Wx',
                  initiallyRevealed: true,
                ),
                const SizedBox(height: Gap.md),
                _TotpCard(),
              ],
            ),
          ),

          _Section(
            title: 'Jauge de robustesse',
            note: 'Le motif compte autant que la longueur : « azerty123456 » '
                'fait douze caractères et reste trivial.',
            child: Column(
              children: [
                for (final sample in const [
                  'azerty',
                  'azerty123456',
                  'Chocolat2024',
                  'Kx7\$mQ2vB',
                  'K9\$mZq7#vLp2Wx4!nT',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: Gap.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(sample, style: SecretText.of(context, size: 13)),
                        const SizedBox(height: Gap.sm),
                        StrengthMeter(
                          strength:
                              PasswordStrengthEvaluator.evaluate(sample),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          _Section(
            title: 'Actions',
            child: Wrap(
              spacing: Gap.md,
              runSpacing: Gap.md,
              children: [
                FilledButton(onPressed: () {}, child: const Text('Enregistrer')),
                FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: const Text('Générer'),
                ),
                OutlinedButton(onPressed: () {}, child: const Text('Annuler')),
                TextButton(onPressed: () {}, child: const Text('Mot de passe oublié')),
                FilledButton(
                  onPressed: null,
                  child: const Text('Désactivé'),
                ),
              ],
            ),
          ),

          _Section(
            title: 'Saisie',
            child: Column(
              children: [
                const TextField(
                  decoration: InputDecoration(
                    labelText: 'Nom de l’élément',
                    hintText: 'GitHub',
                  ),
                ),
                const SizedBox(height: Gap.md),
                TextField(
                  decoration: InputDecoration(
                    labelText: 'Adresse du site',
                    hintText: 'https://github.com',
                    prefixIcon: const Icon(Icons.link_rounded, size: 20),
                    suffixIcon: Icon(Icons.add_rounded,
                        size: 20, color: c.textTertiary),
                  ),
                ),
                const SizedBox(height: Gap.md),
                const TextField(
                  decoration: InputDecoration(
                    labelText: 'Mot de passe maître',
                    errorText: 'Mot de passe maître incorrect',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.note});

  final String title;
  final String? note;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = context.palette;

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.giant),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: text.labelSmall),
          const SizedBox(height: Gap.sm),
          if (note != null) ...[
            Text(note!, style: text.bodySmall?.copyWith(color: c.textTertiary)),
            const SizedBox(height: Gap.lg),
          ],
          child,
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.name, this.color);

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 84,
          height: 52,
          decoration: BoxDecoration(
            color: color,
            borderRadius: Radii.all(Radii.sm),
            border: Border.all(color: c.hairlineStrong),
          ),
        ),
        const SizedBox(height: Gap.xs),
        Text(name, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _MonoSample extends StatelessWidget {
  const _MonoSample(this.source);

  final String source;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      child: Column(
        children: [
          MonogramTile(source: source, size: 52),
          const SizedBox(height: Gap.sm),
          Text(
            source,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontSize: 11, color: context.palette.textTertiary),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Code TOTP avec son anneau de progression.
class _TotpCard extends StatefulWidget {
  @override
  State<_TotpCard> createState() => _TotpCardState();
}

class _TotpCardState extends State<_TotpCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 30),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.sm, Gap.md),
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: Radii.all(Radii.md),
        border: Border.all(color: c.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CODE À USAGE UNIQUE', style: text.labelSmall),
                const SizedBox(height: Gap.xs),
                // Groupé par trois : un code à six chiffres se recopie beaucoup
                // plus sûrement en « 418 249 » qu'en « 418249 ».
                Text('418 249',
                    style: SecretText.of(context, size: 21)
                        .copyWith(letterSpacing: 2)),
              ],
            ),
          ),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => TotpRing(
              progress: 1 - _controller.value,
              color: c.accent,
              size: 26,
            ),
          ),
          const SizedBox(width: Gap.sm),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.content_copy_outlined, size: 20),
          ),
        ],
      ),
    );
  }
}
