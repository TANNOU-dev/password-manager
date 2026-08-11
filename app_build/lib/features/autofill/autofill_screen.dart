import 'package:flutter/material.dart';
import 'package:flutter_autofill_service/flutter_autofill_service.dart';
import 'package:provider/provider.dart';

import '../../core/crypto/vault_crypto.dart';
import '../../core/design/app_theme.dart';
import '../../core/design/monogram.dart';
import '../../core/design/tokens.dart';
import '../../core/lock/biometric_unlock.dart';
import '../../core/settings/app_settings.dart';
import '../../data/api/api_client.dart';
import '../../data/models/cipher.dart';
import '../../data/vault_repository.dart';
import '../../widgets/common.dart';
import 'uri_matcher.dart';

/// Écran affiché quand Android demande un identifiant à PassVault.
///
/// Ce n'est pas l'app normale : le processus est lancé par le service de
/// remplissage, sur un point d'entrée séparé, et il n'a qu'une chose à faire —
/// rendre un couple identifiant / mot de passe, ou rien.
///
/// Deux différences de fond avec le coffre habituel :
///
/// * le coffre est presque toujours **verrouillé** ici, puisque le processus
///   vient de démarrer. On propose donc le déverrouillage sur place, biométrie
///   en premier ;
/// * on n'affiche **que** les entrées qui correspondent au demandeur. Montrer
///   tout le coffre donnerait l'occasion de remplir le mauvais compte dans la
///   mauvaise application.
class AutofillScreen extends StatefulWidget {
  const AutofillScreen({super.key});

  @override
  State<AutofillScreen> createState() => _AutofillScreenState();
}

class _AutofillScreenState extends State<AutofillScreen> {
  final _service = AutofillService();
  final _passwordController = TextEditingController();

  AutofillMetadata? _metadata;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _biometricReady = false;

  @override
  void initState() {
    super.initState();
    _loadRequest();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadRequest() async {
    // Résolu avant le premier await : le service peut être lent à répondre.
    final store = context.read<BiometricUnlockStore>();
    final metadata = await _service.autofillMetadata;
    final ready = await store.hasStoredKey && await store.isAvailable;
    if (!mounted) return;
    setState(() {
      _metadata = metadata;
      _biometricReady = ready;
      _loading = false;
    });

    // Si la biométrie est prête on la propose tout de suite : l'utilisateur est
    // déjà en train de remplir un formulaire, un appui de plus est de trop.
    if (ready) await _unlockWithBiometrics();
  }

  /// Un navigateur fournit un domaine web ; une application native, son paquet.
  ///
  /// Le schéma est repris tel que le fournit Android quand il est connu : forcer
  /// `https` sur un formulaire servi en clair masquerait le fait que le site
  /// n'est pas chiffré.
  String get _requestedUri {
    final domains = _metadata?.webDomains ?? const <AutofillWebDomain>{};
    if (domains.isEmpty) return '';
    final web = domains.first;
    if (web.domain.contains('://')) return web.domain;
    return '${web.scheme ?? 'https'}://${web.domain}';
  }

  String? get _requestedPackage {
    final packages = _metadata?.packageNames ?? const <String>{};
    return packages.isEmpty ? null : packages.first;
  }

  /// Qui demande. L'information la plus importante de l'écran : c'est elle qui
  /// permet de repérer une application qui se fait passer pour une autre.
  String get _requesterLabel {
    final uri = _requestedUri;
    if (uri.isNotEmpty) return UriMatcher.hostOf(uri) ?? uri;
    return _requestedPackage ?? 'application inconnue';
  }

  Future<void> _unlockWithBiometrics() async {
    final store = context.read<BiometricUnlockStore>();
    final vault = context.read<VaultRepository>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await store.unlock();
      if (data == null) return;
      await vault.unlockWithStoredKey(
        sessionToken: data.sessionToken,
        vaultKeyBytes: data.vaultKeyBytes,
      );
    } on UnauthorizedFailure {
      await store.disable();
      if (mounted) {
        setState(() {
          _biometricReady = false;
          _error = 'La session enregistrée a expiré. Entrez votre mot de passe '
              'maître.';
        });
      }
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlockWithPassword() async {
    final email = context.read<AppSettings>().lastEmail;
    if (email == null || _passwordController.text.isEmpty) return;
    final vault = context.read<VaultRepository>();

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await vault.unlock(email: email, masterPassword: _passwordController.text);
      _passwordController.clear();
    } on WrongMasterPasswordException {
      if (mounted) setState(() => _error = 'Mot de passe maître incorrect');
    } on UnauthorizedFailure {
      if (mounted) setState(() => _error = 'Mot de passe maître incorrect');
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Rend l'identifiant choisi au service, qui remplit les champs et referme.
  Future<void> _fillWith(CipherItem item) async {
    final data = item.data;
    if (data is! LoginData) return;
    await _service.resultWithDataset(
      label: data.name,
      username: data.username,
      password: data.password,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final vault = context.watch<VaultRepository>();

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Text('Remplissage automatique'),
        leading: IconButton(
          tooltip: 'Annuler',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding:
                    const EdgeInsets.fromLTRB(Gap.xl, Gap.sm, Gap.xl, Gap.giant),
                children: [
                  _RequesterCard(
                    label: _requesterLabel,
                    isWebDomain: _requestedUri.isNotEmpty,
                  ),
                  const SizedBox(height: Gap.xl),
                  if (_error != null) ...[
                    InlineError(message: _error!),
                    const SizedBox(height: Gap.xl),
                  ],
                  if (!vault.isUnlocked)
                    _UnlockBlock(
                      busy: _busy,
                      biometricReady: _biometricReady,
                      controller: _passwordController,
                      knownEmail: context.read<AppSettings>().lastEmail,
                      onBiometric: _unlockWithBiometrics,
                      onPassword: _unlockWithPassword,
                    )
                  else
                    ..._candidates(vault),
                ],
              ),
      ),
    );
  }

  List<Widget> _candidates(VaultRepository vault) {
    final matches = UriMatcher.candidatesFor(
      vault.items,
      _requestedUri,
      packageName: _requestedPackage,
    );

    if (matches.isEmpty) {
      return [
        const SizedBox(height: Gap.xxl),
        EmptyState(
          icon: Icons.search_off_rounded,
          title: 'Aucun identifiant pour ce demandeur',
          message: 'Votre coffre ne contient rien d’enregistré pour '
              '$_requesterLabel. Ajoutez cette adresse à un élément existant '
              'pour qu’il soit proposé ici.',
        ),
      ];
    }

    return [
      SectionLabel(
        '${matches.length} identifiant${matches.length > 1 ? 's' : ''} '
        'correspondant${matches.length > 1 ? 's' : ''}',
      ),
      for (final item in matches)
        Padding(
          padding: const EdgeInsets.only(bottom: Gap.sm),
          child: _CandidateTile(item: item, onTap: () => _fillWith(item)),
        ),
      const SizedBox(height: Gap.lg),
      Text(
        'Seules les entrées dont une adresse correspond à ce demandeur sont '
        'listées. C’est volontaire : cela évite de remplir le mauvais compte '
        'dans la mauvaise application.',
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: context.palette.textTertiary),
      ),
    ];
  }
}

class _RequesterCard extends StatelessWidget {
  const _RequesterCard({required this.label, required this.isWebDomain});

  final String label;
  final bool isWebDomain;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    return HairlineCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: c.primaryWash,
              borderRadius: Radii.all(Radii.sm),
            ),
            child: Icon(
              isWebDomain ? Icons.language_rounded : Icons.android_rounded,
              size: 21,
              color: c.primary,
            ),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isWebDomain ? 'Site demandeur' : 'Application demandeuse',
                  style: text.labelSmall,
                ),
                const SizedBox(height: Gap.xxs),
                Text(
                  label,
                  style: text.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UnlockBlock extends StatelessWidget {
  const _UnlockBlock({
    required this.busy,
    required this.biometricReady,
    required this.controller,
    required this.knownEmail,
    required this.onBiometric,
    required this.onPassword,
  });

  final bool busy;
  final bool biometricReady;
  final TextEditingController controller;
  final String? knownEmail;
  final VoidCallback onBiometric;
  final VoidCallback onPassword;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    if (knownEmail == null) {
      return const EmptyState(
        icon: Icons.lock_outline_rounded,
        title: 'Coffre non configuré',
        message: 'Ouvrez PassVault une première fois pour créer ou '
            'déverrouiller votre coffre.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Coffre verrouillé', style: text.titleLarge),
        const SizedBox(height: Gap.sm),
        Text(
          'Déverrouillez-le pour voir les identifiants correspondants.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: Gap.xl),
        if (biometricReady) ...[
          FilledButton.icon(
            onPressed: busy ? null : onBiometric,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.fingerprint_rounded, size: 22),
            label: const Text('Déverrouiller par biométrie'),
          ),
          const SizedBox(height: Gap.xl),
          Row(
            children: [
              Expanded(child: Divider(color: c.hairline)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                child: Text('ou', style: text.bodySmall),
              ),
              Expanded(child: Divider(color: c.hairline)),
            ],
          ),
          const SizedBox(height: Gap.xl),
        ],
        TextField(
          controller: controller,
          enabled: !busy,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          style: SecretText.of(context),
          decoration: InputDecoration(
            labelText: 'Mot de passe maître',
            helperText: knownEmail,
            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
          ),
          onSubmitted: (_) => onPassword(),
        ),
        const SizedBox(height: Gap.lg),
        OutlinedButton(
          onPressed: busy ? null : onPassword,
          child: const Text('Déverrouiller'),
        ),
      ],
    );
  }
}

/// Ligne d'un identifiant proposé. Volontairement dépouillée : pas de copie, pas
/// de menu. Un seul geste possible, remplir.
class _CandidateTile extends StatelessWidget {
  const _CandidateTile({required this.item, required this.onTap});

  final CipherItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    final data = item.data as LoginData;

    return Material(
      color: c.surface,
      borderRadius: Radii.all(Radii.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.all(Radii.lg),
        child: Container(
          padding: const EdgeInsets.all(Gap.md),
          decoration: BoxDecoration(
            borderRadius: Radii.all(Radii.lg),
            border: Border.all(color: c.hairline),
          ),
          child: Row(
            children: [
              MonogramTile(source: data.primaryHost ?? data.name),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            data.name,
                            style: text.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (item.favorite) ...[
                          const SizedBox(width: Gap.sm),
                          Icon(Icons.star_rounded, size: 15, color: c.warning),
                        ],
                      ],
                    ),
                    const SizedBox(height: Gap.xxs),
                    Text(
                      data.username.isEmpty
                          ? 'Aucun identifiant'
                          : data.username,
                      style: text.bodySmall?.copyWith(color: c.textTertiary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, size: 19, color: c.primary),
            ],
          ),
        ),
      ),
    );
  }
}
