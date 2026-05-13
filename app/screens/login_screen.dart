import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'home_screen.dart';
import 'setup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _api = ApiService();
  final _localAuth = LocalAuthentication();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  bool _checkingBio = true;

  @override
  void initState() {
    super.initState();
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
            localizedReason: 'Déverrouillez Mes mot de passe',
            options: const AuthenticationOptions(
              stickyAuth: true,
              biometricOnly: true,
            ),
          );

          if (authenticated && mounted) {
            _api.setToken(savedToken);
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => HomeScreen(api: _api),
              ),
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
      // Proposer d'activer la biométrie
      final canBio = await _localAuth.canCheckBiometrics;
      if (canBio && mounted) {
        final enableBio = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('🔐 Déverrouillage rapide'),
            content: const Text(
              'Activer l\'empreinte digitale pour déverrouiller l\'appli plus rapidement ?',
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
          // Enregistrer une empreinte pour confirmer
          final enrolled = await _localAuth.authenticate(
            localizedReason: 'Enregistrez votre empreinte pour le déverrouillage rapide',
            options: const AuthenticationOptions(
              stickyAuth: true,
              biometricOnly: true,
            ),
          );

          if (enrolled && mounted) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('biometric_enabled', true);
            if (_api.token != null) {
              await prefs.setString('biometric_token', _api.token!);
            }
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('✅ Empreinte enregistrée !')),
              );
            }
          }
        }
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => HomeScreen(api: _api),
          ),
        );
      }
    } else {
      // Peut-être que le compte n'existe pas encore → proposer setup
      final shouldSetup = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Compte introuvable'),
          content: const Text(
            'Aucun mot de passe maître trouvé. Voulez-vous créer un nouveau compte ?',
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
          MaterialPageRoute(
            builder: (_) => SetupScreen(api: _api),
          ),
        );
      }
    }

    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 80, color: Colors.blue),
              const SizedBox(height: 16),
              Text(
                'Mes mot de passe',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Mes mot de passe chiffrés et synchronisés',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
              ),
              const SizedBox(height: 40),
              if (_checkingBio)
                const Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Déverrouillage biométrique...'),
                  ],
                )
              else ...[
                TextField(
                  controller: _passwordController,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: 'Mot de passe maître',
                    prefixIcon: const Icon(Icons.key),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _login(),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _loading ? null : _login,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Déverrouiller'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }
}
