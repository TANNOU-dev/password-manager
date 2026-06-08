import 'package:flutter/material.dart';
import '../main.dart';
import '../services/api_service.dart';
import 'home_screen.dart';

class SetupScreen extends StatefulWidget {
  final ApiService api;
  const SetupScreen({super.key, required this.api});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _confirmController = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  late AnimationController _animController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _animController.forward();
  }

  int _passwordStrength(String password) {
    int score = 0;
    if (password.length >= 8) score++;
    if (password.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(password)) score++;
    if (RegExp(r'[a-z]').hasMatch(password)) score++;
    if (RegExp(r'[0-9]').hasMatch(password)) score++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) score++;
    return score.clamp(0, 4);
  }

  String _strengthLabel(int score) {
    switch (score) {
      case 0:
        return 'Très faible';
      case 1:
        return 'Faible';
      case 2:
        return 'Moyen';
      case 3:
        return 'Bon';
      case 4:
        return 'Fort';
      default:
        return 'Très faible';
    }
  }

  Color _strengthColor(int score) {
    switch (score) {
      case 0:
        return const Color(0xFF93000A);
      case 1:
        return const Color(0xFFB3261E);
      case 2:
        return const Color(0xFFE8A317);
      case 3:
        return const Color(0xFF34A853);
      case 4:
        return const Color(0xFF34A853);
      default:
        return const Color(0xFF93000A);
    }
  }

  Future<void> _create() async {
    final password = _controller.text;
    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Minimum 6 caractères requis'),
          backgroundColor: PassVaultApp.errorContainer,
        ),
      );
      return;
    }
    if (password != _confirmController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Les mots de passe ne correspondent pas'),
          backgroundColor: PassVaultApp.errorContainer,
        ),
      );
      return;
    }

    setState(() => _loading = true);
    final success = await widget.api.setup(password);
    if (!mounted) return;

    if (success) {
      await widget.api.login(password);
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => HomeScreen(api: widget.api)),
          (route) => false,
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur de connexion au serveur')),
      );
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final strength = _passwordStrength(_controller.text);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(color: PassVaultApp.deepNavy),
        child: Stack(
          children: [
            // Blurs décoratifs
            Positioned(
              top: -96,
              right: -96,
              child: Container(
                width: 256,
                height: 256,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: PassVaultApp.electricBlue.withValues(alpha: 0.1),
                ),
              ),
            ),
            Positioned(
              bottom: -96,
              left: -96,
              child: Container(
                width: 256,
                height: 256,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: PassVaultApp.brandGreen.withValues(alpha: 0.1),
                ),
              ),
            ),

            SafeArea(
              child: Center(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // ── Icône bouclier + logo ──
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color:
                                PassVaultApp.brandGreen.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.shield_rounded,
                            size: 48,
                            color: PassVaultApp.brandGreen,
                          ),
                        ),
                        const SizedBox(height: 24),

                        Text(
                          'Créer votre coffre-fort',
                          style: Theme.of(context)
                              .textTheme
                              .headlineLarge
                              ?.copyWith(fontSize: 28),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Choisissez un mot de passe maître solide',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: PassVaultApp.brandGrey,
                              ),
                        ),
                        const SizedBox(height: 32),

                        // ── Champ MDP maître ──
                        _buildPasswordField(
                          controller: _controller,
                          label: 'MOT DE PASSE MAÎTRE',
                          hint: '••••••••••••',
                          obscure: _obscure,
                          onToggle: () => setState(() => _obscure = !_obscure),
                          showVisibility: true,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 12),

                        // ── Indicateur de force ──
                        if (_controller.text.isNotEmpty) ...[
                          _buildStrengthIndicator(strength),
                          const SizedBox(height: 16),
                        ],

                        // ── Confirmation ──
                        _buildPasswordField(
                          controller: _confirmController,
                          label: 'CONFIRMER LE MOT DE PASSE',
                          hint: '••••••••••••',
                          obscure: _obscure,
                          showVisibility: false,
                        ),
                        const SizedBox(height: 20),

                        // ── Message sécurité ──
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: PassVaultApp.brandSlate.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: PassVaultApp.brandBorder
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.info_outline,
                                color: PassVaultApp.electricBlue
                                    .withValues(alpha: 0.7),
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Ce mot de passe est la clé unique de votre coffre. '
                                  'S\'il est perdu, PassVault ne pourra pas récupérer vos données.',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: PassVaultApp.brandGrey
                                        .withValues(alpha: 0.8),
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── Bouton Créer ──
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: FilledButton.icon(
                            onPressed: _loading ? null : _create,
                            icon: _loading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.arrow_forward),
                            label: Text(
                                _loading ? 'Création...' : 'Créer mon coffre-fort'),
                            style: FilledButton.styleFrom(
                              backgroundColor: PassVaultApp.brandGreen,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Clé de sécurité physique ──
                        TextButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                    'Clé de sécurité physique bientôt disponible'),
                              ),
                            );
                          },
                          child: const Text(
                            'UTILISER UNE CLÉ DE SÉCURITÉ PHYSIQUE',
                            style: TextStyle(
                              fontFamily: 'JetBrains Mono',
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                              color: PassVaultApp.brandGrey,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool obscure,
    VoidCallback? onToggle,
    bool showVisibility = false,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
              color: PassVaultApp.brandGrey,
            ),
          ),
        ),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
          ),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: const Icon(
              Icons.lock_outline,
              color: PassVaultApp.brandGrey,
              size: 20,
            ),
            suffixIcon: showVisibility
                ? IconButton(
                    icon: Icon(
                      obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: PassVaultApp.brandGrey,
                      size: 20,
                    ),
                    onPressed: onToggle,
                  )
                : null,
            filled: true,
            fillColor: PassVaultApp.brandSlate,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: PassVaultApp.brandBorder),
            ),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 16),
          ),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildStrengthIndicator(int score) {
    final color = _strengthColor(score);
    final label = _strengthLabel(score);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Force : $label',
              style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontStyle: FontStyle.italic,
                fontSize: 12,
                color: PassVaultApp.brandGrey,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: List.generate(4, (i) {
            return Expanded(
              child: Container(
                height: 4,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: i < score
                      ? color
                      : PassVaultApp.brandBorder,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _confirmController.dispose();
    _animController.dispose();
    super.dispose();
  }
}
