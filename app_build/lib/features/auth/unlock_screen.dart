import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/crypto/vault_crypto.dart';
import '../../core/design/app_theme.dart';
import '../../core/design/tokens.dart';
import '../../core/lock/biometric_unlock.dart';
import '../../core/settings/app_settings.dart';
import '../../data/api/api_client.dart';
import '../../data/vault_repository.dart';
import '../../widgets/common.dart';
import 'create_vault_screen.dart';

/// Écran de déverrouillage.
///
/// Le bouton biométrique n'apparaît que si une clé est effectivement stockée
/// dans le trousseau du système : on ne montre pas un raccourci qui échouerait.
/// Le mot de passe maître reste toujours disponible en dessous — la biométrie
/// est un raccourci, pas un remplacement.
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _obscure = true;
  bool _busy = false;
  String? _error;
  bool? _acceptsRegistration;

  /// Vrai si une clé est stockée derrière la biométrie. Tant que c'est `null`,
  /// on n'affiche rien : un bouton qui apparaît puis disparaît est pire que
  /// l'attente.
  bool? _biometricReady;

  @override
  void initState() {
    super.initState();
    final remembered = context.read<AppSettings>().lastEmail;
    if (remembered != null) {
      _emailController.text = remembered;
      // Le compte est connu : on met le curseur là où il y a quelque chose à
      // taper.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _passwordFocus.requestFocus();
      });
    }
    _probeServer();
    _probeBiometrics();
  }

  Future<void> _probeBiometrics() async {
    final store = context.read<BiometricUnlockStore>();
    final ready = await store.hasStoredKey && await store.isAvailable;
    if (!mounted) return;

    // L'e-mail rattaché à la clé prime : c'est le compte que la biométrie ouvre.
    if (ready) {
      final email = await store.storedEmail;
      if (mounted && email != null && _emailController.text.isEmpty) {
        _emailController.text = email;
      }
    }
    if (mounted) setState(() => _biometricReady = ready);
  }

  Future<void> _unlockWithBiometrics() async {
    final store = context.read<BiometricUnlockStore>();
    // Résolu avant le premier await : la boîte biométrique du système peut durer
    // longtemps, et ce State pourrait être démonté entre-temps.
    final vault = context.read<VaultRepository>();
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final data = await store.unlock();
      if (data == null) {
        // Refus, annulation, ou plus rien en mémoire : on ne dit pas laquelle,
        // et on laisse le champ mot de passe disponible.
        if (mounted) setState(() => _busy = false);
        return;
      }

      await vault.unlockWithStoredKey(
        sessionToken: data.sessionToken,
        vaultKeyBytes: data.vaultKeyBytes,
      );
    } on UnauthorizedFailure {
      // La session enregistrée a expiré ou a été révoquée depuis un autre
      // appareil : la clé stockée ne sert plus à rien, on la retire.
      await store.disable();
      if (!mounted) return;
      await context.read<AppSettings>().setBiometricUnlock(false);
      if (!mounted) return;
      setState(() {
        _biometricReady = false;
        _error = 'La session enregistrée a expiré. Entrez votre mot de passe '
            'maître pour rouvrir le coffre.';
      });
    } on WrongMasterPasswordException {
      await store.disable();
      if (!mounted) return;
      await context.read<AppSettings>().setBiometricUnlock(false);
      if (!mounted) return;
      setState(() {
        _biometricReady = false;
        _error = 'La clé enregistrée n’ouvre plus ce coffre. Utilisez votre '
            'mot de passe maître.';
      });
    } on ApiFailure catch (e) {
      _fail(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  /// Interroge le serveur pour savoir s'il accepte encore une inscription.
  /// Évite de proposer « créer un coffre » sur un serveur qui refusera.
  Future<void> _probeServer() async {
    try {
      final status = await context.read<VaultRepository>().serverStatus();
      if (mounted) setState(() => _acceptsRegistration = status.acceptsRegistration);
    } on ApiFailure {
      if (mounted) setState(() => _acceptsRegistration = null);
    }
  }

  Future<void> _unlock() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await context.read<VaultRepository>().unlock(
            email: email,
            masterPassword: password,
          );
      if (!mounted) return;
      await context.read<AppSettings>().rememberEmail(email);
      // Le mot de passe maître ne traîne pas dans un champ de saisie.
      _passwordController.clear();
    } on WrongMasterPasswordException {
      _fail('Mot de passe maître incorrect');
    } on UnauthorizedFailure {
      _fail('E-mail ou mot de passe maître incorrect');
    } on RateLimitedFailure catch (e) {
      _fail(
        'Trop de tentatives. Réessayez dans '
        '${(e.retryAfterSeconds / 60).ceil()} minute(s).',
      );
    } on NetworkFailure catch (e) {
      _fail('Serveur injoignable. ${e.message.split(':').first}');
    } on ApiFailure catch (e) {
      _fail(e.message);
    } catch (e, stack) {
      // Même filet qu'à la création : une exception hors ApiFailure laissait
      // l'écran figé sans explication.
      debugPrintStack(stackTrace: stack, label: 'unlock: $e');
      _fail('Échec inattendu : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fail(String message) {
    if (mounted) setState(() => _error = message);
  }

  Future<void> _openCreate() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreateVaultScreen()),
    );
    if (mounted) _probeServer();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    final repo = context.watch<VaultRepository>();
    final deriving = repo.status == VaultStatus.unlocking;

    return Scaffold(
      backgroundColor: c.background,
      body: Stack(
        children: [
          const _AmbientGlow(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Gap.xxl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _Brand(),
                      const SizedBox(height: Gap.giant),

                      Text('Déverrouiller le coffre', style: text.headlineMedium),
                      const SizedBox(height: Gap.sm),
                      Text(
                        'Votre mot de passe maître ne quitte jamais cet '
                        'appareil : il sert à recalculer la clé sur place.',
                        style: text.bodyMedium,
                      ),
                      const SizedBox(height: Gap.xxl),

                      TextField(
                        controller: _emailController,
                        enabled: !_busy,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Adresse e-mail',
                          prefixIcon: Icon(Icons.alternate_email_rounded, size: 20),
                        ),
                        onSubmitted: (_) => _passwordFocus.requestFocus(),
                      ),
                      const SizedBox(height: Gap.md),

                      TextField(
                        controller: _passwordController,
                        focusNode: _passwordFocus,
                        enabled: !_busy,
                        obscureText: _obscure,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: SecretText.of(context),
                        decoration: InputDecoration(
                          labelText: 'Mot de passe maître',
                          prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                          suffixIcon: IconButton(
                            tooltip: _obscure ? 'Afficher' : 'Masquer',
                            onPressed: () => setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 20,
                            ),
                          ),
                        ),
                        onSubmitted: (_) => _unlock(),
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: Gap.lg),
                        InlineError(message: _error!),
                      ],

                      const SizedBox(height: Gap.xl),
                      FilledButton.icon(
                        onPressed: _busy ? null : _unlock,
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.lock_open_rounded, size: 20),
                        label: Text(
                          deriving ? 'Dérivation de la clé…' : 'Déverrouiller',
                        ),
                      ),

                      if (deriving) ...[
                        const SizedBox(height: Gap.md),
                        Text(
                          'Argon2id tourne sur cet appareil. Quelques secondes '
                          'sur mobile, et c’est voulu : c’est ce qui rend une '
                          'attaque par force brute coûteuse.',
                          style: text.bodySmall?.copyWith(color: c.textTertiary),
                          textAlign: TextAlign.center,
                        ),
                      ],

                      if (_biometricReady == true) ...[
                        const SizedBox(height: Gap.lg),
                        _BiometricButton(
                          onPressed: _busy ? null : _unlockWithBiometrics,
                        ),
                      ],

                      if (_acceptsRegistration == true) ...[
                        const SizedBox(height: Gap.xxl),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Pas encore de coffre ?',
                              style: text.bodySmall
                                  ?.copyWith(color: c.textTertiary),
                            ),
                            TextButton(
                              onPressed: _busy ? null : _openCreate,
                              child: const Text('En créer un'),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: Gap.xl),
                      _ServerFooter(url: repo.serverUrl),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Raccourci biométrique. Présenté en second, sous le mot de passe maître :
/// c'est un confort, et l'écran ne doit pas suggérer qu'il remplace la seule
/// méthode qui fonctionne toujours.
class _BiometricButton extends StatelessWidget {
  const _BiometricButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(Icons.fingerprint_rounded, size: 22, color: c.accent),
      label: const Text('Déverrouiller par biométrie'),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: c.accent.withValues(alpha: 0.5)),
      ),
    );
  }
}

/// Halo diffus en fond. Deux taches floutées de la couleur d'accent : donne de
/// la profondeur à un écran presque vide sans ajouter d'élément à lire.
class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow();

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              top: -140,
              right: -110,
              child: _Blob(color: c.primary, size: 320),
            ),
            Positioned(
              bottom: -160,
              left: -120,
              child: _Blob(color: c.accent, size: 300),
            ),
          ],
        ),
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            borderRadius: Radii.all(Radii.lg),
            gradient: LinearGradient(
              colors: [c.primary, c.accent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: c.primary.withValues(alpha: 0.4),
                blurRadius: 26,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Icon(Icons.shield_rounded, size: 32, color: c.onPrimary),
        ),
        const SizedBox(height: Gap.lg),
        Text('PassVault', style: text.headlineSmall),
      ],
    );
  }
}

/// Rappelle à quel serveur on parle. Sur un coffre auto-hébergé, savoir où
/// partent ses données n'est pas un détail.
class _ServerFooter extends StatelessWidget {
  const _ServerFooter({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final insecure = isInsecureServerUrl(url);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              insecure ? Icons.lock_open_rounded : Icons.dns_outlined,
              size: 13,
              color: insecure ? c.warning : c.textTertiary,
            ),
            const SizedBox(width: Gap.sm),
            Flexible(
              child: Text(
                url.replaceFirst(RegExp(r'^https?://'), ''),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: c.textTertiary, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (insecure) ...[
          const SizedBox(height: Gap.sm),
          Text(
            'Connexion en HTTP : le contenu du coffre reste chiffré, mais '
            'l’adresse du serveur et vos métadonnées circulent en clair.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: c.warning, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
