import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AddPasswordScreen extends StatefulWidget {
  final ApiService api;

  // Optionnel : si fourni, on est en mode édition
  final Map<String, dynamic>? existingPassword;

  const AddPasswordScreen({
    super.key,
    required this.api,
    this.existingPassword,
  });

  @override
  State<AddPasswordScreen> createState() => _AddPasswordScreenState();
}

class _AddPasswordScreenState extends State<AddPasswordScreen> {
  final _siteController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _noteController = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  bool get _isEditing => widget.existingPassword != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final p = widget.existingPassword!;
      _siteController.text = p['site'] ?? '';
      _emailController.text = p['email'] ?? '';
      _passwordController.text = p['password'] ?? '';
      _noteController.text = p['note'] ?? '';
    } else {
      _generatePassword();
    }
  }

  Future<void> _generatePassword() async {
    final pwd = await widget.api.generatePassword();
    _passwordController.text = pwd;
    setState(() {});
  }

  Future<void> _save() async {
    if (_siteController.text.isEmpty || _emailController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Site et email requis')),
      );
      return;
    }

    setState(() => _loading = true);

    bool success;
    if (_isEditing) {
      success = await widget.api.updatePassword(
        id: widget.existingPassword!['id'],
        site: _siteController.text,
        email: _emailController.text,
        password: _passwordController.text,
        note: _noteController.text,
      );
    } else {
      success = await widget.api.addPassword(
        site: _siteController.text,
        email: _emailController.text,
        password: _passwordController.text,
        note: _noteController.text,
      );
    }

    if (!mounted) return;

    if (success) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur lors de la sauvegarde')),
      );
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Modifier' : 'Ajouter un mot de passe'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: _siteController,
              decoration: const InputDecoration(
                labelText: 'Site ou application',
                hintText: 'ex: google.com, github.com',
                prefixIcon: Icon(Icons.language),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email ou identifiant',
                prefixIcon: Icon(Icons.email),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _generatePassword,
                      tooltip: 'Générer',
                    ),
                    IconButton(
                      icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ],
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Note (optionnelle)',
                prefixIcon: Icon(Icons.note),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _loading ? null : _save,
                icon: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(_isEditing ? Icons.edit : Icons.save),
                label: Text(
                  _loading
                      ? 'Sauvegarde...'
                      : (_isEditing ? 'Enregistrer les modifications' : 'Sauvegarder'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _siteController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _noteController.dispose();
    super.dispose();
  }
}
