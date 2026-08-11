import 'package:flutter/material.dart';
import 'package:flutter_autofill_service/flutter_autofill_service.dart';

import '../../core/design/app_theme.dart';
import '../../core/design/tokens.dart';
import '../../widgets/common.dart';

/// Réglage d'activation du remplissage automatique.
///
/// L'app ne peut pas s'auto-désigner comme service de remplissage : c'est Android
/// qui décide, via un écran système. Le bouton ne fait donc qu'ouvrir cet écran,
/// et l'état réel est relu au retour au premier plan — sinon l'interrupteur
/// afficherait « activé » alors que l'utilisateur a annulé la demande.
class AutofillSettingCard extends StatefulWidget {
  const AutofillSettingCard({super.key});

  @override
  State<AutofillSettingCard> createState() => _AutofillSettingCardState();
}

class _AutofillSettingCardState extends State<AutofillSettingCard>
    with WidgetsBindingObserver {
  final _service = AutofillService();

  AutofillServiceStatus? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Au retour de l'écran système, on relit l'état réel plutôt que de supposer
    // que la demande a abouti.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final status = await _service.status;
      if (mounted) setState(() => _status = status);
    } on Exception {
      if (mounted) setState(() => _status = AutofillServiceStatus.unsupported);
    }
  }

  Future<void> _request() async {
    setState(() => _busy = true);
    try {
      await _service.requestSetAutofillService();
    } on Exception {
      if (mounted) {
        AppFeedback.failure(context, 'Android a refusé d’ouvrir ce réglage');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  Future<void> _disable() async {
    setState(() => _busy = true);
    try {
      await _service.disableAutofillServices();
    } on Exception {
      // Rien à rattraper : le rafraîchissement dira l'état réel.
    } finally {
      if (mounted) setState(() => _busy = false);
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    final status = _status;

    if (status == null) {
      return HairlineCard(
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: Gap.md),
            Text('Vérification du remplissage automatique…',
                style: text.bodySmall),
          ],
        ),
      );
    }

    if (status == AutofillServiceStatus.unsupported) {
      return HairlineCard(
        sunken: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.block_rounded, size: 18, color: c.textTertiary),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Text(
                'Cet appareil ne propose pas de remplissage automatique '
                'système.',
                style: text.bodySmall?.copyWith(color: c.textTertiary),
              ),
            ),
          ],
        ),
      );
    }

    final enabled = status == AutofillServiceStatus.enabled;

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
                  color: (enabled ? c.success : c.textTertiary)
                      .withValues(alpha: 0.16),
                  borderRadius: Radii.all(Radii.sm),
                ),
                child: Icon(
                  Icons.keyboard_rounded,
                  size: 20,
                  color: enabled ? c.success : c.textTertiary,
                ),
              ),
              const SizedBox(width: Gap.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      enabled
                          ? 'PassVault remplit vos identifiants'
                          : 'Remplissage automatique inactif',
                      style: text.titleMedium,
                    ),
                    const SizedBox(height: Gap.xxs),
                    Text(
                      enabled
                          ? 'Android proposera vos identifiants dans les autres '
                              'applications et dans le navigateur.'
                          : 'À activer depuis les réglages Android : c’est le '
                              'système qui choisit le service de remplissage.',
                      style: text.bodySmall?.copyWith(color: c.textTertiary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.lg),
          if (enabled)
            OutlinedButton.icon(
              onPressed: _busy ? null : _disable,
              icon: const Icon(Icons.link_off_rounded, size: 18),
              label: const Text('Désactiver'),
            )
          else
            FilledButton.icon(
              onPressed: _busy ? null : _request,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('Ouvrir les réglages Android'),
            ),
          const SizedBox(height: Gap.md),
          Text(
            'Le coffre reste verrouillé : chaque remplissage demande la '
            'biométrie ou le mot de passe maître, et seules les entrées dont '
            'une adresse correspond au demandeur sont proposées.',
            style: text.bodySmall?.copyWith(color: c.textTertiary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
