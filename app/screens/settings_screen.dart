import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';
import '../services/api_service.dart';
import 'login_screen.dart';

class SettingsScreen extends StatelessWidget {
  final ApiService api;
  const SettingsScreen({super.key, required this.api});

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
              value: true,
              activeColor: PassVaultApp.brandGreen,
              onChanged: (_) {},
            ),
          ),
          _settingsTile(
            icon: Icons.timer_outlined,
            title: 'Verrouillage automatique',
            subtitle: 'Après 5 minutes d\'inactivité',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Paramètre à venir')),
              );
            },
          ),
          const SizedBox(height: 16),

          // ── Sauvegarde ──
          _sectionHeader('Sauvegarde et Export'),
          _settingsTile(
            icon: Icons.download_outlined,
            title: 'Exporter le coffre-fort',
            subtitle: 'Sauvegarder tous vos mots de passe',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Utilisez Exporter dans le menu du Vault')),
              );
            },
          ),
          _settingsTile(
            icon: Icons.upload_outlined,
            title: 'Importer des mots de passe',
            subtitle: 'Restaurer depuis une sauvegarde',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Utilisez Importer dans le menu du Vault')),
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
            title: 'Afficher les icônes des sites',
            subtitle: 'Activer les couleurs par site',
            trailing: Switch(
              value: true,
              activeColor: PassVaultApp.brandGreen,
              onChanged: (_) {},
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
                  MaterialPageRoute(
                      builder: (_) => const LoginScreen()),
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
              onPressed: () async {
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

                if (confirm == true && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Fonctionnalité à implémenter'),
                    ),
                  );
                }
              },
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
