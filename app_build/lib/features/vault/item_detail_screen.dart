import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/app_theme.dart';
import '../../core/design/monogram.dart';
import '../../core/design/tokens.dart';
import '../../core/utils/password_strength.dart';
import '../../core/utils/totp.dart';
import '../../data/api/api_client.dart';
import '../../data/models/cipher.dart';
import '../../data/vault_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/secret_field.dart';
import '../../widgets/strength_meter.dart';
import 'item_edit_screen.dart';

/// Détail d'un élément.
///
/// On s'adresse au dépôt par identifiant plutôt que de recevoir une copie de
/// l'élément : après une modification, l'écran doit refléter l'état à jour sans
/// qu'on ait à le repousser à la main.
class ItemDetailScreen extends StatelessWidget {
  const ItemDetailScreen({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<VaultRepository>();
    final matches = [...repo.items, ...repo.trash].where((i) => i.id == itemId);

    if (matches.isEmpty) {
      // Peut arriver si l'élément a été supprimé définitivement depuis un autre
      // appareil pendant qu'on le regardait.
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.search_off_rounded,
          title: 'Élément introuvable',
          message: 'Il a peut-être été supprimé depuis un autre appareil.',
        ),
      );
    }

    return _DetailBody(item: matches.first);
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.item});

  final CipherItem item;

  Future<void> _guard(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } on ApiFailure catch (e) {
      if (context.mounted) AppFeedback.failure(context, e.message);
    }
  }

  Future<void> _trash(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mettre à la corbeille ?'),
        content: const Text(
          'L’élément restera récupérable depuis la corbeille.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mettre à la corbeille'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await _guard(context, () => context.read<VaultRepository>().moveToTrash(item));
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    final repo = context.watch<VaultRepository>();
    final data = item.data;

    final folderName = item.folderId == null
        ? null
        : repo.folders
            .where((f) => f.id == item.folderId)
            .map((f) => f.name)
            .firstOrNull;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: item.favorite ? 'Retirer des favoris' : 'Ajouter aux favoris',
            onPressed: () => _guard(
              context,
              () => context.read<VaultRepository>().toggleFavorite(item),
            ),
            icon: Icon(
              item.favorite ? Icons.star_rounded : Icons.star_outline_rounded,
              color: item.favorite ? c.warning : null,
            ),
          ),
          if (!item.isDeleted)
            IconButton(
              tooltip: 'Modifier',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ItemEditScreen(existing: item),
                ),
              ),
              icon: const Icon(Icons.edit_outlined),
            ),
          if (!item.isDeleted)
            IconButton(
              tooltip: 'Mettre à la corbeille',
              onPressed: () => _trash(context),
              icon: Icon(Icons.delete_outline_rounded, color: c.danger),
            ),
          const SizedBox(width: Gap.sm),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.giant),
        children: [
          _Header(item: item, folderName: folderName),
          const SizedBox(height: Gap.xxl),

          if (item.isDeleted) ...[
            _TrashBanner(item: item),
            const SizedBox(height: Gap.xl),
          ],

          ...switch (data) {
            LoginData() => _loginSections(context, data),
            CardData() => _cardSections(context, data),
            IdentityData() => _identitySections(context, data),
            SecureNoteData() => _noteSections(context, data),
            SshKeyData() => _sshKeySections(context, data),
          },

          if (data.fields.isNotEmpty) ...[
            const SizedBox(height: Gap.xxl),
            const SectionLabel('Champs personnalisés'),
            for (final field in data.fields)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.md),
                child: field.type == CustomFieldType.hidden
                    ? SecretField(label: field.name, value: field.value)
                    : HairlineCard(
                        sunken: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: Gap.lg,
                          vertical: Gap.sm,
                        ),
                        child: InfoRow(
                          label: field.name,
                          value: field.type == CustomFieldType.boolean
                              ? (field.value == 'true' ? 'Oui' : 'Non')
                              : field.value,
                          copyable: field.type != CustomFieldType.boolean,
                        ),
                      ),
              ),
          ],

          if (data.notes.isNotEmpty && data is! SecureNoteData) ...[
            const SizedBox(height: Gap.xxl),
            const SectionLabel('Notes'),
            HairlineCard(
              sunken: true,
              child: SelectableText(data.notes, style: text.bodyLarge),
            ),
          ],

          const SizedBox(height: Gap.xxl),
          _Timestamps(item: item),
        ],
      ),
    );
  }

  // ── Identifiant ──
  List<Widget> _loginSections(BuildContext context, LoginData data) {
    final strength = data.password.isEmpty
        ? null
        : PasswordStrengthEvaluator.evaluate(data.password);

    return [
      if (data.username.isNotEmpty)
        HairlineCard(
          sunken: true,
          padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.sm),
          child: InfoRow(
            label: 'Identifiant',
            value: data.username,
            copyable: true,
            copyLabel: 'Identifiant',
          ),
        ),
      if (data.username.isNotEmpty) const SizedBox(height: Gap.md),

      SecretField(
        label: 'Mot de passe',
        value: data.password,
        onCopied: () {},
      ),

      if (strength != null) ...[
        const SizedBox(height: Gap.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.xs),
          child: StrengthMeter(strength: strength, showWarnings: true),
        ),
      ],

      if (data.hasTotp) ...[
        const SizedBox(height: Gap.md),
        _TotpCard(secret: data.totp),
      ],

      if (data.uris.isNotEmpty) ...[
        const SizedBox(height: Gap.xxl),
        const SectionLabel('Adresses'),
        for (final uri in data.uris)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.sm),
            child: HairlineCard(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.lg,
                vertical: Gap.md,
              ),
              child: Row(
                children: [
                  Icon(Icons.link_rounded,
                      size: 18, color: context.palette.textTertiary),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          uri.uri,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: context.palette.textPrimary,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: Gap.xxs),
                        Text(
                          'Correspondance : ${uri.match.label}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: context.palette.textTertiary,
                                fontSize: 11,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Copier l’adresse',
                    onPressed: () =>
                        AppFeedback.copyValue(context, uri.uri, 'Adresse'),
                    icon: const Icon(Icons.content_copy_outlined, size: 18),
                  ),
                ],
              ),
            ),
          ),
      ],

      if (data.passwordHistory.isNotEmpty) ...[
        const SizedBox(height: Gap.xxl),
        _PasswordHistory(history: data.passwordHistory),
      ],
    ];
  }

  // ── Carte bancaire ──
  List<Widget> _cardSections(BuildContext context, CardData data) {
    return [
      _CardVisual(data: data),
      const SizedBox(height: Gap.xl),
      SecretField(label: 'Numéro', value: data.number),
      const SizedBox(height: Gap.md),
      Row(
        children: [
          Expanded(
            child: HairlineCard(
              sunken: true,
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.lg,
                vertical: Gap.sm,
              ),
              child: InfoRow(
                label: 'Échéance',
                value: data.expiry,
                monospace: true,
              ),
            ),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: SecretField(label: 'Cryptogramme', value: data.code),
          ),
        ],
      ),
      if (data.cardholderName.isNotEmpty) ...[
        const SizedBox(height: Gap.md),
        HairlineCard(
          sunken: true,
          padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.sm),
          child: InfoRow(
            label: 'Titulaire',
            value: data.cardholderName,
            copyable: true,
          ),
        ),
      ],
    ];
  }

  // ── Identité ──
  List<Widget> _identitySections(BuildContext context, IdentityData data) {
    final rows = <(String, String, bool)>[
      ('Nom complet', data.fullName, false),
      ('Société', data.company, false),
      ('E-mail', data.email, false),
      ('Téléphone', data.phone, false),
      ('Identifiant', data.username, false),
      ('Adresse', data.address1, false),
      ('Complément', data.address2, false),
      ('Ville', data.city, false),
      ('Région', data.state, false),
      ('Code postal', data.postalCode, false),
      ('Pays', data.country, false),
    ].where((r) => r.$2.isNotEmpty).toList();

    // Numéros d'identité : masqués comme des mots de passe. Ce sont les données
    // les plus sensibles d'une fiche identité.
    final secrets = <(String, String)>[
      ('Numéro de sécurité sociale', data.ssn),
      ('Passeport', data.passportNumber),
      ('Permis de conduire', data.licenseNumber),
    ].where((r) => r.$2.isNotEmpty).toList();

    return [
      if (rows.isNotEmpty)
        HairlineCard(
          sunken: true,
          padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.sm),
          child: Column(
            children: [
              for (final (label, value, mono) in rows)
                InfoRow(
                  label: label,
                  value: value,
                  monospace: mono,
                  copyable: true,
                ),
            ],
          ),
        ),
      if (secrets.isNotEmpty) ...[
        const SizedBox(height: Gap.xxl),
        const SectionLabel('Pièces d’identité'),
        for (final (label, value) in secrets)
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: SecretField(label: label, value: value),
          ),
      ],
    ];
  }

  // ── Note ──
  // ── Clé SSH ──
  //
  // Ordre voulu : privée, publique, empreinte. La clé privée est masquée comme
  // un mot de passe ; les deux autres sont publiques par nature et se lisent
  // directement — les cacher ne protégerait rien et gênerait la comparaison
  // d'empreinte, qui est justement l'usage courant.
  List<Widget> _sshKeySections(BuildContext context, SshKeyData data) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    return [
      const SectionLabel('Clé privée'),
      SecretField(
        label: 'Clé privée',
        value: data.privateKey,
        onCopied: () {},
      ),
      const SizedBox(height: Gap.sm),
      Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: c.warning),
          const SizedBox(width: Gap.xs),
          Expanded(
            child: Text(
              'Ne se colle jamais ailleurs que dans un fichier de clé.',
              style: text.bodySmall?.copyWith(color: c.textTertiary),
            ),
          ),
        ],
      ),

      const SizedBox(height: Gap.xxl),
      const SectionLabel('Clé publique'),
      HairlineCard(
        sunken: true,
        child: data.publicKey.isEmpty
            ? Text('Aucune clé publique',
                style: text.bodyMedium?.copyWith(color: c.textTertiary))
            : SelectableText(
                data.publicKey,
                style: text.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  height: 1.5,
                ),
              ),
      ),
      const SizedBox(height: Gap.md),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: data.publicKey.isEmpty
              ? null
              : () => AppFeedback.copyValue(
                    context,
                    data.publicKey,
                    'Clé publique',
                  ),
          icon: const Icon(Icons.content_copy_outlined, size: 18),
          label: const Text('Copier la clé publique'),
        ),
      ),

      if (data.keyFingerprint.isNotEmpty) ...[
        const SizedBox(height: Gap.xxl),
        const SectionLabel('Empreinte'),
        HairlineCard(
          sunken: true,
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.lg,
            vertical: Gap.sm,
          ),
          child: InfoRow(
            label: 'SHA256',
            value: data.keyFingerprint,
            copyable: true,
            copyLabel: 'Empreinte',
            monospace: true,
          ),
        ),
        const SizedBox(height: Gap.sm),
        Text(
          'À comparer avec ce qu’affiche le serveur à la première connexion.',
          style: text.bodySmall?.copyWith(color: c.textTertiary),
        ),
      ],
    ];
  }

  List<Widget> _noteSections(BuildContext context, SecureNoteData data) {
    return [
      HairlineCard(
        sunken: true,
        child: data.notes.isEmpty
            ? Text(
                'Note vide',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: context.palette.textTertiary),
              )
            : SelectableText(
                data.notes,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
      ),
      const SizedBox(height: Gap.md),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: data.notes.isEmpty
              ? null
              : () => AppFeedback.copyValue(context, data.notes, 'Note'),
          icon: const Icon(Icons.content_copy_outlined, size: 18),
          label: const Text('Copier la note'),
        ),
      ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.item, this.folderName});

  final CipherItem item;
  final String? folderName;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    final data = item.data;

    final monogramSource =
        data is LoginData ? (data.primaryHost ?? data.name) : data.name;
    final icon = switch (item.type) {
      CipherType.login => null,
      CipherType.card => Icons.credit_card_rounded,
      CipherType.identity => Icons.badge_outlined,
      CipherType.secureNote => Icons.sticky_note_2_outlined,
      CipherType.sshKey => Icons.terminal_rounded,
    };

    return Row(
      children: [
        MonogramTile(source: monogramSource, size: 58, icon: icon),
        const SizedBox(width: Gap.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data.name.isEmpty ? 'Sans nom' : data.name,
                style: text.headlineSmall,
              ),
              const SizedBox(height: Gap.xs),
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.xs,
                children: [
                  _Tag(label: item.type.label, icon: Icons.category_outlined),
                  if (folderName != null)
                    _Tag(label: folderName!, icon: Icons.folder_outlined),
                  if (item.favorite)
                    _Tag(
                      label: 'Favori',
                      icon: Icons.star_rounded,
                      tint: c.warning,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.icon, this.tint});

  final String label;
  final IconData icon;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final color = tint ?? c.textTertiary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 3),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.xs),
        border: Border.all(color: c.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: Gap.xs),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: color, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Carte bancaire stylisée. Le numéro reste masqué : seuls les quatre derniers
/// chiffres apparaissent, ce qui suffit à identifier la carte.
class _CardVisual extends StatelessWidget {
  const _CardVisual({required this.data});

  final CardData data;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final mono = Monogram.of(data.inferredBrand.isEmpty
        ? data.name
        : data.inferredBrand);

    return Container(
      padding: const EdgeInsets.all(Gap.xl),
      decoration: BoxDecoration(
        borderRadius: Radii.all(Radii.lg),
        gradient: LinearGradient(
          colors: mono.gradient(
            dark: Theme.of(context).brightness == Brightness.dark,
          ),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        // Halo léger pour détacher la carte du fond.
        boxShadow: [
          BoxShadow(
            color: c.primary.withValues(alpha: 0.22),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.credit_card_rounded,
                  size: 22, color: Colors.white.withValues(alpha: 0.9)),
              const Spacer(),
              Text(
                data.inferredBrand,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                    ),
              ),
            ],
          ),
          const SizedBox(height: Gap.xxl),
          Text(
            '•••• •••• •••• ${data.last4}',
            style: SecretText.of(context, size: 19).copyWith(
              color: Colors.white,
              letterSpacing: 2,
            ),
          ),
          // Le titulaire n'est pas répété ici : il a sa propre ligne copiable
          // plus bas. L'afficher deux fois n'aide personne sur un écran étroit.
          if (data.expiry.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                data.expiry,
                style: SecretText.of(context, size: 13)
                    .copyWith(color: Colors.white.withValues(alpha: 0.86)),
              ),
            ),
        ],
      ),
    );
  }
}

/// Code TOTP vivant. Recalculé chaque seconde depuis l'horloge locale : aucun
/// appel réseau, le secret ne bouge pas de l'appareil.
class _TotpCard extends StatefulWidget {
  const _TotpCard({required this.secret});

  final String secret;

  @override
  State<_TotpCard> createState() => _TotpCardState();
}

class _TotpCardState extends State<_TotpCard> {
  Timer? _timer;
  TotpCode? _code;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _tick() {
    try {
      final config = Totp.parse(widget.secret);
      final code = Totp.generate(config);
      if (mounted) {
        setState(() {
          _code = code;
          _error = null;
        });
      }
    } on TotpFormatException catch (e) {
      _timer?.cancel();
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    if (_error != null) {
      return InlineError(message: 'Secret TOTP invalide : $_error');
    }

    final code = _code;
    if (code == null) return const SizedBox.shrink();

    // Rouge sur les cinq dernières secondes : signale qu'il vaut mieux attendre
    // le prochain code plutôt que de coller celui-ci in extremis.
    final expiring = code.remaining.inSeconds <= 5;
    final label = Totp.describe(widget.secret);

    return HairlineCard(
      sunken: true,
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.sm, Gap.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label == null
                      ? 'CODE À USAGE UNIQUE'
                      : 'CODE À USAGE UNIQUE · ${label.toUpperCase()}',
                  style: text.labelSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: Gap.xs),
                Text(
                  code.grouped,
                  style: SecretText.of(context, size: 22).copyWith(
                    letterSpacing: 2,
                    color: expiring ? c.danger : c.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          TotpRing(
            progress: code.progress,
            color: expiring ? c.danger : c.accent,
            size: 26,
          ),
          const SizedBox(width: Gap.sm),
          IconButton(
            tooltip: 'Copier le code',
            onPressed: () =>
                AppFeedback.copyValue(context, code.code, 'Code'),
            icon: const Icon(Icons.content_copy_outlined, size: 20),
          ),
        ],
      ),
    );
  }
}

class _PasswordHistory extends StatelessWidget {
  const _PasswordHistory({required this.history});

  final List<PasswordHistoryEntry> history;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel('Anciens mots de passe (${history.length})'),
        Text(
          'Conservés pour retrouver un accès resté sur un ancien mot de passe. '
          'Ils sont chiffrés comme le reste.',
          style: text.bodySmall?.copyWith(color: c.textTertiary),
        ),
        const SizedBox(height: Gap.md),
        for (final entry in history.take(5))
          Padding(
            padding: const EdgeInsets.only(bottom: Gap.md),
            child: SecretField(
              label: 'Remplacé le ${_formatDate(entry.replacedAt)}',
              value: entry.password,
            ),
          ),
      ],
    );
  }
}

class _TrashBanner extends StatelessWidget {
  const _TrashBanner({required this.item});

  final CipherItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        color: c.dangerWash,
        borderRadius: Radii.all(Radii.lg),
        border: Border.all(color: c.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.delete_outline_rounded, size: 20, color: c.danger),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Text(
              'À la corbeille depuis le ${_formatDate(item.deletedAt!)}. '
              'Restaurez-le pour le modifier.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: c.danger),
            ),
          ),
        ],
      ),
    );
  }
}

class _Timestamps extends StatelessWidget {
  const _Timestamps({required this.item});

  final CipherItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    final lines = <String>[
      if (item.createdAt != null) 'Créé le ${_formatDate(item.createdAt!)}',
      if (item.revisionDate != null)
        'Modifié le ${_formatDate(item.revisionDate!)}',
    ];
    if (lines.isEmpty) return const SizedBox.shrink();

    return Text(
      lines.join(' · '),
      style: text.bodySmall?.copyWith(color: c.textTertiary, fontSize: 11),
      textAlign: TextAlign.center,
    );
  }
}

String _formatDate(DateTime value) {
  final local = value.toLocal();
  final d = local.day.toString().padLeft(2, '0');
  final m = local.month.toString().padLeft(2, '0');
  return '$d/$m/${local.year}';
}
