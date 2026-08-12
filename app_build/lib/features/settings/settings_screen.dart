import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/crypto/vault_crypto.dart';
import '../../core/design/app_theme.dart';
import '../../core/design/tokens.dart';
import '../../core/lock/biometric_unlock.dart';
import '../../core/lock/clipboard_guard.dart';
import '../../core/settings/app_settings.dart';
import '../../core/settings/lock_settings.dart';
import '../../core/utils/password_strength.dart';
import '../../data/api/api_client.dart';
import '../../data/api/coffort_api.dart';
import '../../data/vault_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/strength_meter.dart';
import '../autofill/autofill_setting.dart';
import '../transfer/export_screen.dart';
import '../transfer/import_screen.dart';
import '../vault/folder_sheet.dart';
import '../vault/trash_screen.dart';

/// Réglages.
///
/// Chaque entrée est relue par du code qui agit : `LockController` pour le
/// verrouillage, `ClipboardGuard` pour le presse-papiers, `BiometricUnlockStore`
/// pour la biométrie. Dans la v1, trois interrupteurs sur quatre ne changeaient
/// qu'un booléen local que personne ne consultait.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    final repo = context.watch<VaultRepository>();
    final settings = context.watch<AppSettings>();
    final profile = repo.profile;

    return Scaffold(
      backgroundColor: c.background,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xl, Gap.xl, 120),
        children: [
          Text('Réglages', style: text.headlineMedium),
          const SizedBox(height: Gap.xxl),

          // ── Coffre ──
          const SectionLabel('Coffre'),
          HairlineCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.alternate_email_rounded),
                  title: const Text('Compte'),
                  subtitle: Text(profile?.email ?? '—'),
                ),
                Divider(height: 1, color: c.hairline),
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('Dossiers'),
                  subtitle: Text(
                    '${repo.folders.length} dossier'
                    '${repo.folders.length > 1 ? 's' : ''}',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const FolderSheet(),
                  ),
                ),
                Divider(height: 1, color: c.hairline),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Corbeille'),
                  subtitle: Text(
                    '${repo.trash.length} élément'
                    '${repo.trash.length > 1 ? 's' : ''}',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TrashScreen()),
                  ),
                ),
              ],
            ),
          ),

          // ── Remplissage automatique ──
          const SizedBox(height: Gap.xxl),
          const SectionLabel('Remplissage automatique'),
          const AutofillSettingCard(),

          // ── Verrouillage ──
          const SizedBox(height: Gap.xxl),
          const SectionLabel('Verrouillage'),
          const _LockSection(),

          // ── Transfert ──
          const SizedBox(height: Gap.xxl),
          const SectionLabel('Sauvegarde et transfert'),
          HairlineCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.download_outlined),
                  title: const Text('Importer un coffre'),
                  subtitle: const Text(
                    'Bitwarden, KeePass, Chrome, LastPass, 1Password…',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ImportScreen()),
                  ),
                ),
                Divider(height: 1, color: c.hairline),
                ListTile(
                  leading: const Icon(Icons.upload_outlined),
                  title: const Text('Exporter le coffre'),
                  subtitle: const Text(
                    'Sauvegarde chiffrée, ou export en clair pour migrer',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ExportScreen()),
                  ),
                ),
              ],
            ),
          ),

          // ── Apparence ──
          const SizedBox(height: Gap.xxl),
          const SectionLabel('Apparence'),
          HairlineCard(
            padding: EdgeInsets.zero,
            // La valeur et le rappel sont désormais portés par l'ancêtre
            // RadioGroup, plus par chaque tuile.
            child: RadioGroup<ThemeMode>(
              groupValue: settings.themeMode,
              onChanged: (v) {
                if (v != null) settings.setThemeMode(v);
              },
              child: Column(
                children: [
                  for (final mode in ThemeMode.values)
                    RadioListTile<ThemeMode>(
                      value: mode,
                      title: Text(switch (mode) {
                        ThemeMode.system => 'Suivre le système',
                        ThemeMode.light => 'Clair',
                        ThemeMode.dark => 'Sombre',
                      }),
                    ),
                ],
              ),
            ),
          ),

          // ── Chiffrement ──
          const SizedBox(height: Gap.xxl),
          const SectionLabel('Chiffrement'),
          HairlineCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.memory_rounded, size: 17, color: c.accent),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      child: Text(
                        profile?.kdf.label ?? '—',
                        style: text.bodyMedium?.copyWith(color: c.textPrimary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.sm),
                Row(
                  children: [
                    Icon(Icons.lock_rounded, size: 17, color: c.accent),
                    const SizedBox(width: Gap.sm),
                    Expanded(
                      child: Text(
                        'AES-256-GCM par élément',
                        style: text.bodyMedium?.copyWith(color: c.textPrimary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Gap.md),
                Text(
                  'La clé est dérivée sur cet appareil et n’en sort jamais. Le '
                  'serveur ne stocke que des blobs qu’il ne peut pas ouvrir.',
                  style: text.bodySmall?.copyWith(color: c.textTertiary),
                ),
              ],
            ),
          ),

          // ── Sécurité du compte ──
          const SizedBox(height: Gap.xxl),
          const SectionLabel('Sécurité du compte'),
          HairlineCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.password_rounded),
                  title: const Text('Changer le mot de passe maître'),
                  subtitle: const Text(
                    'Réenveloppe la clé, sans rechiffrer le coffre',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const _ChangePasswordSheet(),
                  ),
                ),
                Divider(height: 1, color: c.hairline),
                ListTile(
                  leading: const Icon(Icons.devices_rounded),
                  title: const Text('Appareils connectés'),
                  subtitle: const Text('Voir et révoquer les sessions'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => const _SessionsSheet(),
                  ),
                ),
              ],
            ),
          ),

          // ── Actions dangereuses ──
          const SizedBox(height: Gap.giant),
          OutlinedButton.icon(
            onPressed: () => repo.lock(),
            icon: Icon(Icons.lock_outline_rounded, size: 20, color: c.warning),
            label: Text('Verrouiller', style: TextStyle(color: c.warning)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: c.warning.withValues(alpha: 0.5)),
            ),
          ),
          const SizedBox(height: Gap.md),
          OutlinedButton.icon(
            onPressed: () async {
              // Le raccourci biométrique repose sur ce jeton : il part avec lui.
              await context.read<BiometricUnlockStore>().disable();
              if (!context.mounted) return;
              await settings.setBiometricUnlock(false);
              if (!context.mounted) return;
              try {
                await repo.logout();
              } on ApiFailure catch (e) {
                if (context.mounted) AppFeedback.failure(context, e.message);
              }
            },
            icon: const Icon(Icons.logout_rounded, size: 20),
            label: const Text('Se déconnecter de cet appareil'),
          ),
          const SizedBox(height: Gap.md),
          OutlinedButton.icon(
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              builder: (_) => const _DeleteVaultSheet(),
            ),
            icon: Icon(Icons.delete_forever_rounded, size: 20, color: c.danger),
            label: Text('Supprimer le coffre', style: TextStyle(color: c.danger)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: c.danger.withValues(alpha: 0.5)),
            ),
          ),

          const SizedBox(height: Gap.giant),
          Center(
            child: Text(
              'Coffort · coffre zero-knowledge',
              style: text.bodySmall?.copyWith(color: c.textTertiary, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

/// Réglages de verrouillage.
///
/// La biométrie est un `FutureBuilder` sur l'état réel de l'appareil : on ne
/// propose pas un interrupteur qui échouerait faute d'empreinte enrôlée.
class _LockSection extends StatefulWidget {
  const _LockSection();

  @override
  State<_LockSection> createState() => _LockSectionState();
}

class _LockSectionState extends State<_LockSection> {
  late Future<_BiometricState> _biometricState;

  @override
  void initState() {
    super.initState();
    _biometricState = _readBiometricState();
  }

  Future<_BiometricState> _readBiometricState() async {
    final store = context.read<BiometricUnlockStore>();
    return _BiometricState(
      available: await store.isAvailable,
      enrolled: await store.hasStoredKey,
      description: await store.describeAvailable(),
    );
  }

  void _refresh() {
    // Corps en bloc, et non une flèche : `=> x = f()` renvoie la valeur
    // affectée, donc un Future. Flutter refuse un callback de setState qui
    // renvoie un Future — et comme il lève *après* avoir exécuté le callback
    // mais *avant* markNeedsBuild, l'état changeait sans que l'écran se
    // redessine. L'interrupteur biométrique restait donc sur sa position
    // précédente alors que l'action avait réussi.
    setState(() {
      _biometricState = _readBiometricState();
    });
  }

  Future<void> _toggleBiometric(bool enable) async {
    final store = context.read<BiometricUnlockStore>();
    final settings = context.read<AppSettings>();
    final repo = context.read<VaultRepository>();

    if (!enable) {
      await store.disable();
      if (!mounted) return;
      await settings.setBiometricUnlock(false);
      if (mounted) {
        _refresh();
        AppFeedback.show(
          context,
          'Clé retirée du trousseau',
          icon: Icons.lock_rounded,
        );
      }
      return;
    }

    final email = repo.profile?.email;
    if (email == null) return;

    final ok = await store.enable(
      email: email,
      sessionToken: repo.sessionTokenForBiometricStorage,
      vaultKeyBytes: repo.exportVaultKeyForBiometricStorage(),
    );
    if (!mounted) return;
    await settings.setBiometricUnlock(ok);
    if (!mounted) return;
    _refresh();
    if (ok) {
      AppFeedback.show(
        context,
        'Déverrouillage biométrique activé',
        icon: Icons.fingerprint_rounded,
      );
    } else {
      AppFeedback.failure(
        context,
        'Activation annulée ou biométrie indisponible',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    final settings = context.watch<AppSettings>();
    final clipboard = context.read<ClipboardGuard>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HairlineCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('Verrouillage par inactivité'),
                subtitle: Text(settings.autoLock.label),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _pickAutoLock(settings),
              ),
              Divider(height: 1, color: c.hairline),
              SwitchListTile(
                value: settings.lockOnBackground,
                onChanged: settings.setLockOnBackground,
                secondary: const Icon(Icons.exit_to_app_rounded),
                title: const Text('Verrouiller en quittant l’app'),
                subtitle: const Text(
                  'Le contenu reste visible dans le sélecteur de tâches sinon',
                ),
              ),
              Divider(height: 1, color: c.hairline),
              ListTile(
                leading: const Icon(Icons.content_paste_off_rounded),
                title: const Text('Effacer le presse-papiers'),
                subtitle: Text(clipboard.describeDelay),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _pickClipboard(settings),
              ),
            ],
          ),
        ),

        const SizedBox(height: Gap.lg),
        FutureBuilder<_BiometricState>(
          future: _biometricState,
          builder: (context, snapshot) {
            final state = snapshot.data;
            if (state == null) {
              return HairlineCard(
                child: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: Gap.md),
                    Text('Vérification de la biométrie…',
                        style: text.bodySmall),
                  ],
                ),
              );
            }

            if (!state.available) {
              return HairlineCard(
                sunken: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.fingerprint_rounded,
                        size: 18, color: c.textTertiary),
                    const SizedBox(width: Gap.md),
                    Expanded(
                      child: Text(
                        'Déverrouillage biométrique indisponible : '
                        '${state.description}.',
                        style: text.bodySmall?.copyWith(color: c.textTertiary),
                      ),
                    ),
                  ],
                ),
              );
            }

            return HairlineCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  SwitchListTile(
                    value: state.enrolled,
                    onChanged: _toggleBiometric,
                    secondary: Icon(Icons.fingerprint_rounded, color: c.accent),
                    title: const Text('Déverrouillage biométrique'),
                    subtitle: Text(state.description),
                  ),
                  if (state.enrolled) ...[
                    Divider(height: 1, color: c.hairline),
                    Padding(
                      padding: const EdgeInsets.all(Gap.lg),
                      child: Text(
                        'La clé du coffre est conservée dans le trousseau du '
                        'système, pas votre mot de passe maître. Un appareil '
                        'rooté peut toutefois la lire sans passer la '
                        'biométrie : c’est une limite de la brique de stockage '
                        'utilisée, pas un oubli.',
                        style: text.bodySmall
                            ?.copyWith(color: c.textTertiary, fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _pickAutoLock(AppSettings settings) async {
    final choice = await showModalBottomSheet<AutoLockDelay>(
      context: context,
      builder: (ctx) => _OptionSheet<AutoLockDelay>(
        title: 'Verrouillage par inactivité',
        note: 'Le coffre se referme après ce délai sans interaction. La clé est '
            'alors effacée de la mémoire.',
        options: AutoLockDelay.values,
        selected: settings.autoLock,
        labelOf: (v) => v.label,
      ),
    );
    if (choice != null) await settings.setAutoLock(choice);
  }

  Future<void> _pickClipboard(AppSettings settings) async {
    final choice = await showModalBottomSheet<ClipboardClearDelay>(
      context: context,
      builder: (ctx) => _OptionSheet<ClipboardClearDelay>(
        title: 'Effacement du presse-papiers',
        note: 'Sur Android, le presse-papiers est lisible par toute application '
            'installée, et son contenu y reste jusqu’au prochain remplacement.',
        options: ClipboardClearDelay.values,
        selected: settings.clipboardClear,
        labelOf: (v) => v.label,
      ),
    );
    if (choice != null) await settings.setClipboardClear(choice);
  }
}

class _BiometricState {
  final bool available;
  final bool enrolled;
  final String description;

  const _BiometricState({
    required this.available,
    required this.enrolled,
    required this.description,
  });
}

/// Feuille de choix générique, pour les réglages à valeurs multiples.
class _OptionSheet<T> extends StatelessWidget {
  const _OptionSheet({
    required this.title,
    required this.options,
    required this.selected,
    required this.labelOf,
    this.note,
  });

  final String title;
  final String? note;
  final List<T> options;
  final T selected;
  final String Function(T) labelOf;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    return SafeArea(
      // Défilable : la feuille est bornée par la hauteur de l'écran, et les six
      // délais de verrouillage la dépassaient de 118 pixels sur un écran de
      // 360 dp. Les derniers choix étaient donc affichés mais hors d'atteinte.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: text.titleLarge),
            if (note != null) ...[
              const SizedBox(height: Gap.sm),
              Text(
                note!,
                style: text.bodySmall?.copyWith(color: c.textTertiary),
              ),
            ],
            const SizedBox(height: Gap.xl),
            for (final option in options)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.sm),
                child: Material(
                  color: option == selected ? c.primaryWash : c.surface,
                  borderRadius: Radii.all(Radii.md),
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(option),
                    borderRadius: Radii.all(Radii.md),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Gap.lg,
                        vertical: Gap.md,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: Radii.all(Radii.md),
                        border: Border.all(
                          color: option == selected
                              ? c.primary.withValues(alpha: 0.5)
                              : c.hairline,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              labelOf(option),
                              style: text.bodyLarge?.copyWith(
                                color: option == selected
                                    ? c.primary
                                    : c.textPrimary,
                              ),
                            ),
                          ),
                          if (option == selected)
                            Icon(Icons.check_rounded, size: 18, color: c.primary),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}


/// Changement du mot de passe maître. La clé du coffre est réenveloppée, aucun
/// élément n'est rechiffré : l'opération est instantanée quel que soit le volume.
class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet();

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;
  PasswordStrength _strength = PasswordStrengthEvaluator.evaluate('');

  @override
  void initState() {
    super.initState();
    _next.addListener(() => setState(() {
          _strength = PasswordStrengthEvaluator.evaluate(_next.text);
        }));
  }

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _valid =>
      _current.text.isNotEmpty &&
      _next.text == _confirm.text &&
      _confirm.text.isNotEmpty &&
      _strength.level.index >= StrengthLevel.fair.index;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<VaultRepository>().changeMasterPassword(
            currentPassword: _current.text,
            newPassword: _next.text,
          );
      if (!mounted) return;
      // Le serveur a révoqué toutes les sessions : le jeton conservé derrière la
      // biométrie ne vaut plus rien, et la clé stockée ouvrirait un coffre dont
      // l'enveloppe a changé. On retire les deux.
      await context.read<BiometricUnlockStore>().disable();
      if (!mounted) return;
      await context.read<AppSettings>().setBiometricUnlock(false);
      if (!mounted) return;
      // Le dépôt s'est reverrouillé : la porte d'entrée reprendra la main
      // d'elle-même dès que cette feuille se referme.
      Navigator.of(context).pop();
    } on WrongMasterPasswordException {
      if (mounted) setState(() => _error = 'Mot de passe maître actuel incorrect');
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Gap.xl,
          0,
          Gap.xl,
          Gap.xl + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Changer le mot de passe maître', style: text.titleLarge),
              const SizedBox(height: Gap.sm),
              Text(
                'La clé du coffre est réenveloppée avec la nouvelle clé dérivée. '
                'Aucun élément n’est rechiffré, donc l’opération est immédiate. '
                'Toutes vos sessions, y compris celle-ci, seront révoquées.',
                style: text.bodySmall?.copyWith(color: c.textTertiary),
              ),
              const SizedBox(height: Gap.xl),
              TextField(
                controller: _current,
                enabled: !_busy,
                obscureText: true,
                style: SecretText.of(context),
                decoration: const InputDecoration(
                  labelText: 'Mot de passe maître actuel',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: Gap.md),
              TextField(
                controller: _next,
                enabled: !_busy,
                obscureText: true,
                style: SecretText.of(context),
                decoration: const InputDecoration(
                  labelText: 'Nouveau mot de passe maître',
                ),
              ),
              const SizedBox(height: Gap.md),
              StrengthMeter(strength: _strength, showWarnings: false),
              const SizedBox(height: Gap.md),
              TextField(
                controller: _confirm,
                enabled: !_busy,
                obscureText: true,
                style: SecretText.of(context),
                decoration: InputDecoration(
                  labelText: 'Confirmer',
                  errorText: _confirm.text.isEmpty || _confirm.text == _next.text
                      ? null
                      : 'Les deux saisies diffèrent',
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_error != null) ...[
                const SizedBox(height: Gap.lg),
                InlineError(message: _error!),
              ],
              const SizedBox(height: Gap.xl),
              FilledButton(
                onPressed: (_busy || !_valid) ? null : _submit,
                child: Text(_busy ? 'Réenveloppement…' : 'Changer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionsSheet extends StatefulWidget {
  const _SessionsSheet();

  @override
  State<_SessionsSheet> createState() => _SessionsSheetState();
}

class _SessionsSheetState extends State<_SessionsSheet> {
  late Future<List<VaultSession>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = context.read<VaultRepository>().listSessions();
  }

  Future<void> _revokeOthers(int others) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Déconnecter les autres appareils ?'),
        content: Text(
          '$others session${others > 1 ? 's' : ''} sera${others > 1 ? 'ont' : ''} '
          'révoquée${others > 1 ? 's' : ''}. Ces appareils devront redemander le '
          'mot de passe maître.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Déconnecter'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await context.read<VaultRepository>().revokeOtherSessions();
      if (!mounted) return;
      // On relit la liste : c'est la seule preuve que la révocation a pris.
      setState(() {
        _future = context.read<VaultRepository>().listSessions();
      });
      AppFeedback.show(
        context,
        'Autres appareils déconnectés',
        icon: Icons.check_rounded,
      );
    } on ApiFailure catch (e) {
      if (mounted) AppFeedback.failure(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Appareils connectés', style: text.titleLarge),
              const SizedBox(height: Gap.sm),
              Text(
                'Le serveur ne conserve que l’empreinte du jeton de session, '
                'jamais le jeton lui-même.',
                style: text.bodySmall?.copyWith(color: c.textTertiary),
              ),
              const SizedBox(height: Gap.xl),

              Flexible(
                child: FutureBuilder<List<VaultSession>>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.all(Gap.xxl),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      return InlineError(
                        message: snapshot.error is ApiFailure
                            ? (snapshot.error as ApiFailure).message
                            : 'Impossible de lire les sessions',
                        onRetry: () => setState(() {
                          _future =
                              context.read<VaultRepository>().listSessions();
                        }),
                      );
                    }

                    final sessions = snapshot.data ?? const <VaultSession>[];
                    if (sessions.isEmpty) {
                      return Text(
                        'Aucune session listée.',
                        style: text.bodyMedium,
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: sessions.length,
                      separatorBuilder: (_, _) => const SizedBox(height: Gap.sm),
                      itemBuilder: (context, i) =>
                          _SessionRow(session: sessions[i]),
                    );
                  },
                ),
              ),

              const SizedBox(height: Gap.xl),
              FutureBuilder<List<VaultSession>>(
                future: _future,
                builder: (context, snapshot) {
                  final total = snapshot.data?.length ?? 0;
                  // La session courante est dans la liste : on ne compte que
                  // les autres.
                  final others = total > 1 ? total - 1 : 0;
                  return OutlinedButton.icon(
                    onPressed: (_busy || others == 0)
                        ? null
                        : () => _revokeOthers(others),
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: Text(
                      others == 0
                          ? 'Aucun autre appareil connecté'
                          : 'Déconnecter les $others autre'
                              '${others > 1 ? 's' : ''} appareil'
                              '${others > 1 ? 's' : ''}',
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session});

  final VaultSession session;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    return HairlineCard(
      padding: const EdgeInsets.all(Gap.md),
      child: Row(
        children: [
          Icon(Icons.devices_rounded, size: 19, color: c.textSecondary),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session.deviceName ?? 'Appareil sans nom',
                  style: text.bodyLarge,
                ),
                const SizedBox(height: Gap.xxs),
                Text(
                  [
                    if (session.lastUsedAt != null)
                      'vu ${_relative(session.lastUsedAt!)}',
                    if (session.expiresAt != null)
                      'expire le ${_shortDate(session.expiresAt!)}',
                  ].join(' · '),
                  style: text.bodySmall
                      ?.copyWith(color: c.textTertiary, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _relative(DateTime value) {
  final ago = DateTime.now().difference(value.toLocal());
  return switch (ago) {
    Duration(inMinutes: < 1) => 'à l’instant',
    Duration(inMinutes: final m) when m < 60 => 'il y a $m min',
    Duration(inHours: final h) when h < 24 => 'il y a $h h',
    _ => 'il y a ${ago.inDays} j',
  };
}

String _shortDate(DateTime value) {
  final local = value.toLocal();
  final d = local.day.toString().padLeft(2, '0');
  final m = local.month.toString().padLeft(2, '0');
  return '$d/$m/${local.year}';
}

/// Suppression définitive du coffre. Demande le mot de passe maître : le serveur
/// vérifie l'empreinte avant d'effacer, donc un jeton volé ne suffit pas.
class _DeleteVaultSheet extends StatefulWidget {
  const _DeleteVaultSheet();

  @override
  State<_DeleteVaultSheet> createState() => _DeleteVaultSheetState();
}

class _DeleteVaultSheetState extends State<_DeleteVaultSheet> {
  final _password = TextEditingController();
  final _confirmWord = TextEditingController();
  bool _busy = false;
  String? _error;

  static const _requiredWord = 'SUPPRIMER';

  @override
  void dispose() {
    _password.dispose();
    _confirmWord.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<VaultRepository>().deleteVault(_password.text);
      if (!mounted) return;
      await context.read<BiometricUnlockStore>().disable();
      if (!mounted) return;
      await context.read<AppSettings>().setBiometricUnlock(false);
      if (mounted) Navigator.of(context).pop();
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    final repo = context.read<VaultRepository>();
    final canSubmit = !_busy &&
        _password.text.isNotEmpty &&
        _confirmWord.text.trim().toUpperCase() == _requiredWord;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Gap.xl,
          0,
          Gap.xl,
          Gap.xl + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: c.danger),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text('Supprimer le coffre', style: text.titleLarge),
                  ),
                ],
              ),
              const SizedBox(height: Gap.md),
              Text(
                'Les ${repo.items.length + repo.trash.length} éléments, les '
                'dossiers et le compte seront effacés du serveur. Il n’existe '
                'aucune sauvegarde côté serveur : personne ne pourra les '
                'restaurer, pas même vous.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: Gap.xl),
              TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                style: SecretText.of(context),
                decoration: const InputDecoration(
                  labelText: 'Mot de passe maître',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: Gap.md),
              TextField(
                controller: _confirmWord,
                enabled: !_busy,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Tapez SUPPRIMER pour confirmer',
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_error != null) ...[
                const SizedBox(height: Gap.lg),
                InlineError(message: _error!),
              ],
              const SizedBox(height: Gap.xl),
              FilledButton(
                onPressed: canSubmit ? _submit : null,
                style: FilledButton.styleFrom(backgroundColor: c.danger),
                child: Text(_busy ? 'Suppression…' : 'Supprimer définitivement'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
