import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../services/api_service.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  final ApiService api;
  const SettingsScreen({super.key, required this.api});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _biometricEnabled = true;
  bool _showSiteIcons = true;
  int _autoLockMinutes = 5;

  Future<void> _deleteAllPasswords() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: PassVaultApp.brandSlate,
        title: const Text('⚠️ Supprimer le coffre-fort ?'),
        content: const Text(
          'Tous vos mots de passe seront définitivement supprimés. '
          'Cette action est irréversible.',
        ),
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
            child: const Text('Tout supprimer'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    // Récupérer tous les mots de passe et les supprimer un par un
    final passwords = await widget.api.getPasswords();
    if (!mounted) return;

    if (passwords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun mot de passe à supprimer')),
      );
      return;
    }

    int deleted = 0;
    for (final p in passwords) {
      final success = await widget.api.deletePassword(p['id'] as int);
      if (success) deleted++;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('🗑️ $deleted mot(s) de passe supprimé(s)'),
        backgroundColor: PassVaultApp.errorContainer,
      ),
    );
  }

  void _showAutoLockPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: PassVaultApp.brandSlate,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 32, height: 4,
            decoration: BoxDecoration(
              color: PassVaultApp.brandGrey.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Verrouillage automatique',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
          ),
          const SizedBox(height: 16),
          ...[1, 5, 15, 30, 60].map((m) => ListTile(
            leading: Icon(
              _autoLockMinutes == m ? Icons.radio_button_checked : Icons.radio_button_off,
              color: PassVaultApp.electricBlue,
            ),
            title: Text(
              m < 60 ? '$m minute(s)' : '${m ~/ 60} heure(s)',
              style: const TextStyle(color: Colors.white),
            ),
            onTap: () {
              setState(() => _autoLockMinutes = m);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('✅ Verrouillage après $_autoLockMinutes min')),
              );
            },
          )),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PassVaultApp.deepNavy,
      appBar: AppBar(title: const Text('Paramètres')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Sécurité ──
          _sectionHeader('Sécurité'),
          _settingsTile(
            icon: Icons.fingerprint,
            title: 'Déverrouillage biométrique',
            subtitle: 'Empreinte digitale / Face ID',
            trailing: Switch(
              value: _biometricEnabled,
              activeColor: PassVaultApp.brandGreen,
              onChanged: (v) {
                setState(() => _biometricEnabled = v);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(v ? '✅ Biométrie activée' : '❌ Biométrie désactivée'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
          ),
          _settingsTile(
            icon: Icons.timer_outlined,
            title: 'Verrouillage automatique',
            subtitle: 'Après $_autoLockMinutes minute(s) d\'inactivité',
            onTap: _showAutoLockPicker,
          ),
          const SizedBox(height: 16),

          // ── Sauvegarde et Export ──
          _sectionHeader('Sauvegarde et Export'),
          _settingsTile(
            icon: Icons.download_outlined,
            title: 'Exporter le coffre-fort (JSON)',
            subtitle: 'Sauvegarder tous vos mots de passe',
            onTap: () {
              // Retourner au coffre qui a déjà cette fonctionnalité
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('📤 Utilisez le menu ⋮ du Coffre pour exporter'),
                ),
              );
            },
          ),
          _settingsTile(
            icon: Icons.upload_outlined,
            title: 'Importer des mots de passe',
            subtitle: 'Restaurer depuis une sauvegarde',
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('📥 Utilisez le menu ⋮ du Coffre pour importer'),
                ),
              );
            },
          ),
          const SizedBox(height: 16),

          // ── Apparence ──
          _sectionHeader('Apparence'),
          _settingsTile(
            icon: Icons.dark_mode,
            title: 'Thème sombre',
            subtitle: 'Toujours activé',
            trailing: Icon(Icons.check, color: PassVaultApp.brandGreen, size: 20),
          ),
          _settingsTile(
            icon: Icons.grid_view_outlined,
            title: 'Icônes des sites',
            subtitle: 'Afficher les icônes colorées par site',
            trailing: Switch(
              value: _showSiteIcons,
              activeColor: PassVaultApp.brandGreen,
              onChanged: (v) {
                setState(() => _showSiteIcons = v);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(v ? '✅ Icônes activées' : '❌ Icônes désactivées'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // ── À propos ──
          _sectionHeader('À propos'),
          _settingsTile(
            icon: Icons.info_outline,
            title: 'Version',
            subtitle: 'PassVault v2.0.0',
          ),
          _settingsTile(
            icon: Icons.security_outlined,
            title: 'Chiffrement',
            subtitle: 'AES-256 + PBKDF2 (10 000 itérations)',
          ),
          _settingsTile(
            icon: Icons.code,
            title: 'Développeur',
            subtitle: 'Tannou Abou',
          ),
          const SizedBox(height: 24),

          // ── Verrouiller ──
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
              icon: const Icon(Icons.lock_outline, color: Colors.red),
              label: const Text('Verrouiller PassVault',
                  style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red, width: 1),
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Supprimer le coffre ──
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _deleteAllPasswords,
              icon: const Icon(Icons.delete_forever,
                  color: PassVaultApp.errorContainer),
              label: const Text('Supprimer le coffre-fort',
                  style: TextStyle(color: PassVaultApp.errorContainer)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(
                    color: PassVaultApp.errorContainer, width: 1),
                minimumSize: const Size(0, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, top: 0, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'JetBrains Mono',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
          color: PassVaultApp.electricBlue,
        ),
      ),
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: PassVaultApp.brandSlate,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: PassVaultApp.brandBorder),
      ),
      child: ListTile(
        leading: Icon(icon, color: PassVaultApp.brandGrey, size: 22),
        title: Text(title,
            style: const TextStyle(
                fontSize: 14, color: Colors.white)),
        subtitle: subtitle != null
            ? Text(subtitle,
                style: const TextStyle(
                    fontSize: 12, color: PassVaultApp.brandGrey))
            : null,
        trailing: trailing,
        onTap: onTap,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
