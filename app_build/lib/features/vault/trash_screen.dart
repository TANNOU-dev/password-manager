import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/app_theme.dart';
import '../../core/design/tokens.dart';
import '../../data/api/api_client.dart';
import '../../data/models/cipher.dart';
import '../../data/vault_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/vault_item_tile.dart';
import 'item_detail_screen.dart';

/// Corbeille.
///
/// La suppression est douce par défaut : `DELETE /api/ciphers/:id` marque
/// `deleted_at` sans effacer la ligne. La suppression définitive est une action
/// distincte, et elle demande confirmation.
class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  bool _busy = false;

  Future<void> _guard(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on ApiFailure catch (e) {
      if (mounted) AppFeedback.failure(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _purgeOne(CipherItem item) async {
    final confirmed = await _confirm(
      title: 'Supprimer définitivement ?',
      body: '« ${item.data.name} » sera effacé du serveur. '
          'Cette action est irréversible.',
      action: 'Supprimer définitivement',
    );
    if (confirmed != true) return;
    await _guard(() => context.read<VaultRepository>().deleteForever(item));
  }

  Future<void> _emptyAll(int count) async {
    final confirmed = await _confirm(
      title: 'Vider la corbeille ?',
      body: 'Les $count élément${count > 1 ? 's' : ''} seront effacés du '
          'serveur. Cette action est irréversible.',
      action: 'Vider',
    );
    if (confirmed != true) return;
    await _guard(() async {
      final purged = await context.read<VaultRepository>().emptyTrash();
      if (mounted) {
        AppFeedback.show(
          context,
          '$purged élément${purged > 1 ? 's' : ''} supprimé${purged > 1 ? 's' : ''}',
          icon: Icons.delete_outline_rounded,
          tint: context.palette.danger,
        );
      }
    });
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String action,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: context.palette.danger,
            ),
            child: Text(action),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    final repo = context.watch<VaultRepository>();
    final trash = [...repo.trash]..sort((a, b) {
        final da = a.deletedAt;
        final db = b.deletedAt;
        if (da == null || db == null) return 0;
        return db.compareTo(da); // le plus récemment supprimé d'abord
      });

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Text('Corbeille'),
        actions: [
          if (trash.isNotEmpty)
            TextButton(
              onPressed: _busy ? null : () => _emptyAll(trash.length),
              child: Text('Vider', style: TextStyle(color: c.danger)),
            ),
          const SizedBox(width: Gap.sm),
        ],
      ),
      body: trash.isEmpty
          ? const EmptyState(
              icon: Icons.delete_outline_rounded,
              title: 'Corbeille vide',
              message: 'Les éléments supprimés atterrissent ici et restent '
                  'récupérables jusqu’à ce que vous les effaciez.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.lg, Gap.xl, Gap.giant),
              itemCount: trash.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: Gap.sm),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: Gap.sm),
                    child: Text(
                      '${trash.length} élément${trash.length > 1 ? 's' : ''} '
                      'récupérable${trash.length > 1 ? 's' : ''}. Ils restent '
                      'chiffrés sur le serveur.',
                      style: text.bodySmall?.copyWith(color: c.textTertiary),
                    ),
                  );
                }
                final item = trash[i - 1];
                return Dismissible(
                  key: ValueKey(item.id),
                  direction: DismissDirection.startToEnd,
                  // Restauration par balayage : le geste le plus probable dans
                  // cet écran. La suppression définitive reste dans le menu,
                  // pour ne pas être déclenchée d'un revers de doigt.
                  background: Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: Gap.xl),
                    decoration: BoxDecoration(
                      color: c.success.withValues(alpha: 0.18),
                      borderRadius: Radii.all(Radii.lg),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.restore_rounded, color: c.success, size: 20),
                        const SizedBox(width: Gap.sm),
                        Text('Restaurer',
                            style: text.labelMedium?.copyWith(color: c.success)),
                      ],
                    ),
                  ),
                  confirmDismiss: (_) async {
                    await _guard(() =>
                        context.read<VaultRepository>().restoreFromTrash(item));
                    // On laisse le dépôt piloter la liste : l'élément disparaît
                    // de la corbeille parce qu'il n'y est plus, pas parce que le
                    // widget a été retiré.
                    return false;
                  },
                  child: Row(
                    children: [
                      Expanded(
                        child: Opacity(
                          opacity: 0.72,
                          child: VaultItemTile(
                            item: item,
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    ItemDetailScreen(itemId: item.id!),
                              ),
                            ),
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Actions',
                        enabled: !_busy,
                        onSelected: (v) {
                          if (v == 'restore') {
                            _guard(() => context
                                .read<VaultRepository>()
                                .restoreFromTrash(item));
                          }
                          if (v == 'purge') _purgeOne(item);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'restore',
                            child: ListTile(
                              leading: Icon(Icons.restore_rounded),
                              title: Text('Restaurer'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          PopupMenuItem(
                            value: 'purge',
                            child: ListTile(
                              leading: Icon(Icons.delete_forever_rounded,
                                  color: c.danger),
                              title: Text('Supprimer définitivement',
                                  style: TextStyle(color: c.danger)),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
