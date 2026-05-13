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
  bool _bioAvailable = false;
  bool _bioEnrolled = false;
  String _bioStatusMessage = '';

  @override
  void initState() {
    super.initState();
    _initBiometrics();
  }

  Future<void> _initBiometrics() async {
    try {
      _bioAvailable = await _localAuth.isDeviceSupported();

      if (_bioAvailable) {
        try {
          _bioEnrolled = await _localAuth.canCheckBiometrics;
        } catch (e) {
          debugPrint('canCheckBiometrics error: $e');
          _bioEnrolled = false;
        }

        if (!_bioEnrolled) {
          _bioStatusMessage = '✅ Capteur disponible — '
              'Ajoutez une empreinte dans Paramètres > Sécurité > Empreinte';
        }
      } else {
        _bioStatusMessage = 'ℹ️ Ce téléphone ne supporte pas la biométrie';
      }
    } catch (e) {
      debugPrint('Biometric init error: $e');
      _bioAvailable = false;
      _bioEnrolled = false;
    }

    // Tentative biométrique si capteur dispo
    if (_bioAvailable && mounted) {
      await _tryBiometricLogin();
    } else {
      if (mounted) setState(() => _checkingBio = false);
    }
  }

  /// Connexion par empreinte : vérifie le vrai mot de passe maître à chaque fois
  Future<void> _tryBiometricLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final bioEnabled = prefs.getBool('biometric_enabled') ?? false;
      final savedPassword = prefs.getString('biometric_password');

      if (bioEnabled && savedPassword != null && savedPassword.isNotEmpty) {
        // 1. Demander l'empreinte
        final authenticated = await _localAuth.authenticate(
          localizedReason: 'Déverrouillez Mes mot de passe',
          biometricOnly: false,
          persistAcrossBackgrounding: true,
        );

        if (authenticated && mounted) {
          // 2. Empreinte OK → on se connecte avec le vrai mot de passe maître
          final loginSuccess = await _api.login(savedPassword);

          if (loginSuccess && mounted) {
            // 3. Mot de passe valide → on entre
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => HomeScreen(api: _api),
              ),
            );
            return;
          } else if (mounted) {
            // 4. Mot de passe invalide → demander reconnexion
            setState(() => _checkingBio = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('🔑 Mot de passe maître modifié, reconnectez-vous'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        } else if (mounted) {
          debugPrint('Biometric login cancelled');
        }
      }
    } catch (e) {
      debugPrint('Biometric login error: $e');
      if (mounted && !e.toString().contains('userCanceled')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ $e'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }

    if (mounted) setState(() => _checkingBio = false);
  }

  Future<void> _login() async {
    if (_passwordController.text.isEmpty) return;

    setState(() => _loading = true);

    final success = await _api.login(_passwordController.text);

    if (!mounted) return;

    if (success) {
      final prefs = await SharedPreferences.getInstance();
      final alreadyEnabled = prefs.getBool('biometric_enabled') ?? false;
      final savedPassword = prefs.getString('biometric_password');

      // Sauvegarder le mot de passe pour l'empreinte
      // (remplace l'ancien mot de passe si changé)
      if (_api.token != null) {
        await prefs.setString('biometric_password', _passwordController.text);
      }

      // Proposer d'activer la biométrie (si pas déjà activé)
      if (_bioAvailable && !alreadyEnabled && mounted && _bioEnrolled) {
        final enableBio = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('🔐 Déverrouillage rapide'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Activer l\'empreinte digitale pour déverrouiller '
                  'l\'appli plus rapidement ?',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Votre mot de passe sera sauvegardé pour '
                  'vous connecter automatiquement.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
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
          try {
            final enrolled = await _localAuth.authenticate(
              localizedReason:
                  'Enregistrez votre empreinte pour le déverrouillage rapide',
              biometricOnly: false,
              persistAcrossBackgrounding: true,
            );

            if (enrolled && mounted) {
              await prefs.setBool('biometric_enabled', true);
              await prefs.setString('biometric_password', _passwordController.text);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ Empreinte enregistrée !'),
                  backgroundColor: Colors.green,
                ),
              );
            } else if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('❌ Activation annulée'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          } catch (e) {
            debugPrint('Biometric enroll error: $e');
            if (mounted && !e.toString().contains('userCanceled')) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('⚠️ $e'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 5),
                ),
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
      final shouldSetup = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Compte introuvable'),
          content: const Text(
            'Aucun mot de passe maître trouvé. '
            'Voulez-vous créer un nouveau compte ?',
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
              if (_bioStatusMessage.isNotEmpty && !_checkingBio) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _bioAvailable
                        ? Colors.blue.withOpacity(0.1)
                        : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _bioAvailable ? Icons.fingerprint : Icons.info_outline,
                        size: 18,
                        color: _bioAvailable ? Colors.blue : Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _bioStatusMessage,
                          style: TextStyle(
                            fontSize: 12,
                            color: _bioAvailable
                                ? Colors.blue[300]
                                : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
                      icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () =>
                          setState(() => _obscure = !_obscure),
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
