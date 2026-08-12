import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/app_theme.dart';
import '../../core/design/tokens.dart';
import '../../data/api/api_client.dart';
import '../../data/breach/hibp_service.dart';
import '../../data/models/cipher.dart';
import '../../data/vault_repository.dart';
import '../../widgets/common.dart';
import '../../widgets/vault_item_tile.dart';
import '../vault/item_detail_screen.dart';
import 'vault_health.dart';

/// Rapport de santé du coffre.
///
/// Faiblesse, réutilisation, ancienneté : tout est calculé localement sur le
/// coffre déchiffré. Le serveur ne pourrait pas produire ce rapport, il ne voit
/// que des blobs.
///
/// La confrontation aux fuites connues est le seul volet qui sort de l'appareil.
/// Elle est donc **déclenchée à la main**, jamais automatiquement : c'est à
/// l'utilisateur de décider s'il accepte cet appel réseau. Voir `HibpService`
/// pour ce qui transite réellement.
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  final _hibp = HibpService();

  /// Résultat de la dernière confrontation aux fuites. `null` = jamais lancée,
  /// ce qui n'est pas la même chose que « aucune fuite ».
  Map<String, int>? _breachCounts;
  bool _checking = false;
  String? _checkError;
  String? _checkProgress;

  @override
  void dispose() {
    _hibp.close();
    super.dispose();
  }

  Future<void> _checkBreaches() async {
    final passwords = context
        .read<VaultRepository>()
        .items
        .map((i) => i.data)
        .whereType<LoginData>()
        .map((d) => d.password)
        .where((p) => p.isNotEmpty);

    setState(() {
      _checking = true;
      _checkError = null;
      _checkProgress = null;
    });

    try {
      final counts = await _hibp.countForAll(
        passwords,
        onProgress: (done, total) {
          if (mounted) {
            setState(() => _checkProgress = '$done / $total vérifiés');
          }
        },
      );
      if (mounted) setState(() => _breachCounts = counts);
    } on HibpFailure catch (e) {
      // On n'installe pas un résultat partiel : un coffre à moitié vérifié
      // affiché comme vérifié est pire que pas de vérification.
      if (mounted) setState(() => _checkError = e.message);
    } finally {
      if (mounted) {
        setState(() {
          _checking = false;
          _checkProgress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    final repo = context.watch<VaultRepository>();
    final report = VaultHealth.analyse(
      repo.items,
      breachCounts: _breachCounts,
    );

    return Scaffold(
      backgroundColor: c.background,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.xl, Gap.xl, 120),
        children: [
          Text('Sécurité', style: text.headlineMedium),
          const SizedBox(height: Gap.xxs),
          Text(
            'Analyse faite sur cet appareil, sur le coffre déchiffré.',
            style: text.bodySmall?.copyWith(color: c.textTertiary),
          ),
          const SizedBox(height: Gap.xxl),

          _ScoreCard(report: report),

          const SizedBox(height: Gap.lg),
          _BreachCheckCard(
            checked: _breachCounts != null,
            checking: _checking,
            progress: _checkProgress,
            error: _checkError,
            exposedCount: report.countOf(HealthIssue.breached),
            onCheck: _checking ? null : _checkBreaches,
          ),

          const SizedBox(height: Gap.lg),
          const _DuplicateCard(),

          if (report.totalAnalysed == 0) ...[
            const SizedBox(height: Gap.giant),
            const EmptyState(
              icon: Icons.health_and_safety_outlined,
              title: 'Rien à analyser',
              message: 'Ajoutez des identifiants : l’analyse porte sur les mots '
                  'de passe, pas sur les notes ou les cartes.',
            ),
          ] else ...[
            const SizedBox(height: Gap.xxl),
            for (final issue in HealthIssue.values)
              _IssueSection(issue: issue, report: report),
          ],
        ],
      ),
    );
  }
}

/// Doublons stricts déjà présents dans le coffre.
///
/// La déduplication à l'import empêche d'en créer de nouveaux ; elle ne dit
/// rien de ce qui était là avant. Un coffre qui a reçu deux fois le même
/// fichier a besoin qu'on vienne le nettoyer.
///
/// Le critère est le même qu'à l'import : contenu identique de bout en bout.
/// Deux comptes qui ne diffèrent que par leur mot de passe ne sont pas des
/// doublons — c'est le même compte à deux époques, et fondre les deux perdrait
/// le mot de passe à jour.
class _DuplicateCard extends StatefulWidget {
  const _DuplicateCard();

  @override
  State<_DuplicateCard> createState() => _DuplicateCardState();
}

class _DuplicateCardState extends State<_DuplicateCard> {
  bool _busy = false;
  String? _progress;
  String? _error;
  int? _trashed;

  Future<void> _clean(int expected) async {
    final repo = context.read<VaultRepository>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Retirer $expected exemplaire'
            '${expected > 1 ? 's' : ''} en trop ?'),
        content: const Text(
          'Un exemplaire de chaque est conservé. Les autres partent à la '
          'corbeille, d’où vous pourrez les restaurer si besoin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Mettre à la corbeille'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
      _trashed = null;
    });

    try {
      final count = await repo.trashDuplicates(
        onProgress: (done, total) {
          if (mounted) setState(() => _progress = '$done / $total');
        },
      );
      if (mounted) setState(() => _trashed = count);
    } on ApiFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      // Le coffre verrouillé lève un StateError, pas une ApiFailure.
      if (mounted) setState(() => _error = 'Nettoyage interrompu : $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    final repo = context.watch<VaultRepository>();
    final count = repo.duplicateCount;

    if (count == 0) {
      // Toujours affichée, même sans rien à signaler.
      //
      // La masquer était une erreur : une fonction invisible quand elle ne
      // trouve rien est indiscernable d'une fonction absente. L'utilisateur ne
      // peut alors pas savoir si le coffre est propre ou si la vérification n'a
      // jamais eu lieu — et c'est précisément ce doute qu'un écran de sécurité
      // doit lever.
      return HairlineCard(
        child: Row(
          children: [
            Icon(Icons.check_circle_outline_rounded, size: 18, color: c.success),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(
                _trashed == null
                    ? 'Aucun doublon : chaque entrée du coffre est unique.'
                    : '$_trashed exemplaire${_trashed! > 1 ? 's' : ''} mis à la '
                        'corbeille. Plus aucun doublon.',
                style: text.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }

    return HairlineCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.copy_all_outlined, size: 18, color: c.warning),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Text(
                  '$count entrée${count > 1 ? 's' : ''} en double',
                  style: text.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Text(
            'Ces entrées répètent exactement une autre du coffre — mêmes '
            'champs du début à la fin. Un coffre qui a reçu deux fois le même '
            'fichier d’import se retrouve dans cet état.',
            style: text.bodySmall?.copyWith(color: c.textSecondary),
          ),
          if (_error != null) ...[
            const SizedBox(height: Gap.md),
            InlineError(message: _error!),
          ],
          const SizedBox(height: Gap.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : () => _clean(count),
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cleaning_services_outlined, size: 18),
              label: Text(_busy
                  ? 'Nettoyage… ${_progress ?? ""}'
                  : 'Retirer les doublons'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Confrontation aux fuites connues.
///
/// Elle expose son fonctionnement avant d'être lancée, parce qu'elle est la
/// seule fonction de l'app à contacter un tiers. Un bouton « Vérifier » sans
/// explication demanderait une confiance qu'on n'a pas à demander.
class _BreachCheckCard extends StatelessWidget {
  const _BreachCheckCard({
    required this.checked,
    required this.checking,
    required this.exposedCount,
    required this.onCheck,
    this.progress,
    this.error,
  });

  final bool checked;
  final bool checking;
  final int exposedCount;
  final VoidCallback? onCheck;
  final String? progress;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;

    final (tint, icon, title) = switch ((checked, exposedCount)) {
      (true, 0) => (
          c.success,
          Icons.verified_user_outlined,
          'Aucun mot de passe dans les fuites connues',
        ),
      (true, _) => (
          c.danger,
          Icons.report_gmailerrorred_rounded,
          '$exposedCount mot${exposedCount > 1 ? 's' : ''} de passe exposé'
              '${exposedCount > 1 ? 's' : ''}',
        ),
      _ => (
          c.accent,
          Icons.cloud_outlined,
          'Vérifier les fuites de données',
        ),
    };

    return HairlineCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.16),
                  borderRadius: Radii.all(Radii.sm),
                ),
                child: Icon(icon, size: 20, color: tint),
              ),
              const SizedBox(width: Gap.md),
              Expanded(child: Text(title, style: text.titleMedium)),
            ],
          ),
          const SizedBox(height: Gap.md),
          Text(
            checked
                ? 'Comparaison faite avec la base Have I Been Pwned. Un mot de '
                    'passe absent n’est pas garanti sûr : il n’est simplement '
                    'pas dans les fuites répertoriées.'
                : 'Coffort n’envoie que les 5 premiers caractères de '
                    'l’empreinte SHA-1 de chaque mot de passe. Le service '
                    'renvoie environ 800 empreintes commençant pareil, et la '
                    'comparaison se fait ici. Ni le mot de passe ni son '
                    'empreinte complète ne quittent l’appareil.',
            style: text.bodySmall?.copyWith(color: c.textTertiary),
          ),
          if (progress != null) ...[
            const SizedBox(height: Gap.md),
            Row(
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: Gap.md),
                Text(progress!, style: text.bodySmall),
              ],
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: Gap.md),
            InlineError(message: error!),
          ],
          const SizedBox(height: Gap.lg),
          OutlinedButton.icon(
            onPressed: onCheck,
            icon: checking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.travel_explore_rounded, size: 18),
            label: Text(
              checking
                  ? 'Vérification…'
                  : (checked ? 'Vérifier à nouveau' : 'Lancer la vérification'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.report});

  final VaultHealthReport report;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    final score = report.score;

    final tint = switch (score) {
      >= 90 => c.success,
      >= 65 => c.warning,
      _ => c.danger,
    };

    return Container(
      padding: const EdgeInsets.all(Gap.xl),
      decoration: BoxDecoration(
        borderRadius: Radii.all(Radii.lg),
        border: Border.all(color: tint.withValues(alpha: 0.34)),
        gradient: LinearGradient(
          colors: [
            tint.withValues(alpha: 0.12),
            tint.withValues(alpha: 0.03),
          ],
        ),
      ),
      child: Row(
        children: [
          _ScoreRing(score: score, color: tint),
          const SizedBox(width: Gap.xl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  report.isClean
                      ? 'Aucun problème détecté'
                      : '${report.totalProblems} élément'
                          '${report.totalProblems > 1 ? 's' : ''} à revoir',
                  style: text.titleLarge,
                ),
                const SizedBox(height: Gap.xs),
                Text(
                  report.isClean
                      ? '${report.totalAnalysed} mot'
                          '${report.totalAnalysed > 1 ? 's' : ''} de passe '
                          'analysé${report.totalAnalysed > 1 ? 's' : ''}.'
                      : report.summaryLine,
                  style: text.bodySmall?.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScoreRing extends StatelessWidget {
  const _ScoreRing({required this.score, required this.color});

  final int score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    return SizedBox(
      width: 74,
      height: 74,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: score / 100),
            duration: Motion.slow,
            curve: Motion.enter,
            builder: (context, value, _) => SizedBox(
              width: 74,
              height: 74,
              child: CircularProgressIndicator(
                value: value,
                strokeWidth: 6,
                strokeCap: StrokeCap.round,
                color: color,
                backgroundColor: c.surfaceSunken,
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$score',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: color,
                      fontSize: 22,
                    ),
              ),
              Text(
                '/100',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(fontSize: 9, letterSpacing: 0),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IssueSection extends StatelessWidget {
  const _IssueSection({required this.issue, required this.report});

  final HealthIssue issue;
  final VaultHealthReport report;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    final affected = report.withIssue(issue);
    if (affected.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.giant),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                switch (issue) {
                  HealthIssue.breached => Icons.report_gmailerrorred_rounded,
                  HealthIssue.weak => Icons.lock_open_rounded,
                  HealthIssue.reused => Icons.content_copy_rounded,
                  HealthIssue.old => Icons.history_rounded,
                  HealthIssue.empty => Icons.no_encryption_gmailerrorred_rounded,
                },
                size: 18,
                color: c.danger,
              ),
              const SizedBox(width: Gap.sm),
              Expanded(
                child: Text(
                  '${issue.label} (${affected.length})',
                  style: text.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          Text(
            issue.explanation,
            style: text.bodySmall?.copyWith(color: c.textTertiary),
          ),
          const SizedBox(height: Gap.md),
          for (final health in affected)
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: VaultItemTile(
                item: health.item,
                warning: issue == HealthIssue.reused && health.reuseCount > 1
                    ? 'Utilisé sur ${health.reuseCount} comptes'
                    : null,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ItemDetailScreen(itemId: health.item.id!),
                  ),
                ),
                onCopyPassword: () {
                  final data = health.item.data;
                  if (data is LoginData && data.password.isNotEmpty) {
                    AppFeedback.copyValue(context, data.password, 'Mot de passe');
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}
