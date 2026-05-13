import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'add_password_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _loadPasswords();
  }

  Future<void> _loadPasswords() async {
    setState(() => _loading = true);
    final passwords = await widget.api.getPasswords();
    if (mounted) {
      setState(() {
        _passwords = passwords;
        _loading = false;
      });
    }
  }

  Future<void> _deletePassword(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ?'),
        content: const Text('Ce mot de passe sera définitivement supprimé.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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

  // ==================== EXPORT JSON ====================
  // ==================== EXPORT JSON (fichier) ====================
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
      return {
        'site': p['site'],
        'email': p['email'],
        'password': p['password'],
        if (p['note'] != null && (p['note'] as String).isNotEmpty) 'note': p['note'],
      };
    }).toList();

    final jsonStr = const JsonEncoder.withIndent('  ').convert(cleanList);

    // Sauvegarder dans un fichier
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/passvault_export.json');
    await file.writeAsString(jsonStr);

    // Partager le fichier
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Mes mot de passe - Export JSON',
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ ${passwords.length} mot(s) exporté(s) en JSON'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ==================== EXPORT CSV (fichier) ====================
  Future<void> _exportCsv() async {
    final csv = await widget.api.exportCsv();
    if (!mounted) return;

    if (csv.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun mot de passe à exporter')),
      );
      return;
    }

    // Sauvegarder dans un fichier
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/passvault_export.csv');
    await file.writeAsString(csv);

    // Partager le fichier
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Mes mot de passe - Export CSV',
    );

    if (!mounted) return;
    final lines = csv.split('\n').length - 1;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ $lines mot(s) exporté(s) en CSV'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ==================== IMPORT FICHIER (CSV ou JSON) ====================
  Future<void> _importFromFile(String format) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: format == 'csv' ? ['csv'] : ['json'],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;

    final filePath = result.files.single.path;
    if (filePath == null) return;

    // Lire le fichier
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final content = await File(filePath).readAsString();

      if (!mounted) return;
      Navigator.pop(context); // ferme le loading

      if (format == 'csv') {
        await _importCsvContent(content);
      } else {
        await _importJsonContent(content);
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Erreur de lecture : ${e.toString()}'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _importJsonContent(String content) async {
    try {
      final parsed = jsonDecode(content);
      if (parsed is! List) throw FormatException('Le fichier doit contenir un tableau');

      final entries = parsed.cast<Map<String, dynamic>>();
      if (entries.isEmpty) throw FormatException('Tableau vide');

      final count = await widget.api.importPasswords(entries);
      if (!mounted) return;

      if (count > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $count mot(s) importé(s) depuis le fichier JSON'),
            duration: const Duration(seconds: 3),
          ),
        );
        _loadPasswords();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Erreur JSON : ${e.toString()}'),
          duration: const Duration(seconds: 4),
        ),
      );
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
          content: Text('✅ $imported importé(s) depuis le fichier CSV' +
              (errors > 0 ? ' ($errors erreur(s))' : '')),
          duration: const Duration(seconds: 3),
        ),
      );
      _loadPasswords();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ ${resp['error'] ?? 'Erreur inconnue'}'),
          duration: const Duration(seconds: 4),
        ),
      );
    }
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes mot de passe'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
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
                  title: Text('Exporter (JSON)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'export_csv',
                child: ListTile(
                  leading: Icon(Icons.table_chart),
                  title: Text('Exporter (CSV)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.file_open_outlined),
                  title: Text('Importer (fichier JSON)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'import_csv',
                child: ListTile(
                  leading: Icon(Icons.table_chart_outlined),
                  title: Text('Importer (fichier CSV)'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout, color: Colors.red),
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
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Rechercher un site...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_open, size: 64, color: Colors.grey[600]),
                            const SizedBox(height: 12),
                            Text(
                              'Aucun mot de passe',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Appuyez sur + pour en ajouter un',
                              style: TextStyle(color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadPasswords,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) {
                            final p = filtered[i];
                            final site = p['site'] ?? 'Site inconnu';
                            final email = p['email'] ?? '';
                            final id = p['id'];

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.blue.withOpacity(0.2),
                                  child: Text(
                                    _firstLetter(site.toString()),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                                title: Text(site.toString()),
                                subtitle: Text(email.toString()),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () => _editPassword(p),
                                      tooltip: 'Modifier',
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.copy),
                                      onPressed: () {
                                        Clipboard.setData(
                                          ClipboardData(text: p['password'] ?? ''),
                                        );
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Mot de passe copié pour $site'),
                                            duration: const Duration(seconds: 2),
                                          ),
                                        );
                                      },
                                      tooltip: 'Copier',
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.red),
                                      onPressed: () => _deletePassword(id),
                                      tooltip: 'Supprimer',
                                    ),
                                  ],
                                ),
                                onTap: () => _showPassword(context, p),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
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
        child: const Icon(Icons.add),
      ),
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

  String _firstLetter(String s) {
    if (s.isEmpty) return '?';
    return s[0].toUpperCase();
  }

  void _showPassword(BuildContext context, Map<String, dynamic> p) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p['site'] ?? '',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            _infoRow('Email', p['email'] ?? ''),
            const SizedBox(height: 8),
            _infoRow('Mot de passe', p['password'] ?? ''),
            if (p['note'] != null && p['note'].toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              _infoRow('Note', p['note'] ?? ''),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _editPassword(p);
                    },
                    icon: const Icon(Icons.edit),
                    label: const Text('Modifier'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Fermer'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(label,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        Expanded(child: Text(value)),
      ],
    );
  }
}
