import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../main.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'add_password_screen.dart';
import 'generator_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  final ApiService api;
  const HomeScreen({super.key, required this.api});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Map<String, dynamic>> _passwords = [];
  bool _loading = true;
  String _search = '';
  int _currentTab = 0;
  int _compromisedCount = 0;
  String? _expandedSite;

  @override
  void initState() {
    super.initState();
    _loadPasswords();
  }

  Future<void> _loadPasswords() async {
    setState(() => _loading = true);
    final passwords = await widget.api.getPasswords();
    if (mounted) {
      // Analyse de sécurité simple
      int weak = 0;
      final weakPatterns = [
        '123456', 'password', 'azerty', 'qwerty', '111111',
        'admin', 'letmein', 'welcome', 'monkey', 'dragon',
      ];
      for (final p in passwords) {
        final pwd = (p['password'] ?? '').toString().toLowerCase();
        if (pwd.length < 8 || weakPatterns.any((w) => pwd.contains(w))) {
          weak++;
        }
      }
      setState(() {
        _passwords = passwords;
        _compromisedCount = weak;
        _loading = false;
      });
    }
  }

  Future<void> _deletePassword(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PassVaultApp.brandSlate,
        title: const Text('Supprimer ?'),
        content: const Text('Ce mot de passe sera définitivement supprimé.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: PassVaultApp.errorContainer,
            ),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.api.deletePassword(id);
      _loadPasswords();
    }
  }

  // ─── Export / Import (inchangé) ───
  Future<void> _exportPasswords() async {
    final passwords = await widget.api.exportPasswords();
    if (!mounted) return;
    if (passwords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun mot de passe à exporter')),
      );
      return;
    }
    final cleanList = passwords.map((p) {
      final m = <String, dynamic>{
        'site': p['site'],
        'email': p['email'],
        'password': p['password'],
      };
      if (p['note'] != null && (p['note'] as String).isNotEmpty) {
        m['note'] = p['note'];
      }
      return m;
    }).toList();
    final jsonStr = const JsonEncoder.withIndent('  ').convert(cleanList);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/passvault_export.json');
    await file.writeAsString(jsonStr);
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'PassVault - Export JSON',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ ${passwords.length} mot(s) exporté(s)'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _exportCsv() async {
    final csv = await widget.api.exportCsv();
    if (!mounted) return;
    if (csv.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun mot de passe à exporter')),
      );
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/passvault_export.csv');
    await file.writeAsString(csv);
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'PassVault - Export CSV',
    );
    if (mounted) {
      final lines = csv.split('\n').length - 1;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ $lines mot(s) exporté(s) en CSV'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _importFromFile(String format) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: format == 'csv' ? ['csv'] : ['json'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final filePath = result.files.single.path;
    if (filePath == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final content = await File(filePath).readAsString();
      if (!mounted) return;
      Navigator.pop(context);
      if (format == 'csv') {
        await _importCsvContent(content);
      } else {
        await _importJsonContent(content);
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Erreur : ${e.toString()}')),
      );
    }
  }

  Future<void> _importJsonContent(String content) async {
    try {
      final parsed = jsonDecode(content);
      if (parsed is! List) throw FormatException('Tableau attendu');
      final entries = parsed.cast<Map<String, dynamic>>();
      if (entries.isEmpty) throw FormatException('Tableau vide');
      final count = await widget.api.importPasswords(entries);
      if (mounted && count > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ $count mot(s) importé(s)')),
        );
        _loadPasswords();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _importCsvContent(String content) async {
    final resp = await widget.api.importCsv(content);
    if (!mounted) return;
    if (resp['success'] == true) {
      final imported = resp['imported'] ?? 0;
      final errors = resp['errors'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ $imported importé(s)' +
              (errors > 0 ? ' ($errors erreur(s))' : '')),
        ),
      );
      _loadPasswords();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ ${resp['error'] ?? 'Erreur'}')),
      );
    }
  }

  // Icône par site
  IconData _siteIcon(String site) {
    final s = site.toLowerCase();
    if (s.contains('google') || s.contains('gmail')) return Icons.mail;
    if (s.contains('netflix')) return Icons.movie;
    if (s.contains('amazon')) return Icons.shopping_cart;
    if (s.contains('github')) return Icons.code;
    if (s.contains('facebook') || s.contains('instagram'))
      return Icons.people;
    if (s.contains('twitter') || s.contains('x.com')) return Icons.alternate_email;
    if (s.contains('linkedin')) return Icons.work;
    if (s.contains('bank') || s.contains('banque')) return Icons.account_balance;
    return Icons.language;
  }

  Color _siteColor(String site) {
    final s = site.toLowerCase();
    if (s.contains('google') || s.contains('gmail')) return const Color(0xFFEA4335);
    if (s.contains('netflix')) return const Color(0xFFE50914);
    if (s.contains('amazon')) return const Color(0xFFFF9900);
    if (s.contains('github')) return const Color(0xFF6E40C9);
    if (s.contains('facebook')) return const Color(0xFF1877F2);
    if (s.contains('linkedin')) return const Color(0xFF0A66C2);
    return PassVaultApp.electricBlue;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _passwords.where((p) {
      if (_search.isEmpty) return true;
      final site = (p['site'] ?? '').toString().toLowerCase();
      final email = (p['email'] ?? '').toString().toLowerCase();
      final q = _search.toLowerCase();
      return site.contains(q) || email.contains(q);
    }).toList();

    // Grouper par site
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final p in filtered) {
      final site = (p['site'] ?? '').toString();
      grouped.putIfAbsent(site.toLowerCase(), () => []);
      grouped[site.toLowerCase()]!.add(p);
    }
    final sortedSites = grouped.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Scaffold(
      backgroundColor: PassVaultApp.deepNavy,
      appBar: AppBar(
        title: const Text('PassVault'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: PassVaultApp.brandGrey),
            color: PassVaultApp.brandSlate,
            onSelected: (value) {
              if (value == 'export') _exportPasswords();
              if (value == 'export_csv') _exportCsv();
              if (value == 'import') _importFromFile('json');
              if (value == 'import_csv') _importFromFile('csv');
              if (value == 'logout') {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.code),
                  title: Text('Exporter JSON'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'export_csv',
                child: ListTile(
                  leading: Icon(Icons.table_chart),
                  title: Text('Exporter CSV'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.file_open_outlined),
                  title: Text('Importer JSON'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'import_csv',
                child: ListTile(
                  leading: Icon(Icons.table_chart_outlined),
                  title: Text('Importer CSV'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.lock_outline, color: Colors.red),
                  title: Text('Verrouiller', style: TextStyle(color: Colors.red)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Barre de recherche ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Rechercher un site...',
                hintStyle: const TextStyle(color: PassVaultApp.brandGrey),
                prefixIcon: const Icon(Icons.search, color: PassVaultApp.brandGrey),
                filled: true,
                fillColor: PassVaultApp.brandSlate,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),

          // ── Alerte sécurité ──
          if (_compromisedCount > 0 && !_loading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D1616),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF442222)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: PassVaultApp.errorContainer, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '$_compromisedCount mot(s) faible(s) ou compromis',
                        style: const TextStyle(
                          color: Color(0xFFFFDAD6),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _loadPasswords,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Analyser',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Liste groupée par site ──
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_open_rounded,
                                size: 64, color: PassVaultApp.brandGrey.withValues(alpha: 0.4)),
                            const SizedBox(height: 16),
                            Text(
                              _search.isEmpty
                                  ? 'Aucun mot de passe'
                                  : 'Aucun résultat',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _search.isEmpty
                                  ? 'Appuyez sur + pour en ajouter un'
                                  : 'Essayez un autre terme',
                              style: const TextStyle(
                                color: PassVaultApp.brandGrey,
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadPasswords,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: sortedSites.length,
                          itemBuilder: (ctx, i) {
                            final entry = sortedSites[i];
                            final siteName = entry.value.first['site']?.toString() ?? 'Site';
                            final entries = entry.value;
                            final isExpanded = _expandedSite == entry.key;

                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: PassVaultApp.brandSlate,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: PassVaultApp.brandBorder),
                                ),
                                child: Column(
                                  children: [
                                    // En-tête du groupe
                                    InkWell(
                                      borderRadius: BorderRadius.circular(12),
                                      onTap: () {
                                        setState(() {
                                          _expandedSite = isExpanded ? null : entry.key;
                                        });
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(14),
                                        child: Row(
                                          children: [
                                            // Icône
                                            Container(
                                              width: 48,
                                              height: 48,
                                              decoration: BoxDecoration(
                                                color: _siteColor(siteName).withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Icon(
                                                _siteIcon(siteName),
                                                color: _siteColor(siteName),
                                                size: 24,
                                              ),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    siteName,
                                                    style: const TextStyle(
                                                      fontSize: 16,
                                                      fontWeight: FontWeight.w600,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '${entries.length} mot(s) de passe',
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      color: PassVaultApp.brandGrey,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Icon(
                                              isExpanded
                                                  ? Icons.expand_less
                                                  : Icons.expand_more,
                                              color: PassVaultApp.brandGrey,
                                              size: 24,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),

                                    // Sous-entrées
                                    if (isExpanded)
                                      ...entries.map((p) {
                                        final email = p['email']?.toString() ?? '';
                                        final id = p['id'] as int;

                                        return Container(
                                          padding: const EdgeInsets.only(
                                            left: 76,
                                            right: 8,
                                            bottom: 12,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: PassVaultApp.brandNavy,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        email,
                                                        style: const TextStyle(
                                                          fontSize: 14,
                                                          fontWeight: FontWeight.w500,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        '••••••••••••',
                                                        style: TextStyle(
                                                          fontSize: 13,
                                                          fontFamily: 'JetBrains Mono',
                                                          color: PassVaultApp.brandGrey.withValues(alpha: 0.7),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.copy,
                                                      size: 20,
                                                      color: PassVaultApp.brandGrey),
                                                  onPressed: () {
                                                    Clipboard.setData(ClipboardData(
                                                        text: p['password'] ?? ''));
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(
                                                        content: Text('Copié !'),
                                                        duration: Duration(seconds: 2),
                                                      ),
                                                    );
                                                  },
                                                ),
                                                PopupMenuButton<String>(
                                                  icon: const Icon(Icons.more_vert,
                                                      size: 20,
                                                      color: PassVaultApp.brandGrey),
                                                  color: PassVaultApp.brandSlate,
                                                  onSelected: (v) {
                                                    if (v == 'edit') _editPassword(p);
                                                    if (v == 'delete') _deletePassword(id);
                                                    if (v == 'show') _showPassword(p);
                                                  },
                                                  itemBuilder: (_) => [
                                                    const PopupMenuItem(
                                                      value: 'show',
                                                      child: ListTile(
                                                        leading: Icon(Icons.visibility),
                                                        title: Text('Voir'),
                                                        contentPadding: EdgeInsets.zero,
                                                      ),
                                                    ),
                                                    const PopupMenuItem(
                                                      value: 'edit',
                                                      child: ListTile(
                                                        leading: Icon(Icons.edit),
                                                        title: Text('Modifier'),
                                                        contentPadding: EdgeInsets.zero,
                                                      ),
                                                    ),
                                                    const PopupMenuItem(
                                                      value: 'delete',
                                                      child: ListTile(
                                                        leading: Icon(Icons.delete, color: Colors.red),
                                                        title: Text('Supprimer', style: TextStyle(color: Colors.red)),
                                                        contentPadding: EdgeInsets.zero,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),

      // ── FAB + ──
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => AddPasswordScreen(api: widget.api),
            ),
          );
          if (result == true) _loadPasswords();
        },
        backgroundColor: PassVaultApp.electricBlue,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.add, color: Colors.white),
      ),

      // ── Bottom Navigation ──
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: PassVaultApp.brandNavy,
          border: Border(
            top: BorderSide(color: PassVaultApp.brandBorder, width: 0.5),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _bottomNavItem(
                  icon: Icons.lock_outline,
                  activeIcon: Icons.lock,
                  label: 'Coffre',
                  index: 0,
                ),
                _bottomNavItem(
                  icon: Icons.auto_fix_high_outlined,
                  activeIcon: Icons.auto_fix_high,
                  label: 'Générateur',
                  index: 1,
                ),
                _bottomNavItem(
                  icon: Icons.settings_outlined,
                  activeIcon: Icons.settings,
                  label: 'Paramètres',
                  index: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomNavItem({
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int index,
  }) {
    final isActive = _currentTab == index;
    final color = isActive ? PassVaultApp.electricBlue : PassVaultApp.brandGrey;

    return GestureDetector(
      onTap: () {
        if (index == 0) return; // déjà sur Vault
        if (index == 1) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => GeneratorScreen(),
            ),
          );
        } else if (index == 2) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SettingsScreen(api: widget.api),
            ),
          );
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isActive ? activeIcon : icon, color: color, size: 22),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Détail mot de passe (bottom sheet) ───
  void _showPassword(Map<String, dynamic> p) {
    final site = p['site'] ?? '';
    final email = p['email'] ?? '';
    final password = p['password'] ?? '';
    final note = p['note'] ?? '';

    showModalBottomSheet(
      context: context,
      backgroundColor: PassVaultApp.brandSlate,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: PassVaultApp.brandGrey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(site.toString(),
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
            const SizedBox(height: 20),
            _detailRow('Email', email.toString()),
            const SizedBox(height: 12),
            _detailRow('Mot de passe', password.toString()),
            if (note.toString().isNotEmpty) ...[
              const SizedBox(height: 12),
              _detailRow('Note', note.toString()),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _editPassword(p);
                    },
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('Modifier'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: PassVaultApp.brandGrey,
                      side: const BorderSide(color: PassVaultApp.brandBorder),
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Clipboard.setData(
                          ClipboardData(text: password.toString()));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Mot de passe copié !')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copier'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'JetBrains Mono',
            fontSize: 12,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
            color: PassVaultApp.brandGrey,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            color: Colors.white,
            fontFamily: 'JetBrains Mono',
          ),
        ),
      ],
    );
  }

  Future<void> _editPassword(Map<String, dynamic> p) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddPasswordScreen(
          api: widget.api,
          existingPassword: p,
        ),
      ),
    );
    if (result == true) _loadPasswords();
  }
}
