import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/app_theme.dart';
import '../../core/design/tokens.dart';
import '../../data/api/api_client.dart';
import '../../data/models/cipher.dart';
import '../../data/vault_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/vault_item_tile.dart';
import '../security/vault_health.dart';
import 'folder_sheet.dart';
import 'item_detail_screen.dart';
import 'item_edit_screen.dart';
import 'trash_screen.dart';

/// Filtres de la liste. Le filtre par dossier est porté séparément puisqu'il se
/// combine avec les autres.
enum VaultFilter {
  all('Tous', Icons.apps_rounded),
  favorites('Favoris', Icons.star_rounded),
  logins('Identifiants', Icons.key_rounded),
  cards('Cartes', Icons.credit_card_rounded),
  identities('Identités', Icons.badge_outlined),
  notes('Notes', Icons.sticky_note_2_outlined);

  const VaultFilter(this.label, this.icon);
  final String label;
  final IconData icon;

  bool accepts(CipherItem item) => switch (this) {
        VaultFilter.all => true,
        VaultFilter.favorites => item.favorite,
        VaultFilter.logins => item.type == CipherType.login,
        VaultFilter.cards => item.type == CipherType.card,
        VaultFilter.identities => item.type == CipherType.identity,
        VaultFilter.notes => item.type == CipherType.secureNote,
      };
}

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  VaultFilter _filter = VaultFilter.all;
  String? _folderId;
  String? _syncError;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _sync() async {
    setState(() => _syncError = null);
    try {
      await context.read<VaultRepository>().sync();
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _syncError = e.message);
    }
  }

  /// La recherche porte sur le coffre déchiffré en mémoire. Le serveur ne peut
  /// pas la faire : il ne voit que des blobs opaques.
  List<CipherItem> _visible(List<CipherItem> items) {
    final query = _query.trim().toLowerCase();
    return items.where((item) {
      if (!_filter.accepts(item)) return false;
      if (_folderId != null && item.folderId != _folderId) return false;
      if (query.isEmpty) return true;
      return item.data.searchHaystack.contains(query);
    }).toList(growable: false)
      ..sort((a, b) {
        // Favoris d'abord, puis alphabétique. Un tri par date de révision
        // remonterait ce qu'on vient de modifier, ce qui déplace les lignes sous
        // le doigt d'une fois à l'autre.
        if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
        return a.data.name.toLowerCase().compareTo(b.data.name.toLowerCase());
      });
  }

  Future<void> _openNew() async {
    final type = await showModalBottomSheet<CipherType>(
      context: context,
      builder: (_) => const _TypePickerSheet(),
    );
    if (type == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ItemEditScreen(type: type, folderId: _folderId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    final repo = context.watch<VaultRepository>();

    final items = repo.items;
    final visible = _visible(items);
    final health = VaultHealth.analyse(items);
    final healthByItemId = {
      for (final h in health.problematic)
        if (h.item.id != null) h.item.id!: h,
    };
    final activeFolder =
        _folderId == null ? null : repo.folders.where((f) => f.id == _folderId);

    return Scaffold(
      backgroundColor: c.background,
      body: RefreshIndicator(
        onRefresh: _sync,
        color: c.primary,
        backgroundColor: c.surface,
        child: CustomScrollView(
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
                              Text(
                                activeFolder?.isNotEmpty == true
                                    ? activeFolder!.first.name
                                    : 'Mon coffre',
                                style: text.headlineMedium,
                              ),
                              const SizedBox(height: Gap.xxs),
                              _SubtitleLine(
                                count: items.length,
                                lastSync: repo.lastSync,
                              ),
                            ],
                          ),
                        ),
                        _OverflowMenu(
                          onFolders: () => _pickFolder(repo),
                          onTrash: _openTrash,
                          onLock: () => repo.lock(),
                        ),
                      ],
                    ),
                    const SizedBox(height: Gap.xl),

                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Rechercher un site, un identifiant…',
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Effacer',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                                icon: const Icon(Icons.close_rounded, size: 18),
                              ),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: Gap.md),
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),

                    if (_syncError != null) ...[
                      const SizedBox(height: Gap.lg),
                      InlineError(message: _syncError!, onRetry: _sync),
                    ],

                    if (repo.undecryptable.isNotEmpty) ...[
                      const SizedBox(height: Gap.lg),
                      _UndecryptableNotice(count: repo.undecryptable.length),
                    ],

                    if (!health.isClean && _query.isEmpty) ...[
                      const SizedBox(height: Gap.lg),
                      _HealthBanner(report: health),
                    ],

                    const SizedBox(height: Gap.xl),
                    _FilterBar(
                      selected: _filter,
                      folderName: activeFolder?.isNotEmpty == true
                          ? activeFolder!.first.name
                          : null,
                      onSelected: (f) => setState(() => _filter = f),
                      onClearFolder: () => setState(() => _folderId = null),
                    ),
                    const SizedBox(height: Gap.lg),

                    if (visible.isNotEmpty)
                      SectionLabel(
                        '${visible.length} élément${visible.length > 1 ? 's' : ''}',
                      ),
                  ],
                ),
              ),
            ),

            if (visible.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _emptyState(items.isEmpty),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, 140),
                sliver: SliverList.separated(
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: Gap.sm),
                  itemBuilder: (context, i) {
                    final item = visible[i];
                    final issue =
                        healthByItemId[item.id]?.primaryIssue?.label;
                    return StaggeredEntrance(
                      index: i,
                      child: VaultItemTile(
                        item: item,
                        warning: issue,
                        onTap: () => _openDetail(item),
                        onCopyPassword: () => _copyPassword(item),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: _AddButton(onPressed: _openNew),
    );
  }

  Widget _emptyState(bool vaultIsEmpty) {
    if (vaultIsEmpty) {
      return EmptyState(
        icon: Icons.shield_outlined,
        title: 'Coffre vide',
        message: 'Ajoutez un premier identifiant. Il sera chiffré sur cet '
            'appareil avant de partir vers le serveur.',
        action: FilledButton.icon(
          onPressed: _openNew,
          icon: const Icon(Icons.add_rounded, size: 20),
          label: const Text('Ajouter un élément'),
        ),
      );
    }
    return EmptyState(
      icon: Icons.search_off_rounded,
      title: 'Aucun résultat',
      message: _query.isEmpty
          ? 'Aucun élément ne correspond à ce filtre.'
          : 'Rien ne correspond à « $_query ».',
      action: OutlinedButton(
        onPressed: () {
          _searchController.clear();
          setState(() {
            _query = '';
            _filter = VaultFilter.all;
            _folderId = null;
          });
        },
        child: const Text('Réinitialiser les filtres'),
      ),
    );
  }

  Future<void> _copyPassword(CipherItem item) async {
    final data = item.data;
    if (data is! LoginData || data.password.isEmpty) {
      AppFeedback.failure(context, 'Cet élément n’a pas de mot de passe');
      return;
    }
    await AppFeedback.copyValue(context, data.password, 'Mot de passe');
  }

  void _openDetail(CipherItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ItemDetailScreen(itemId: item.id!)),
    );
  }

  void _openTrash() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TrashScreen()),
    );
  }

  Future<void> _pickFolder(VaultRepository repo) async {
    final result = await showModalBottomSheet<FolderSelection>(
      context: context,
      isScrollControlled: true,
      builder: (_) => FolderSheet(selectedId: _folderId),
    );
    if (result == null || !mounted) return;
    setState(() => _folderId = result.folderId);
  }
}

class _SubtitleLine extends StatelessWidget {
  const _SubtitleLine({required this.count, required this.lastSync});

  final int count;
  final DateTime? lastSync;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final parts = <String>['$count élément${count > 1 ? 's' : ''}'];
    if (lastSync != null) {
      final ago = DateTime.now().difference(lastSync!);
      parts.add(switch (ago) {
        Duration(inMinutes: < 1) => 'synchronisé à l’instant',
        Duration(inMinutes: final m) when m < 60 => 'synchronisé il y a $m min',
        Duration(inHours: final h) when h < 24 => 'synchronisé il y a $h h',
        _ => 'synchronisé il y a ${ago.inDays} j',
      });
    }
    return Text(
      parts.join(' · '),
      style: Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(color: c.textTertiary),
    );
  }
}

class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({
    required this.onFolders,
    required this.onTrash,
    required this.onLock,
  });

  final VoidCallback onFolders;
  final VoidCallback onTrash;
  final VoidCallback onLock;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return PopupMenuButton<String>(
      tooltip: 'Plus d’actions',
      icon: Container(
        width: TouchTarget.minimum,
        height: TouchTarget.minimum,
        decoration: BoxDecoration(
          color: c.surface,
          shape: BoxShape.circle,
          border: Border.all(color: c.hairline),
        ),
        child: Icon(Icons.more_horiz_rounded, size: 20, color: c.textSecondary),
      ),
      onSelected: (value) => switch (value) {
        'folders' => onFolders(),
        'trash' => onTrash(),
        'lock' => onLock(),
        _ => null,
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'folders',
          child: ListTile(
            leading: Icon(Icons.folder_outlined),
            title: Text('Dossiers'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'trash',
          child: ListTile(
            leading: Icon(Icons.delete_outline_rounded),
            title: Text('Corbeille'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'lock',
          child: ListTile(
            leading: Icon(Icons.lock_outline_rounded, color: c.warning),
            title: Text('Verrouiller', style: TextStyle(color: c.warning)),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

/// Bandeau de santé du coffre. Annonce un compte et mène au détail — pas une
/// alerte vague avec un bouton « Analyser » qui n'analysait rien.
class _HealthBanner extends StatelessWidget {
  const _HealthBanner({required this.report});

  final VaultHealthReport report;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    final count = report.totalProblems;

    return HairlineCard(
      padding: const EdgeInsets.all(Gap.lg),
      onTap: () {
        // L'onglet Sécurité porte le détail ; on y renvoie plutôt que de
        // dupliquer la liste ici.
        AppFeedback.show(
          context,
          'Détail dans l’onglet Sécurité',
          icon: Icons.health_and_safety_outlined,
          tint: c.warning,
        );
      },
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: c.warning.withValues(alpha: 0.16),
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
                Text(
                  '$count mot${count > 1 ? 's' : ''} de passe à revoir',
                  style: text.titleMedium,
                ),
                const SizedBox(height: Gap.xxs),
                Text(
                  report.summaryLine,
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

/// Signale les éléments illisibles au lieu de les faire disparaître, comme le
/// faisait la v1 en avalant les erreurs de déchiffrement.
class _UndecryptableNotice extends StatelessWidget {
  const _UndecryptableNotice({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return InlineError(
      message: '$count élément${count > 1 ? 's' : ''} n’a pas pu être '
          'déchiffré. Il reste stocké sur le serveur, mais son contenu est '
          'abîmé — probablement écrit par une version antérieure.',
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selected,
    required this.onSelected,
    this.folderName,
    this.onClearFolder,
  });

  final VaultFilter selected;
  final ValueChanged<VaultFilter> onSelected;
  final String? folderName;
  final VoidCallback? onClearFolder;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          if (folderName != null) ...[
            _Chip(
              label: folderName!,
              icon: Icons.folder_rounded,
              selected: true,
              onTap: onClearFolder ?? () {},
              trailing: Icons.close_rounded,
            ),
            const SizedBox(width: Gap.sm),
          ],
          for (final filter in VaultFilter.values) ...[
            _Chip(
              label: filter.label,
              icon: filter.icon,
              selected: filter == selected,
              onTap: () => onSelected(filter),
            ),
            const SizedBox(width: Gap.sm),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    return Material(
      color: selected ? c.primaryWash : c.surface,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.md,
            vertical: Gap.sm,
          ),
          decoration: BoxDecoration(
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
              if (trailing != null) ...[
                const SizedBox(width: Gap.sm),
                Icon(trailing, size: 14, color: c.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Container(
      decoration: BoxDecoration(
        borderRadius: Radii.all(Radii.md),
        // Seul élément de l'interface à porter une ombre : c'est ce qui le
        // désigne comme l'action principale.
        boxShadow: [
          BoxShadow(
            color: c.primary.withValues(alpha: 0.42),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: onPressed,
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        elevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: Radii.all(Radii.md)),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Ajouter'),
      ),
    );
  }
}

/// Choix du type au moment de créer un élément. Un seul bouton « + » qui ouvre
/// un formulaire d'identifiant obligerait à changer de type après coup.
class _TypePickerSheet extends StatelessWidget {
  const _TypePickerSheet();

  static const _descriptions = {
    CipherType.login: 'Site, identifiant, mot de passe, code à usage unique',
    CipherType.card: 'Numéro, échéance, cryptogramme',
    CipherType.identity: 'Nom, adresse, pièces d’identité',
    CipherType.secureNote: 'Texte libre chiffré',
  };

  static const _icons = {
    CipherType.login: Icons.key_rounded,
    CipherType.card: Icons.credit_card_rounded,
    CipherType.identity: Icons.badge_outlined,
    CipherType.secureNote: Icons.sticky_note_2_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.xl, 0, Gap.xl, Gap.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nouvel élément', style: text.titleLarge),
            const SizedBox(height: Gap.xl),
            for (final type in CipherType.values)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.sm),
                child: HairlineCard(
                  padding: const EdgeInsets.all(Gap.md),
                  onTap: () => Navigator.of(context).pop(type),
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: c.primaryWash,
                          borderRadius: Radii.all(Radii.sm),
                        ),
                        child: Icon(_icons[type], size: 20, color: c.primary),
                      ),
                      const SizedBox(width: Gap.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(type.label, style: text.titleMedium),
                            const SizedBox(height: Gap.xxs),
                            Text(
                              _descriptions[type]!,
                              style: text.bodySmall
                                  ?.copyWith(color: c.textTertiary),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, color: c.textTertiary),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
