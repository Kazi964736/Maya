import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

enum OrbMood { idle, listening, thinking, speaking }

/// Maya's glowing orb. It breathes when idle, swells with your voice while
/// listening, swirls while thinking and pulses while speaking.
class MayaOrb extends StatefulWidget {
  const MayaOrb({super.key, required this.size, required this.mood, this.level});

  final double size;
  final OrbMood mood;

  /// Microphone loudness from the speech service (roughly -2 to 10).
  final ValueNotifier<double>? level;

  @override
  State<MayaOrb> createState() => _MayaOrbState();
}

class _MayaOrbState extends State<MayaOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 12))
    ..repeat();
  double _smoothLevel = 0;

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _spin,
        builder: (_, __) {
          final raw = ((widget.level?.value ?? 0) + 2) / 12;
          final target = widget.mood == OrbMood.listening ? raw.clamp(0.0, 1.0) : 0.0;
          _smoothLevel += (target - _smoothLevel) * 0.2;
          return CustomPaint(
            size: Size.square(widget.size),
            painter: _OrbPainter(t: _spin.value, mood: widget.mood, level: _smoothLevel),
          );
        },
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({required this.t, required this.mood, required this.level});

  final double t;
  final OrbMood mood;
  final double level;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final a = t * 2 * math.pi;

    final speed = switch (mood) {
      OrbMood.idle => 1.0,
      OrbMood.listening => 2.0,
      OrbMood.thinking => 5.0,
      OrbMood.speaking => 2.5,
    };
    final pulse = switch (mood) {
      OrbMood.idle => 0.03 * math.sin(a * 3),
      OrbMood.listening => 0.12 * level + 0.02 * math.sin(a * 8),
      OrbMood.thinking => 0.03 * math.sin(a * 10),
      OrbMood.speaking => 0.07 * math.sin(a * 14).abs(),
    };
    final core = r * (0.62 + pulse);

    // Soft outer glow.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          colors: [
            MayaColors.violet.withValues(alpha: 0.35 + level * 0.25),
            MayaColors.pink.withValues(alpha: 0.10),
            Colors.transparent,
          ],
          stops: const [0.35, 0.7, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // Core sphere.
    final coreRect = Rect.fromCircle(center: c, radius: core);
    canvas.drawCircle(
      c,
      core,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF2A1A5E), Color(0xFF120B26)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(coreRect),
    );

    // Coloured blobs swirling inside the sphere.
    canvas.save();
    canvas.clipPath(Path()..addOval(coreRect));
    final blobs = [
      (MayaColors.violet, 0.0, 0.55),
      (MayaColors.pink, 2.1, 0.5),
      (MayaColors.cyan, 4.2, 0.42),
    ];
    for (final (color, phase, scale) in blobs) {
      final angle = a * speed + phase;
      final wobble = 0.35 + 0.1 * math.sin(a * 2 + phase);
      final pos = c + Offset(math.cos(angle), math.sin(angle * 0.8)) * core * wobble;
      final br = core * (scale + level * 0.25);
      canvas.drawCircle(
        pos,
        br,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: 0.95), color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: pos, radius: br)),
      );
    }
    canvas.restore();

    // Glass highlight and rim.
    canvas.drawCircle(
      c,
      core,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.5),
          radius: 0.9,
          colors: [Colors.white.withValues(alpha: 0.28), Colors.transparent],
          stops: const [0.0, 0.55],
        ).createShader(coreRect),
    );
    canvas.drawCircle(
      c,
      core,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.18),
    );
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.t != t || old.mood != mood || old.level != level;
}
