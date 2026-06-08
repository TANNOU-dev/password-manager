import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../main.dart';

class GeneratorScreen extends StatefulWidget {
  const GeneratorScreen({super.key});

  @override
  State<GeneratorScreen> createState() => _GeneratorScreenState();
}

class _GeneratorScreenState extends State<GeneratorScreen> {
  final _passwordController = TextEditingController();
  int _length = 16;
  bool _upper = true;
  bool _lower = true;
  bool _numbers = true;
  bool _symbols = true;

  String _generate() {
    String chars = '';
    if (_upper) chars += 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    if (_lower) chars += 'abcdefghijklmnopqrstuvwxyz';
    if (_numbers) chars += '0123456789';
    if (_symbols) chars += '!@#\$%^&*()_+-=[]{}|;:,.<>?';

    if (chars.isEmpty) {
      chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    }

    final rng = Random.secure();
    return List.generate(_length, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  void _refresh() {
    _passwordController.text = _generate();
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

  @override
  void initState() {
    super.initState();
    _passwordController.text = _generate();
  }

  @override
  Widget build(BuildContext context) {
    final strength = _passwordStrength(_passwordController.text);
    final strengthColor = _strengthColor(strength);

    return Scaffold(
      backgroundColor: PassVaultApp.deepNavy,
      appBar: AppBar(title: const Text('Générateur')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Mot de passe généré ──
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: PassVaultApp.brandSlate,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: PassVaultApp.brandBorder),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _passwordController,
                    readOnly: true,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontFamily: 'JetBrains Mono',
                      fontWeight: FontWeight.w500,
                      letterSpacing: 2,
                    ),
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      fillColor: Colors.transparent,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Force indicator
                  Row(
                    children: List.generate(4, (i) {
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
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
                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Copy
                      _actionButton(
                        icon: Icons.copy,
                        label: 'Copier',
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: _passwordController.text),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('✅ Mot de passe copié !'),
                              duration: Duration(seconds: 2),
                              backgroundColor: PassVaultApp.brandGreen,
                            ),
                          );
                        },
                      ),
                      // Refresh
                      _actionButton(
                        icon: Icons.refresh,
                        label: 'Nouveau',
                        onTap: _refresh,
                      ),
                      // Partage fonctionnel
                      _actionButton(
                        icon: Icons.share_outlined,
                        label: 'Partager',
                        onTap: () async {
                          final pwd = _passwordController.text;
                          await Clipboard.setData(ClipboardData(text: pwd));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('📋 Mot de passe copié ! Collez-le où vous voulez'),
                              duration: Duration(seconds: 3),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ── Curseur longueur ──
            const Text(
              'LONGUEUR',
              style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
                color: PassVaultApp.brandGrey,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _length.toDouble(),
                    min: 4,
                    max: 64,
                    divisions: 60,
                    activeColor: PassVaultApp.electricBlue,
                    label: '$_length',
                    onChanged: (v) {
                      setState(() => _length = v.round());
                      _refresh();
                    },
                  ),
                ),
                Container(
                  width: 48,
                  alignment: Alignment.center,
                  child: Text(
                    '$_length',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── Options ──
            const Text(
              'CARACTÈRES',
              style: TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
                color: PassVaultApp.brandGrey,
              ),
            ),
            const SizedBox(height: 8),

            _optionTile('Lettres majuscules (A-Z)', _upper, () {
              setState(() => _upper = !_upper);
              _refresh();
            }),
            _optionTile('Lettres minuscules (a-z)', _lower, () {
              setState(() => _lower = !_lower);
              _refresh();
            }),
            _optionTile('Chiffres (0-9)', _numbers, () {
              setState(() => _numbers = !_numbers);
              _refresh();
            }),
            _optionTile('Symboles (!@#\$%...)', _symbols, () {
              setState(() => _symbols = !_symbols);
              _refresh();
            }),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Icon(icon, color: PassVaultApp.brandGrey, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: PassVaultApp.brandGrey)),
          ],
        ),
      ),
    );
  }

  Widget _optionTile(String label, bool value, VoidCallback onToggle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: PassVaultApp.brandSlate,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: PassVaultApp.brandBorder),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: (_) => onToggle(),
        title: Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.white,
          ),
        ),
        activeColor: PassVaultApp.brandGreen,
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }
}
