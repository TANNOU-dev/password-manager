import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Identité visuelle d'un élément, dérivée de son nom ou de son domaine.
///
/// Pourquoi pas les vrais favicons : les récupérer signifie demander à un
/// serveur tiers une icône par site présent dans le coffre. Cette suite de
/// requêtes dessine la liste complète des comptes de l'utilisateur pour
/// quiconque observe le réseau — exactement ce que le chiffrement du coffre
/// cherche à empêcher. Bitwarden expose ce réglage et le documente comme une
/// fuite de vie privée ; ici il est désactivé par défaut.
///
/// À la place, une pastille monogramme : deux lettres sur un dégradé dont la
/// teinte est dérivée du nom. Stable, reconnaissable d'un coup d'œil, et
/// entièrement calculée sur l'appareil.
class Monogram {
  const Monogram({required this.initials, required this.hue});

  final String initials;
  final double hue;

  /// Hachage FNV-1a : petit, déterministe, et bien mieux réparti que
  /// `hashCode`, qui n'est pas stable d'une exécution à l'autre en Dart.
  static int _fnv1a(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  static Monogram of(String source) {
    final cleaned = source.trim();
    if (cleaned.isEmpty) {
      return const Monogram(initials: '?', hue: 240);
    }

    // Un domaine se réduit à son label principal : « mail.google.com » donne
    // « Google », pas « Mail ».
    final label = _primaryLabel(cleaned);

    return Monogram(
      initials: _initialsOf(label),
      hue: (_fnv1a(label.toLowerCase()) % 360).toDouble(),
    );
  }

  static String _primaryLabel(String source) {
    var value = source;
    if (value.contains('://')) {
      value = Uri.tryParse(value)?.host ?? value;
    }
    if (!value.contains(' ') && value.contains('.')) {
      final parts = value.split('.').where((p) => p.isNotEmpty).toList();
      if (parts.length >= 2) {
        // Avant-dernier segment : gère « exemple.co.uk » comme « exemple.com ».
        final candidate = parts.length >= 3 && parts[parts.length - 2].length <= 3
            ? parts[parts.length - 3]
            : parts[parts.length - 2];
        return candidate;
      }
    }
    return value;
  }

  static String _initialsOf(String label) {
    final words = label
        .split(RegExp(r'[\s\-_.]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final word = words.first;
      return word.length == 1
          ? word.toUpperCase()
          : word.substring(0, 2).toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  /// Deux teintes voisines pour un dégradé qui a du relief sans partir dans
  /// l'arc-en-ciel.
  List<Color> gradient({required bool dark}) {
    final saturation = dark ? 0.52 : 0.62;
    final lightness = dark ? 0.46 : 0.56;
    return [
      HSLColor.fromAHSL(1, hue, saturation, lightness).toColor(),
      HSLColor.fromAHSL(1, (hue + 26) % 360, saturation, lightness * 0.82)
          .toColor(),
    ];
  }

  /// Le texte doit rester lisible sur le dégradé quelle que soit la teinte.
  Color foreground({required bool dark}) {
    final base = gradient(dark: dark).first;
    // Luminance relative approchée, pondérée comme la perception humaine.
    final luminance = base.computeLuminance();
    return luminance > 0.45
        ? const Color(0xFF10131F)
        : const Color(0xFFFFFFFF);
  }
}

/// Pastille monogramme. Utilisée dans la liste du coffre et sur les détails.
class MonogramTile extends StatelessWidget {
  const MonogramTile({
    super.key,
    required this.source,
    this.size = 44,
    this.radius,
    this.icon,
  });

  /// Nom de l'élément, ou domaine si on en a un : le domaine donne une pastille
  /// plus stable, parce qu'il ne change pas quand on renomme l'entrée.
  final String source;
  final double size;
  final double? radius;

  /// Remplace les initiales, pour les types qui n'ont pas de nom de marque
  /// (carte bancaire, note, identité).
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final mono = Monogram.of(source);
    final colors = mono.gradient(dark: dark);
    final fg = mono.foreground(dark: dark);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius ?? size * 0.32),
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        // Liseré interne clair : détache la pastille du fond de la carte.
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      alignment: Alignment.center,
      child: icon != null
          ? Icon(icon, size: size * 0.46, color: fg)
          : Text(
              mono.initials,
              style: TextStyle(
                fontSize: size * (mono.initials.length > 1 ? 0.34 : 0.42),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: fg,
                height: 1,
              ),
            ),
    );
  }
}

/// Anneau de progression du code TOTP. Tourne sur la fenêtre de 30 s.
class TotpRing extends StatelessWidget {
  const TotpRing({
    super.key,
    required this.progress,
    required this.color,
    this.size = 20,
    this.strokeWidth = 2.4,
  });

  /// 1.0 au début de la fenêtre, 0.0 juste avant son expiration.
  final double progress;
  final Color color;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          progress: progress.clamp(0.0, 1.0),
          color: color,
          track: color.withValues(alpha: 0.2),
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
    required this.strokeWidth,
  });

  final double progress;
  final Color color;
  final Color track;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (size.shortestSide - strokeWidth) / 2;

    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}
