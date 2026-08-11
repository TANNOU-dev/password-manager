import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/app_theme.dart';
import '../../core/design/tokens.dart';
import '../../data/api/api_client.dart';
import '../../data/export/vault_export.dart';
import '../../data/import/importers.dart';
import '../../data/models/cipher.dart';
import '../../data/vault_repository.dart';
import '../../widgets/common.dart';

/// Import d'un coffre existant.
///
/// Trois temps, et le deuxième est le plus important : on montre ce qui a été
/// reconnu **avant** d'écrire quoi que ce soit. Un import qui s'exécute
/// directement laisse l'utilisateur découvrir après coup qu'il a perdu la moitié
/// de ses entrées.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  ParsedImport? _parsed;
  String? _fileName;
  String? _error;
  bool _busy = false;
  String? _progress;
  int? _imported;

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
      _parsed = null;
      _imported = null;
    });

    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: importExtensions,
        withData: kIsWeb,
      );
    } catch (e) {
      setState(() => _error = 'Impossible d’ouvrir le sélecteur : $e');
      return;
    }
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final String content;
    try {
      // Sur le web il n'y a pas de chemin : seuls les octets remontent.
      if (file.bytes != null) {
        content = utf8.decode(file.bytes!, allowMalformed: true);
      } else if (file.path != null) {
        content = await File(file.path!).readAsString();
      } else {
        setState(() => _error = 'Fichier illisible');
        return;
      }
    } catch (e) {
      setState(() => _error = 'Lecture impossible : $e');
      return;
    }

    if (!mounted) return;
    setState(() => _fileName = file.name);
    await _analyse(content);
  }

  Future<void> _analyse(String content) async {
    // Une sauvegarde chiffrée demande sa phrase de passe avant d'être lisible.
    if (VaultExporter.isEncryptedBackup(content)) {
      final password = await _askBackupPassword();
      if (password == null || !mounted) return;
      setState(() => _busy = true);
      try {
        final plain = await VaultExporter.decryptBackup(
          content,
          exportPassword: password,
        );
        if (!mounted) return;
        setState(() => _parsed = parseImport(plain));
      } on ExportException catch (e) {
        if (mounted) setState(() => _error = e.message);
      } on ImportFormatException catch (e) {
        if (mounted) setState(() => _error = e.message);
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }

    try {
      setState(() => _parsed = parseImport(content, fileName: _fileName));
    } on ImportFormatException catch (e) {
      setState(() => _error = e.message);
    }
  }

  Future<String?> _askBackupPassword() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sauvegarde chiffrée'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ce fichier est protégé par la phrase de passe choisie au moment '
              'de l’export — pas par votre mot de passe maître.',
            ),
            const SizedBox(height: Gap.lg),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              style: SecretText.of(ctx),
              decoration: const InputDecoration(labelText: 'Phrase de passe'),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Déchiffrer'),
          ),
        ],
      ),
    );
    controller.dispose();
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> _confirmImport() async {
    final parsed = _parsed;
    if (parsed == null) return;

    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Préparation…';
    });

    try {
      final count = await context.read<VaultRepository>().importParsed(
            parsed,
            onProgress: (step) {
              if (mounted) setState(() => _progress = step);
            },
          );
      if (!mounted) return;
      setState(() {
        _imported = count;
        _parsed = null;
      });
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _progress = null);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: const Text('Importer un coffre')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.sm, Gap.xl, Gap.giant),
        children: [
          if (_imported != null)
            _SuccessCard(count: _imported!, onDone: () => Navigator.pop(context))
          else ...[
            Text(
              'PassVault rechiffre chaque entrée avec votre clé avant de '
              'l’envoyer. Le fichier source, lui, est en clair : supprimez-le '
              'dès l’import terminé.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: Gap.xl),
            const _SupportedFormats(),
            const SizedBox(height: Gap.xl),

            if (_parsed == null)
              FilledButton.icon(
                onPressed: _busy ? null : _pickFile,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.folder_open_rounded, size: 20),
                label: const Text('Choisir un fichier'),
              ),

            if (_error != null) ...[
              const SizedBox(height: Gap.xl),
              InlineError(message: _error!),
            ],

            if (_parsed != null) ...[
              _PreviewCard(
                parsed: _parsed!,
                fileName: _fileName,
                progress: _progress,
              ),
              const SizedBox(height: Gap.xl),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _parsed = null;
                                _fileName = null;
                              }),
                      child: const Text('Annuler'),
                    ),
                  ),
                  const SizedBox(width: Gap.md),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _confirmImport,
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_rounded, size: 18),
                      label: Text(
                        _busy
                            ? 'Chiffrement…'
                            : 'Importer ${_parsed!.count} élément'
                                '${_parsed!.count > 1 ? 's' : ''}',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SupportedFormats extends StatelessWidget {
  const _SupportedFormats();

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    const sources = [
      ('Bitwarden', 'export JSON non chiffré'),
      ('KeePass / KeePassXC', 'XML ou CSV'),
      ('Chrome, Edge, Firefox, Safari', 'CSV'),
      ('LastPass, 1Password, Dashlane', 'CSV'),
      ('PassVault', 'sauvegarde chiffrée ou export v1'),
    ];

    return HairlineCard(
      sunken: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel('Formats reconnus'),
          for (final (name, format) in sources)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: Row(
                children: [
                  Icon(Icons.check_rounded, size: 14, color: c.success),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: text.bodySmall,
                        children: [
                          TextSpan(
                            text: name,
                            style: text.bodySmall
                                ?.copyWith(color: c.textPrimary),
                          ),
                          TextSpan(
                            text: ' — $format',
                            style: text.bodySmall
                                ?.copyWith(color: c.textTertiary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: Gap.xs),
          Text(
            'Le format est détecté d’après le contenu, pas d’après l’extension.',
            style: text.bodySmall?.copyWith(color: c.textTertiary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Récapitulatif avant écriture. C'est ici que se joue la confiance : on annonce
/// ce qui va entrer, et surtout ce qui a été laissé de côté.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.parsed,
    this.fileName,
    this.progress,
  });

  final ParsedImport parsed;
  final String? fileName;
  final String? progress;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    final byType = parsed.byType;

    return HairlineCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.primaryWash,
                  borderRadius: Radii.all(Radii.sm),
                ),
                child: Icon(Icons.description_outlined,
                    size: 20, color: c.primary),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(parsed.sourceLabel, style: text.titleMedium),
                    if (fileName != null) ...[
                      const SizedBox(height: Gap.xxs),
                      Text(
                        fileName!,
                        style: text.bodySmall?.copyWith(color: c.textTertiary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.xl),

          Text('${parsed.count} élément${parsed.count > 1 ? 's' : ''} reconnu'
              '${parsed.count > 1 ? 's' : ''}',
              style: text.titleLarge),
          const SizedBox(height: Gap.md),

          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              for (final entry in byType.entries)
                _CountChip(
                  label: entry.key.label,
                  count: entry.value,
                  icon: switch (entry.key) {
                    CipherType.login => Icons.key_rounded,
                    CipherType.card => Icons.credit_card_rounded,
                    CipherType.identity => Icons.badge_outlined,
                    CipherType.secureNote => Icons.sticky_note_2_outlined,
                  },
                ),
              if (parsed.folderNames.isNotEmpty)
                _CountChip(
                  label: 'Dossier',
                  count: parsed.folderNames.length,
                  icon: Icons.folder_outlined,
                ),
            ],
          ),

          if (parsed.hasSkipped) ...[
            const SizedBox(height: Gap.xl),
            _SkippedList(skipped: parsed.skipped),
          ],

          if (progress != null) ...[
            const SizedBox(height: Gap.xl),
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Text(progress!, style: text.bodySmall),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({
    required this.label,
    required this.count,
    required this.icon,
  });

  final String label;
  final int count;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c.textTertiary),
          const SizedBox(width: Gap.sm),
          Text(
            '$count $label${count > 1 ? 's' : ''}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    );
  }
}

/// Les lignes rejetées sont montrées, pas comptées en silence : c'est la
/// différence entre un import raté qu'on peut corriger et une perte de données
/// qu'on découvre des mois plus tard.
class _SkippedList extends StatelessWidget {
  const _SkippedList({required this.skipped});

  final List<String> skipped;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(Gap.md),
      decoration: BoxDecoration(
        color: c.warning.withValues(alpha: 0.1),
        borderRadius: Radii.all(Radii.md),
        border: Border.all(color: c.warning.withValues(alpha: 0.34)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: c.warning),
              const SizedBox(width: Gap.sm),
              Text(
                '${skipped.length} ligne${skipped.length > 1 ? 's' : ''} non '
                'importée${skipped.length > 1 ? 's' : ''}',
                style: text.titleMedium?.copyWith(color: c.warning),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          for (final reason in skipped.take(8))
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.xs),
              child: Text(
                '• $reason',
                style: text.bodySmall?.copyWith(fontSize: 12),
              ),
            ),
          if (skipped.length > 8)
            Text(
              '… et ${skipped.length - 8} autre${skipped.length - 8 > 1 ? 's' : ''}',
              style: text.bodySmall?.copyWith(color: c.textTertiary, fontSize: 12),
            ),
        ],
      ),
    );
  }
}

class _SuccessCard extends StatelessWidget {
  const _SuccessCard({required this.count, required this.onDone});

  final int count;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    return Column(
      children: [
        const SizedBox(height: Gap.xxl),
        Container(
          width: 68,
          height: 68,
          decoration: BoxDecoration(
            color: c.success.withValues(alpha: 0.16),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.check_rounded, size: 32, color: c.success),
        ),
        const SizedBox(height: Gap.xl),
        Text(
          '$count élément${count > 1 ? 's' : ''} importé${count > 1 ? 's' : ''}',
          style: text.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Gap.sm),
        Text(
          'Chaque entrée a été chiffrée sur cet appareil avant d’être envoyée. '
          'Pensez à supprimer le fichier source, qui est en clair.',
          style: text.bodyMedium?.copyWith(color: c.textTertiary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Gap.xxl),
        FilledButton(onPressed: onDone, child: const Text('Retour au coffre')),
      ],
    );
  }
}
