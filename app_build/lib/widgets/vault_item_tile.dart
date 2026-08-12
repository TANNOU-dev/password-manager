import 'package:flutter/material.dart';

import '../core/design/app_theme.dart';
import '../core/design/monogram.dart';
import '../core/design/tokens.dart';
import '../data/models/cipher.dart';

/// Ligne du coffre.
///
/// Trois zones : la pastille d'identité, le bloc texte sur deux lignes, et les
/// actions rapides. L'ancienne liste imposait de déplier un groupe puis
/// d'ouvrir un menu à trois points pour copier un mot de passe ; ici la copie
/// est à un seul appui, ce qui est le geste le plus fréquent de loin.
class VaultItemTile extends StatelessWidget {
  const VaultItemTile({
    super.key,
    required this.item,
    this.onTap,
    this.onCopyPassword,
    this.onCopyUsername,
    this.onToggleFavorite,
    this.warning,
  });

  final CipherItem item;
  final VoidCallback? onTap;
  final VoidCallback? onCopyPassword;
  final VoidCallback? onCopyUsername;
  final VoidCallback? onToggleFavorite;

  /// Alerte du rapport de sécurité, affichée en pastille sur la ligne.
  final String? warning;

  /// Les types sans marque reçoivent une icône plutôt que des initiales : deux
  /// lettres tirées de « Carte Visa perso » n'apprennent rien.
  IconData? get _typeIcon => switch (item.type) {
        CipherType.login => null,
        CipherType.card => Icons.credit_card_rounded,
        CipherType.identity => Icons.badge_outlined,
        CipherType.secureNote => Icons.sticky_note_2_outlined,
        CipherType.sshKey => Icons.terminal_rounded,
      };

  /// Source de la pastille : le domaine si on en a un, sinon le nom. Le domaine
  /// est plus stable — renommer l'entrée ne change pas la couleur.
  String get _monogramSource {
    final data = item.data;
    if (data is LoginData) {
      return data.primaryHost ?? data.name;
    }
    return data.name;
  }

  String? _subtitle() {
    final data = item.data;
    return switch (data) {
      LoginData() => data.username.isNotEmpty
          ? data.username
          : (data.primaryHost ?? 'Aucun identifiant'),
      CardData() =>
        [data.inferredBrand, if (data.last4.isNotEmpty) '•••• ${data.last4}']
            .where((s) => s.isNotEmpty)
            .join(' · '),
      IdentityData() => data.fullName.isNotEmpty ? data.fullName : data.email,
      SecureNoteData() => 'Note sécurisée',
      // L'empreinte plutôt que le commentaire : c'est elle qu'on compare à ce
      // qu'affiche un serveur, et elle identifie la clé sans ambiguïté.
      SshKeyData() => data.keyFingerprint.isNotEmpty
          ? data.keyFingerprint
          : 'Clé SSH',
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    final data = item.data;
    final subtitle = _subtitle();
    final hasTotp = data is LoginData && data.hasTotp;

    return Material(
      color: c.surface,
      borderRadius: Radii.all(Radii.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.all(Radii.lg),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: Radii.all(Radii.lg),
            border: Border.all(color: c.hairline),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.md,
            vertical: Gap.md,
          ),
          child: Row(
            children: [
              MonogramTile(source: _monogramSource, icon: _typeIcon),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            data.name.isEmpty ? 'Sans nom' : data.name,
                            style: text.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (item.favorite) ...[
                          const SizedBox(width: Gap.sm),
                          Icon(Icons.star_rounded, size: 15, color: c.warning),
                        ],
                        if (hasTotp) ...[
                          const SizedBox(width: Gap.sm),
                          Icon(Icons.timer_outlined, size: 14, color: c.accent),
                        ],
                      ],
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: Gap.xxs),
                      Text(
                        subtitle,
                        style: text.bodySmall?.copyWith(color: c.textTertiary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (warning != null) ...[
                      const SizedBox(height: Gap.sm),
                      _WarningBadge(label: warning!),
                    ],
                  ],
                ),
              ),
              if (onCopyPassword != null && data is LoginData)
                IconButton(
                  tooltip: 'Copier le mot de passe',
                  onPressed: onCopyPassword,
                  icon: const Icon(Icons.content_copy_outlined, size: 19),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WarningBadge extends StatelessWidget {
  const _WarningBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: 3),
      decoration: BoxDecoration(
        color: c.dangerWash,
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 12, color: c.danger),
          const SizedBox(width: Gap.xs),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: c.danger, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
