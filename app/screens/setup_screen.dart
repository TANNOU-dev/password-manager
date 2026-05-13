import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'home_screen.dart';

class SetupScreen extends StatefulWidget {
  final ApiService api;
  const SetupScreen({super.key, required this.api});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _controller = TextEditingController();
  final _confirmController = TextEditingController();
  bool _loading = false;

  Future<void> _create() async {
    if (_controller.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimum 6 caractères')),
      );
      return;
    }
    if (_controller.text != _confirmController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Les mots de passe ne correspondent pas')),
      );
      return;
    }

    setState(() => _loading = true);
    final success = await widget.api.setup(_controller.text);
    if (!mounted) return;

    if (success) {
      // Connecte automatiquement
      await widget.api.login(_controller.text);
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
    return Scaffold(
      appBar: AppBar(title: const Text('Créer un compte')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.shield_outlined, size: 64, color: Colors.green),
              const SizedBox(height: 16),
              Text(
                'Choisissez un mot de passe maître',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'C\'est le seul mot de passe à retenir',
                style: TextStyle(color: Colors.grey[500]),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Mot de passe maître',
                  prefixIcon: Icon(Icons.key),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirmer le mot de passe',
                  prefixIcon: Icon(Icons.key),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _loading ? null : _create,
                  child: _loading
                      ? const CircularProgressIndicator(strokeWidth: 2)
                      : const Text('Créer mon coffre-fort'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _confirmController.dispose();
    super.dispose();
  }
}
