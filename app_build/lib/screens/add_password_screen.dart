import 'package:flutter/material.dart';
import '../main.dart';
import '../services/api_service.dart';

class AddPasswordScreen extends StatefulWidget {
  final ApiService api;
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
    }
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

  Future<void> _generatePassword() async {
    final pwd = await widget.api.generatePassword();
    _passwordController.text = pwd;
    setState(() {});
    // Feedback visuel
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🔐 Mot de passe généré !'),
        duration: Duration(seconds: 1),
        backgroundColor: PassVaultApp.brandGreen,
      ),
    );
  }

  Future<void> _save() async {
    if (_siteController.text.isEmpty || _emailController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Site et email requis'),
          backgroundColor: PassVaultApp.errorContainer,
        ),
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
        SnackBar(
          content: const Text('Erreur lors de la sauvegarde'),
          backgroundColor: PassVaultApp.errorContainer,
        ),
      );
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final strength = _passwordStrength(_passwordController.text);
    final strengthColor = _strengthColor(strength);

    return Scaffold(
      backgroundColor: PassVaultApp.deepNavy,
      appBar: AppBar(
        title: Text(_isEditing ? 'Modifier' : 'Ajouter un mot de passe'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Section DÉTAILS DU COMPTE ──
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 16),
              child: Text(
                'DÉTAILS DU COMPTE',
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                  color: PassVaultApp.brandGrey,
                ),
              ),
            ),

            // Site
            _buildLabel('SITE OU APPLICATION'),
            const SizedBox(height: 6),
            _buildInputField(
              controller: _siteController,
              hint: 'ex: google.com, github.com',
              icon: Icons.language,
            ),
            const SizedBox(height: 16),

            // Email
            _buildLabel('E-MAIL OU IDENTIFIANT'),
            const SizedBox(height: 6),
            _buildInputField(
              controller: _emailController,
              hint: 'ex: jean.dupont@gmail.com',
              icon: Icons.email_outlined,
            ),
            const SizedBox(height: 16),

            // Mot de passe
            _buildLabel('MOT DE PASSE'),
            const SizedBox(height: 6),
            Row(
              children: [
                Flexible(
                  flex: 3,
                  child: _buildInputField(
                    controller: _passwordController,
                    hint: '••••••••••••',
                    icon: Icons.lock_outline,
                    obscure: _obscure,
                    suffix: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.refresh,
                              size: 20, color: PassVaultApp.brandGrey),
                          onPressed: _generatePassword,
                          tooltip: 'Générer',
                        ),
                        IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                            color: PassVaultApp.brandGrey,
                          ),
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ],
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  flex: 2,
                  child: OutlinedButton.icon(
                    onPressed: _generatePassword,
                    icon: const Icon(Icons.auto_fix_high, size: 16),
                    label: const Text('Générer'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: PassVaultApp.brandGreen,
                      side: const BorderSide(
                          color: PassVaultApp.brandGreen, width: 1),
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),

            // ── Indicateur de force ──
            if (_passwordController.text.isNotEmpty) ...[
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Force : ${_strengthLabel(strength)}',
                        style: TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                          color: strengthColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: List.generate(4, (i) {
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.only(right: 4),
                          height: 4,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(2),
                            color: i < strength
                                ? strengthColor
                                : PassVaultApp.brandBorder,
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 16),

            // Notes
            _buildLabel('NOTE (OPTIONNELLE)'),
            const SizedBox(height: 6),
            _buildInputField(
              controller: _noteController,
              hint: 'Notes de sécurité, questions secrètes...',
              icon: Icons.note_outlined,
              maxLines: 3,
            ),
            const SizedBox(height: 24),

            // ── Message protection active ──
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: PassVaultApp.brandSlate.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: PassVaultApp.brandBorder.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.shield_rounded,
                    color: PassVaultApp.brandGreen.withValues(alpha: 0.8),
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Protection active : vos mots de passe sont chiffrés de bout en bout (E2E) avant d\'être sauvegardés sur nos serveurs sécurisés.',
                      style: TextStyle(
                        fontSize: 13,
                        color: PassVaultApp.brandGrey,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Bouton Sauvegarder ──
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton.icon(
                onPressed: _loading ? null : _save,
                icon: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(_isEditing ? Icons.edit : Icons.save),
                label: Text(
                  _loading
                      ? 'Sauvegarde...'
                      : (_isEditing ? 'Enregistrer les modifications' : 'Sauvegarder'),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'JetBrains Mono',
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
          color: PassVaultApp.brandGrey,
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: PassVaultApp.brandSlate,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: PassVaultApp.brandBorder),
      ),
      child: Row(
        crossAxisAlignment:
            maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.only(
                left: 16, top: maxLines > 1 ? 14 : 0, bottom: maxLines > 1 ? 0 : 0),
            child: Icon(icon, color: PassVaultApp.brandGrey, size: 20),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              maxLines: maxLines,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                fillColor: Colors.transparent,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 14),
              ),
              onChanged: onChanged,
            ),
          ),
          if (suffix != null) suffix,
        ],
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
