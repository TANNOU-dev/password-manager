import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/app_theme.dart';
import '../../core/design/tokens.dart';
import '../../data/api/api_client.dart';
import '../../data/models/cipher.dart';
import '../../data/vault_repository.dart';
import '../../widgets/common.dart';

/// Résultat du choix : `folderId` nul signifie « tout le coffre ».
class FolderSelection {
  final String? folderId;
  const FolderSelection(this.folderId);
}

/// Feuille de gestion des dossiers : choisir, créer, renommer, supprimer.
///
/// Le nom d'un dossier est chiffré comme le reste du coffre. Le serveur voit
/// quels éléments partagent un dossier, mais pas comment il s'appelle.
class FolderSheet extends StatefulWidget {
  const FolderSheet({super.key, this.selectedId, this.pickOnly = false});

  final String? selectedId;

  /// En mode `pickOnly`, on choisit un dossier pour un élément : pas d'entrée
  /// « tout le coffre ».
  final bool pickOnly;

  @override
  State<FolderSheet> createState() => _FolderSheetState();
}

class _FolderSheetState extends State<FolderSheet> {
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

  Future<void> _create() async {
    final name = await _promptName(context, title: 'Nouveau dossier');
    if (name == null || !mounted) return;
    await _guard(() => context.read<VaultRepository>().createFolder(name));
  }

  Future<void> _rename(FolderItem folder) async {
    final name = await _promptName(
      context,
      title: 'Renommer le dossier',
      initial: folder.name,
    );
    if (name == null || !mounted) return;
    await _guard(
      () => context.read<VaultRepository>().renameFolder(folder.id, name),
    );
  }

  Future<void> _delete(FolderItem folder, int itemCount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Supprimer « ${folder.name} » ?'),
        content: Text(
          itemCount == 0
              ? 'Le dossier est vide.'
              : 'Les $itemCount élément${itemCount > 1 ? 's' : ''} qu’il '
                  'contient ne seront pas supprimés : ils reviendront simplement '
                  'sans dossier.',
        ),
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
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _guard(() => context.read<VaultRepository>().deleteFolder(folder.id));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    final repo = context.watch<VaultRepository>();
    final folders = [...repo.folders]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    int countIn(String? id) =>
        repo.items.where((i) => i.folderId == id).length;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Dossiers', style: text.titleLarge)),
                if (_busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            Text(
              'Les noms de dossiers sont chiffrés comme le reste du coffre.',
              style: text.bodySmall?.copyWith(color: c.textTertiary),
            ),
            const SizedBox(height: Gap.xl),

            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    if (!widget.pickOnly)
                      _FolderRow(
                        name: 'Tout le coffre',
                        icon: Icons.inbox_rounded,
                        count: repo.items.length,
                        selected: widget.selectedId == null,
                        onTap: () =>
                            Navigator.of(context).pop(const FolderSelection(null)),
                      ),
                    if (widget.pickOnly)
                      _FolderRow(
                        name: 'Sans dossier',
                        icon: Icons.remove_circle_outline_rounded,
                        count: countIn(null),
                        selected: widget.selectedId == null,
                        onTap: () =>
                            Navigator.of(context).pop(const FolderSelection(null)),
                      ),
                    for (final folder in folders)
                      _FolderRow(
                        name: folder.name,
                        icon: Icons.folder_rounded,
                        count: countIn(folder.id),
                        selected: widget.selectedId == folder.id,
                        onTap: () => Navigator.of(context)
                            .pop(FolderSelection(folder.id)),
                        onRename: _busy ? null : () => _rename(folder),
                        onDelete: _busy
                            ? null
                            : () => _delete(folder, countIn(folder.id)),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: Gap.lg),
            OutlinedButton.icon(
              onPressed: _busy ? null : _create,
              icon: const Icon(Icons.create_new_folder_outlined, size: 18),
              label: const Text('Nouveau dossier'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.name,
    required this.icon,
    required this.count,
    required this.selected,
    required this.onTap,
    this.onRename,
    this.onDelete,
  });

  final String name;
  final IconData icon;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.sm),
      child: Material(
        color: selected ? c.primaryWash : c.surface,
        borderRadius: Radii.all(Radii.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.all(Radii.md),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Gap.md,
              vertical: Gap.md,
            ),
            decoration: BoxDecoration(
              borderRadius: Radii.all(Radii.md),
              border: Border.all(
                color: selected ? c.primary.withValues(alpha: 0.5) : c.hairline,
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 19, color: selected ? c.primary : c.textSecondary),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Text(
                    name,
                    style: text.bodyLarge?.copyWith(
                      color: selected ? c.primary : c.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '$count',
                  style: text.labelMedium?.copyWith(color: c.textTertiary),
                ),
                if (onRename != null || onDelete != null)
                  PopupMenuButton<String>(
                    tooltip: 'Modifier le dossier',
                    icon: Icon(Icons.more_vert_rounded,
                        size: 18, color: c.textTertiary),
                    onSelected: (v) {
                      if (v == 'rename') onRename?.call();
                      if (v == 'delete') onDelete?.call();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'rename',
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Renommer'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline_rounded,
                              color: c.danger),
                          title: Text('Supprimer',
                              style: TextStyle(color: c.danger)),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Boîte de saisie d'un nom de dossier.
Future<String?> _promptName(
  BuildContext context, {
  required String title,
  String? initial,
}) async {
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => _NamePromptDialog(title: title, initial: initial),
  );
  return (result == null || result.isEmpty) ? null : result;
}

/// Le contrôleur appartient à l'état de la boîte, pas à la fonction qui l'ouvre.
///
/// `showDialog` rend la main dès `Navigator.pop`, c'est-à-dire au *début* de
/// l'animation de sortie. Détruire le contrôleur juste après l'attente le
/// retirait donc sous un `TextField` encore monté pour toute la durée de la
/// transition : « A TextEditingController was used after being disposed », suivi
/// d'une cascade d'assertions qui laissait l'arbre incohérent pour le reste de
/// la session. Ici `dispose` n'arrive qu'au démontage réel de la route.
class _NamePromptDialog extends StatefulWidget {
  const _NamePromptDialog({required this.title, this.initial});

  final String title;
  final String? initial;

  @override
  State<_NamePromptDialog> createState() => _NamePromptDialogState();
}

class _NamePromptDialogState extends State<_NamePromptDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Nom du dossier'),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Valider'),
        ),
      ],
    );
  }
}
