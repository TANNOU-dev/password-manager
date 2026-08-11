import 'package:flutter/material.dart';

import '../../core/design/app_theme.dart';
import '../../core/design/tokens.dart';
import '../generator/generator_sheet.dart';
import '../security/security_screen.dart';
import '../settings/settings_screen.dart';
import '../vault/vault_screen.dart';

/// Coquille de l'app déverrouillée.
///
/// `IndexedStack` et non un `PageView` : on veut que l'état de chaque onglet
/// survive au changement d'onglet — la recherche en cours dans le coffre, les
/// réglages du générateur — sans les reconstruire à chaque aller-retour.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _tabs = [
    (label: 'Coffre', icon: Icons.lock_outline_rounded, active: Icons.lock_rounded),
    (
      label: 'Générateur',
      icon: Icons.auto_awesome_outlined,
      active: Icons.auto_awesome_rounded
    ),
    (
      label: 'Sécurité',
      icon: Icons.health_and_safety_outlined,
      active: Icons.health_and_safety_rounded
    ),
    (
      label: 'Réglages',
      icon: Icons.settings_outlined,
      active: Icons.settings_rounded
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.palette;

    return Scaffold(
      backgroundColor: c.background,
      body: IndexedStack(
        index: _index,
        children: const [
          VaultScreen(),
          GeneratorScreen(),
          SecurityScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.hairline)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.sm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  _NavItem(
                    label: _tabs[i].label,
                    icon: _tabs[i].icon,
                    activeIcon: _tabs[i].active,
                    selected: _index == i,
                    onTap: () => setState(() => _index = i),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.palette;
    final text = Theme.of(context).textTheme;
    final color = selected ? c.primary : c.textTertiary;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.all(Radii.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Gap.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Pastille derrière l'icône active : sur fond sombre, un simple
              // changement de teinte se remarque mal.
              AnimatedContainer(
                duration: Motion.fast,
                curve: Motion.standard,
                padding: const EdgeInsets.symmetric(
                  horizontal: Gap.lg,
                  vertical: Gap.xs,
                ),
                decoration: BoxDecoration(
                  color: selected ? c.primaryWash : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(selected ? activeIcon : icon, size: 21, color: color),
              ),
              const SizedBox(height: Gap.xxs),
              Text(
                label,
                style: text.labelMedium?.copyWith(color: color, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
