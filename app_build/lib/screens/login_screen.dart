import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../services/api_service.dart';
import 'home_screen.dart';
import 'setup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _api = ApiService();
  final _localAuth = LocalAuthentication();
  final _passwordController = TextEditingController();
  final _focusNode = FocusNode();
  bool _loading = false;
  bool _obscure = true;
  bool _checkingBio = true;
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
    _tryBiometricLogin();
  }

  Future<void> _tryBiometricLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bioEnabled = prefs.getBool('biometric_enabled') ?? false;
      final savedToken = prefs.getString('biometric_token');

      if (bioEnabled && savedToken != null) {
        final canBio = await _localAuth.canCheckBiometrics;
        if (canBio && mounted) {
          final authenticated = await _localAuth.authenticate(
            localizedReason: 'Déverrouillez PassVault',
          );

          if (authenticated && mounted) {
            _api.setToken(savedToken);
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => HomeScreen(api: _api)),
            );
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Biometric login error: $e');
    }
    if (mounted) setState(() => _checkingBio = false);
  }

  Future<void> _login() async {
    if (_passwordController.text.isEmpty) return;
    setState(() => _loading = true);

    final success = await _api.login(_passwordController.text);
    if (!mounted) return;

    if (success) {
      // Proposer biométrie
      final canBio = await _localAuth.canCheckBiometrics;
      if (canBio && mounted) {
        final enableBio = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: PassVaultApp.brandSlate,
            title: const Text('🔐 Déverrouillage rapide'),
            content: const Text(
              'Activer l\'empreinte digitale pour déverrouiller PassVault plus rapidement ?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Non merci'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Activer'),
              ),
            ],
          ),
        );

        if (enableBio == true && mounted) {
          final enrolled = await _localAuth.authenticate(
            localizedReason:
                'Enregistrez votre empreinte pour le déverrouillage rapide',
          );
          if (enrolled && mounted) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('biometric_enabled', true);
            if (_api.token != null) {
              await prefs.setString('biometric_token', _api.token!);
            }
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ Empreinte enregistrée !'),
                  backgroundColor: PassVaultApp.brandGreen,
                ),
              );
            }
          }
        }
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => HomeScreen(api: _api)),
        );
      }
    } else {
      final shouldSetup = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: PassVaultApp.brandSlate,
          title: const Text('Coffre-fort introuvable'),
          content: const Text(
            'Aucun coffre-fort trouvé. Voulez-vous en créer un nouveau ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Créer'),
            ),
          ],
        ),
      );

      if (shouldSetup == true && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => SetupScreen(api: _api)),
        );
      }
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          color: PassVaultApp.deepNavy,
        ),
        child: Stack(
          children: [
            // ── Décoratif blurs en arrière-plan ──
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

            // ── Contenu principal ──
            SafeArea(
              child: Center(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // ── Logo Shield ──
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: PassVaultApp.brandGreen.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.shield_rounded,
                            size: 48,
                            color: PassVaultApp.brandGreen,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── Titre ──
                        Text(
                          'PassVault',
                          style: Theme.of(context)
                              .textTheme
                              .headlineLarge
                              ?.copyWith(fontSize: 32),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Vos mots de passe chiffrés & synchronisés',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: PassVaultApp.brandGrey,
                              ),
                        ),
                        const SizedBox(height: 48),

                        // ── Champ mot de passe maître ──
                        if (_checkingBio)
                          const Column(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: PassVaultApp.brandGrey,
                                ),
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Déverrouillage biométrique...',
                                style: TextStyle(
                                  color: PassVaultApp.brandGrey,
                                ),
                              ),
                            ],
                          )
                        else ...[
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Label
                              const Padding(
                                padding: EdgeInsets.only(left: 4, bottom: 8),
                                child: Text(
                                  'MOT DE PASSE MAÎTRE',
                                  style: TextStyle(
                                    fontFamily: 'JetBrains Mono',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    letterSpacing: 0.5,
                                    color: PassVaultApp.brandGrey,
                                  ),
                                ),
                              ),
                              // Input
                              TextField(
                                controller: _passwordController,
                                focusNode: _focusNode,
                                obscureText: _obscure,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                                decoration: InputDecoration(
                                  hintText: '••••••••••••',
                                  prefixIcon: const Icon(
                                    Icons.lock_outline,
                                    color: PassVaultApp.brandGrey,
                                    size: 20,
                                  ),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      color: PassVaultApp.brandGrey,
                                      size: 20,
                                    ),
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                  ),
                                  filled: true,
                                  fillColor: PassVaultApp.brandSlate,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: BorderSide(
                                      color: _focusNode.hasFocus
                                          ? PassVaultApp.electricBlue
                                          : PassVaultApp.brandBorder,
                                      width: _focusNode.hasFocus ? 2 : 1,
                                    ),
                                  ),
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 16),
                                ),
                                onSubmitted: (_) => _login(),
                                onChanged: (_) => setState(() {}),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // ── Bouton Déverrouiller ──
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: FilledButton.icon(
                              onPressed:
                                  _loading || _passwordController.text.isEmpty
                                      ? null
                                      : _login,
                              icon: _loading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.lock_open_rounded),
                              label: Text(_loading ? 'Vérification...' : 'Déverrouiller'),
                              style: FilledButton.styleFrom(
                                backgroundColor: PassVaultApp.electricBlue,
                                disabledBackgroundColor:
                                    PassVaultApp.electricBlue.withValues(alpha: 0.4),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // ── Biométrie ──
                          _buildBiometricButton(),
                          const SizedBox(height: 24),

                          // ── Liens bas de page ──
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              TextButton(
                                onPressed: () {
                                  // TODO: réinitialisation à implémenter
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                          'Contactez l\'administrateur pour réinitialiser'),
                                    ),
                                  );
                                },
                                child: Text(
                                  'Mot de passe oublié ?',
                                  style: TextStyle(
                                    color: PassVaultApp.electricBlue
                                        .withValues(alpha: 0.7),
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            SetupScreen(api: _api)),
                                  );
                                },
                                child: const Text('Créer un vault'),
                              ),
                            ],
                          ),
                        ],
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

  Widget _buildBiometricButton() {
    return FutureBuilder<bool>(
      future: _localAuth.canCheckBiometrics,
      builder: (ctx, snapshot) {
        final canBio = snapshot.data ?? false;
        if (!canBio) return const SizedBox.shrink();

        return GestureDetector(
          onTap: _tryBiometricLogin,
          child: Column(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: PassVaultApp.brandBorder,
                    width: 1,
                  ),
                ),
                child: const Icon(
                  Icons.fingerprint,
                  color: PassVaultApp.brandGrey,
                  size: 28,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Déverrouillage biométrique',
                style: TextStyle(
                  color: PassVaultApp.brandGrey.withValues(alpha: 0.7),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _focusNode.dispose();
    _animController.dispose();
    super.dispose();
  }
}
