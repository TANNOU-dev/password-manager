import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/crypto/kdf_params.dart';
import '../../core/design/app_theme.dart';
import '../../core/design/tokens.dart';
import '../../core/settings/app_settings.dart';
import '../../core/utils/password_strength.dart';
import '../../data/api/api_client.dart';
import '../../data/vault_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/strength_meter.dart';

/// Création d'un coffre.
///
/// L'écran doit dire une chose désagréable et la dire clairement : le mot de
/// passe maître n'est récupérable par personne. C'est la conséquence directe du
/// zero-knowledge — le serveur ne détient rien qui permette de le réinitialiser.
/// L'ancienne app affichait « Contactez l'administrateur pour réinitialiser »,
/// ce qui était faux même en v1.
class CreateVaultScreen extends StatefulWidget {
  const CreateVaultScreen({super.key});

  @override
  State<CreateVaultScreen> createState() => _CreateVaultScreenState();
}

class _CreateVaultScreenState extends State<CreateVaultScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _tokenController = TextEditingController();

  bool _obscure = true;
  bool _busy = false;
  bool _acknowledged = false;
  bool _showToken = false;
  String? _error;

  PasswordStrength _strength = PasswordStrengthEvaluator.evaluate('');

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_onPasswordChanged);
  }

  @override
  void dispose() {
    _passwordController.removeListener(_onPasswordChanged);
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  void _onPasswordChanged() {
    setState(() {
      _strength = PasswordStrengthEvaluator.evaluate(_passwordController.text);
    });
  }

  bool get _matches =>
      _confirmController.text.isNotEmpty &&
      _confirmController.text == _passwordController.text;

  /// On refuse de créer un coffre derrière un mot de passe trivial. Ce n'est pas
  /// du zèle : ce mot de passe est la seule chose qui protège tout le reste, et
  /// il n'existe aucun moyen de le remplacer après une fuite du coffre.
  bool get _strongEnough => _strength.level.index >= StrengthLevel.fair.index;

  bool get _canSubmit =>
      !_busy &&
      _emailController.text.trim().isNotEmpty &&
      _matches &&
      _strongEnough &&
      _acknowledged;

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final email = _emailController.text.trim();
    try {
      await context.read<VaultRepository>().createVault(
            email: email,
            masterPassword: _passwordController.text,
            registrationToken: _tokenController.text.trim().isEmpty
                ? null
                : _tokenController.text.trim(),
          );
      if (!mounted) return;
      await context.read<AppSettings>().rememberEmail(email);
      if (!mounted) return;
      // Le coffre est ouvert : la porte d'entrée de l'app basculera d'elle-même
      // sur la coquille principale.
      Navigator.of(context).pop();
    } on ConflictFailure {
      _fail('Un coffre existe déjà pour cet e-mail.');
    } on NetworkFailure catch (e) {
      _fail('Serveur injoignable. ${e.message.split(':').first}');
    } on ApiFailure catch (e) {
      _fail(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _fail(String message) {
    if (mounted) setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    const kdf = KdfParams.argon2idDefault;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: const Text('Créer un coffre')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.sm, Gap.xl, Gap.giant),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _emailController,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Adresse e-mail',
                    helperText: 'Sert d’identifiant de compte, pas de contact.',
                    prefixIcon: Icon(Icons.alternate_email_rounded, size: 20),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: Gap.xl),

                TextField(
                  controller: _passwordController,
                  enabled: !_busy,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: SecretText.of(context),
                  decoration: InputDecoration(
                    labelText: 'Mot de passe maître',
                    prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Gap.md),
                StrengthMeter(strength: _strength),

                if (_strength.level != StrengthLevel.empty && !_strongEnough) ...[
                  const SizedBox(height: Gap.md),
                  Text(
                    'Il faut au moins « Moyen » pour continuer. Ce mot de passe '
                    'protège tout le coffre et personne ne peut le remplacer.',
                    style: text.bodySmall?.copyWith(color: c.warning),
                  ),
                ],

                const SizedBox(height: Gap.xl),
                TextField(
                  controller: _confirmController,
                  enabled: !_busy,
                  obscureText: _obscure,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: SecretText.of(context),
                  decoration: InputDecoration(
                    labelText: 'Confirmer le mot de passe maître',
                    prefixIcon: const Icon(Icons.lock_reset_rounded, size: 20),
                    errorText: _confirmController.text.isEmpty || _matches
                        ? null
                        : 'Les deux saisies diffèrent',
                    suffixIcon: _matches
                        ? Icon(Icons.check_rounded, size: 20, color: c.success)
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),

                const SizedBox(height: Gap.xxl),
                _NoRecoveryNotice(
                  acknowledged: _acknowledged,
                  onChanged: (v) => setState(() => _acknowledged = v),
                ),

                const SizedBox(height: Gap.xl),
                HairlineCard(
                  sunken: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SectionLabel('Protection de la clé'),
                      Row(
                        children: [
                          Icon(Icons.memory_rounded, size: 16, color: c.accent),
                          const SizedBox(width: Gap.sm),
                          Expanded(
                            child: Text(kdf.label, style: text.bodySmall),
                          ),
                        ],
                      ),
                      const SizedBox(height: Gap.sm),
                      Text(
                        'La clé est dérivée sur cet appareil. Le serveur ne '
                        'reçoit qu’une empreinte qui ne permet pas de la '
                        'reconstruire.',
                        style: text.bodySmall
                            ?.copyWith(color: c.textTertiary, fontSize: 12),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: Gap.lg),
                // Replié par défaut : n'a de sens que si le serveur a été
                // configuré avec PASSVAULT_REGISTRATION_TOKEN.
                if (_showToken)
                  TextField(
                    controller: _tokenController,
                    enabled: !_busy,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Jeton d’inscription',
                      helperText: 'Uniquement si le serveur en exige un.',
                      prefixIcon: Icon(Icons.vpn_key_outlined, size: 20),
                    ),
                  )
                else
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _showToken = true),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Le serveur exige un jeton'),
                    ),
                  ),

                if (_error != null) ...[
                  const SizedBox(height: Gap.lg),
                  InlineError(message: _error!),
                ],

                const SizedBox(height: Gap.xxl),
                FilledButton.icon(
                  onPressed: _canSubmit ? _create : null,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.shield_outlined, size: 20),
                  label: Text(_busy ? 'Création du coffre…' : 'Créer le coffre'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Case à cocher explicite sur l'absence de récupération. Une case plutôt qu'un
/// simple paragraphe : on veut que l'utilisateur ait à confirmer qu'il l'a lu.
class _NoRecoveryNotice extends StatelessWidget {
  const _NoRecoveryNotice({required this.acknowledged, required this.onChanged});

  final bool acknowledged;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        borderRadius: Radii.all(Radii.lg),
        color: c.warning.withValues(alpha: 0.08),
        border: Border.all(color: c.warning.withValues(alpha: 0.34)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 18, color: c.warning),
              const SizedBox(width: Gap.sm),
              Text('Aucune récupération possible', style: text.titleMedium),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Text(
            'Le serveur ne stocke rien qui permette de retrouver votre mot de '
            'passe maître : c’est ce qui garantit qu’il ne peut pas lire votre '
            'coffre. Si vous l’oubliez, le contenu est définitivement perdu, y '
            'compris pour vous.',
            style: text.bodySmall,
          ),
          const SizedBox(height: Gap.md),
          InkWell(
            onTap: () => onChanged(!acknowledged),
            borderRadius: Radii.all(Radii.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.sm),
              child: Row(
                children: [
                  Checkbox(
                    value: acknowledged,
                    onChanged: (v) => onChanged(v ?? false),
                    side: BorderSide(color: c.hairlineStrong),
                  ),
                  Expanded(
                    child: Text(
                      'J’ai compris et je conserve ce mot de passe ailleurs.',
                      style: text.bodyMedium?.copyWith(color: c.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
