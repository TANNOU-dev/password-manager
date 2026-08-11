import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/design/app_theme.dart';
import '../../core/design/tokens.dart';
import '../../core/utils/password_strength.dart';
import '../../data/export/vault_export.dart';
import '../../data/vault_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/strength_meter.dart';

enum _ExportKind { encrypted, plainJson, csv }

/// Export du coffre.
///
/// La sauvegarde chiffrée est présentée en premier et par défaut. Les deux autres
/// formats produisent un fichier **lisible par n'importe qui** : l'écran le dit
/// sans détour, parce que c'est le geste par lequel un coffre bien chiffré finit
/// en clair dans un dossier Téléchargements.
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  _ExportKind _kind = _ExportKind.encrypted;
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _acknowledgedPlain = false;
  bool _busy = false;
  String? _error;
  PasswordStrength _strength = PasswordStrengthEvaluator.evaluate('');

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(() => setState(() {
          _strength = PasswordStrengthEvaluator.evaluate(_passwordController.text);
        }));
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _canExport {
    if (_busy) return false;
    return switch (_kind) {
      _ExportKind.encrypted => _passwordController.text.length >= 8 &&
          _passwordController.text == _confirmController.text &&
          _strength.level.index >= StrengthLevel.fair.index,
      _ExportKind.plainJson || _ExportKind.csv => _acknowledgedPlain,
    };
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final repo = context.read<VaultRepository>();
      final folderNames = {for (final f in repo.folders) f.id: f.name};
      final items = repo.items;

      final (content, extension) = switch (_kind) {
        _ExportKind.encrypted => (
            await VaultExporter.toEncryptedJson(
              items,
              exportPassword: _passwordController.text,
              folderNames: folderNames,
            ),
            'json',
          ),
        _ExportKind.plainJson => (
            VaultExporter.toBitwardenJson(items, folderNames: folderNames),
            'json',
          ),
        _ExportKind.csv => (
            VaultExporter.toCsv(items, folderNames: folderNames),
            'csv',
          ),
      };

      final stamp = DateTime.now().toIso8601String().split('T').first;
      final suffix = _kind == _ExportKind.encrypted ? 'chiffre' : 'EN-CLAIR';
      final name = 'passvault-$suffix-$stamp.$extension';

      await _deliver(content, name);
      if (!mounted) return;
      AppFeedback.show(
        context,
        _kind == _ExportKind.encrypted
            ? 'Sauvegarde chiffrée créée'
            : 'Export en clair créé — à supprimer après usage',
        icon: Icons.check_rounded,
        tint: _kind == _ExportKind.encrypted ? null : context.palette.warning,
      );
      Navigator.of(context).pop();
    } on ExportException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Export impossible : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Sur mobile et bureau on passe par la feuille de partage du système. Sur le
  /// web il n'y a pas de système de fichiers accessible : on retombe sur le
  /// presse-papiers, en le disant.
  Future<void> _deliver(String content, String fileName) async {
    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: content));
      if (mounted) {
        AppFeedback.show(
          context,
          'Contenu copié dans le presse-papiers (pas de fichier sur le web)',
          icon: Icons.content_copy_outlined,
        );
      }
      return;
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(content);
    // API de share_plus 9.x. La 10 introduit SharePlus.instance ; migrer les
    // deux demanderait de relever aussi file_picker et flutter_secure_storage,
    // ce qui n'a pas sa place dans cette étape.
    await Share.shareXFiles([XFile(file.path)], text: fileName);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    final repo = context.watch<VaultRepository>();
    final count = repo.items.length;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(title: const Text('Exporter le coffre')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.sm, Gap.xl, Gap.giant),
        children: [
          Text(
            '$count élément${count > 1 ? 's' : ''} à exporter.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: Gap.xl),

          const SectionLabel('Format'),
          _KindOption(
            kind: _ExportKind.encrypted,
            selected: _kind,
            onSelected: (k) => setState(() => _kind = k),
            icon: Icons.shield_outlined,
            title: 'Sauvegarde chiffrée',
            subtitle: 'Protégée par une phrase de passe dédiée. À conserver.',
            recommended: true,
          ),
          const SizedBox(height: Gap.sm),
          _KindOption(
            kind: _ExportKind.plainJson,
            selected: _kind,
            onSelected: (k) => setState(() => _kind = k),
            icon: Icons.code_rounded,
            title: 'JSON en clair (format Bitwarden)',
            subtitle: 'Pour migrer vers un autre gestionnaire. Lisible par tous.',
          ),
          const SizedBox(height: Gap.sm),
          _KindOption(
            kind: _ExportKind.csv,
            selected: _kind,
            onSelected: (k) => setState(() => _kind = k),
            icon: Icons.table_chart_outlined,
            title: 'CSV en clair',
            subtitle: 'Le plus universel, le moins fidèle. Lisible par tous.',
          ),

          const SizedBox(height: Gap.xxl),

          if (_kind == _ExportKind.encrypted)
            _EncryptedOptions(
              passwordController: _passwordController,
              confirmController: _confirmController,
              strength: _strength,
              busy: _busy,
              onChanged: () => setState(() {}),
            )
          else
            _PlainWarning(
              isCsv: _kind == _ExportKind.csv,
              acknowledged: _acknowledgedPlain,
              onChanged: (v) => setState(() => _acknowledgedPlain = v),
            ),

          if (_error != null) ...[
            const SizedBox(height: Gap.xl),
            InlineError(message: _error!),
          ],

          const SizedBox(height: Gap.xxl),
          FilledButton.icon(
            onPressed: _canExport ? _run : null,
            style: _kind == _ExportKind.encrypted
                ? null
                : FilledButton.styleFrom(backgroundColor: c.warning),
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    _kind == _ExportKind.encrypted
                        ? Icons.lock_rounded
                        : Icons.lock_open_rounded,
                    size: 20,
                  ),
            label: Text(
              _busy
                  ? 'Préparation…'
                  : (_kind == _ExportKind.encrypted
                      ? 'Créer la sauvegarde'
                      : 'Exporter en clair'),
            ),
          ),
        ],
      ),
    );
  }
}

class _KindOption extends StatelessWidget {
  const _KindOption({
    required this.kind,
    required this.selected,
    required this.onSelected,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.recommended = false,
  });

  final _ExportKind kind;
  final _ExportKind selected;
  final ValueChanged<_ExportKind> onSelected;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool recommended;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    final isSelected = kind == selected;

    return Material(
      color: isSelected ? c.primaryWash : c.surface,
      borderRadius: Radii.all(Radii.lg),
      child: InkWell(
        onTap: () => onSelected(kind),
        borderRadius: Radii.all(Radii.lg),
        child: Container(
          padding: const EdgeInsets.all(Gap.lg),
          decoration: BoxDecoration(
            borderRadius: Radii.all(Radii.lg),
            border: Border.all(
              color: isSelected ? c.primary.withValues(alpha: 0.5) : c.hairline,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 21, color: isSelected ? c.primary : c.textSecondary),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(title, style: text.titleMedium)),
                        if (recommended) ...[
                          const SizedBox(width: Gap.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Gap.sm,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: c.success.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(Radii.xs),
                            ),
                            child: Text(
                              'conseillé',
                              style: text.labelMedium
                                  ?.copyWith(color: c.success, fontSize: 10),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: Gap.xxs),
                    Text(
                      subtitle,
                      style: text.bodySmall?.copyWith(color: c.textTertiary),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle_rounded, size: 20, color: c.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _EncryptedOptions extends StatelessWidget {
  const _EncryptedOptions({
    required this.passwordController,
    required this.confirmController,
    required this.strength,
    required this.busy,
    required this.onChanged,
  });

  final TextEditingController passwordController;
  final TextEditingController confirmController;
  final PasswordStrength strength;
  final bool busy;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    final matches = confirmController.text.isNotEmpty &&
        confirmController.text == passwordController.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Phrase de passe de la sauvegarde'),
        Text(
          'Distincte de votre mot de passe maître, et c’est volontaire : la '
          'sauvegarde doit rester déchiffrable même après un changement de mot '
          'de passe. Si vous la perdez, le fichier est irrécupérable.',
          style: text.bodySmall?.copyWith(color: c.textTertiary),
        ),
        const SizedBox(height: Gap.lg),
        TextField(
          controller: passwordController,
          enabled: !busy,
          obscureText: true,
          autocorrect: false,
          style: SecretText.of(context),
          decoration: const InputDecoration(labelText: 'Phrase de passe'),
        ),
        const SizedBox(height: Gap.md),
        StrengthMeter(strength: strength, showWarnings: false),
        const SizedBox(height: Gap.md),
        TextField(
          controller: confirmController,
          enabled: !busy,
          obscureText: true,
          autocorrect: false,
          style: SecretText.of(context),
          decoration: InputDecoration(
            labelText: 'Confirmer',
            errorText: confirmController.text.isEmpty || matches
                ? null
                : 'Les deux saisies diffèrent',
            suffixIcon:
                matches ? Icon(Icons.check_rounded, size: 20, color: c.success) : null,
          ),
          onChanged: (_) => onChanged(),
        ),
      ],
    );
  }
}

class _PlainWarning extends StatelessWidget {
  const _PlainWarning({
    required this.isCsv,
    required this.acknowledged,
    required this.onChanged,
  });

  final bool isCsv;
  final bool acknowledged;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(Gap.lg),
      decoration: BoxDecoration(
        borderRadius: Radii.all(Radii.lg),
        color: c.warning.withValues(alpha: 0.1),
        border: Border.all(color: c.warning.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_open_rounded, size: 18, color: c.warning),
              const SizedBox(width: Gap.sm),
              Text('Fichier non chiffré', style: text.titleMedium),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Text(
            'Mots de passe, codes TOTP et numéros de carte seront écrits en '
            'clair. Toute application ayant accès au fichier pourra les lire, '
            'et une sauvegarde automatique du téléphone l’emportera avec elle.',
            style: text.bodySmall,
          ),
          if (isCsv) ...[
            const SizedBox(height: Gap.sm),
            Text(
              'Le CSV ne sait représenter que des identifiants : cartes, '
              'identités et champs personnalisés seront aplatis dans la colonne '
              'de notes.',
              style: text.bodySmall?.copyWith(color: c.textTertiary),
            ),
          ],
          const SizedBox(height: Gap.md),
          InkWell(
            onTap: () => onChanged(!acknowledged),
            borderRadius: Radii.all(Radii.sm),
            child: Row(
              children: [
                Checkbox(
                  value: acknowledged,
                  onChanged: (v) => onChanged(v ?? false),
                  side: BorderSide(color: c.hairlineStrong),
                ),
                Expanded(
                  child: Text(
                    'J’ai compris et je supprimerai le fichier après usage.',
                    style: text.bodyMedium?.copyWith(color: c.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
