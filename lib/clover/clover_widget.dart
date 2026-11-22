// Clover on screen: per-mood pixel-art faces (assets/clover/moods), random blinking, mouth flaps while
// he talks, a wagging tail layer, procedural body motion, mood effect glyphs and a speech bubble.
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'brain.dart';
import 'moods.dart';

Set<String>? _assets;
Future<Set<String>> _assetSet() async =>
    _assets ??= (await AssetManifest.loadFromAssetBundle(rootBundle)).listAssets().toSet();

const _basePath = 'assets/clover/clover_base.png';
const _tailPath = 'assets/clover/moods/tail.png';

class CloverSprite extends StatefulWidget {
  final CloverMood mood;
  final double size;
  final VoidCallback? onTap;
  /// While true, Clover's mouth flaps (wire to AppState.talking).
  final ValueListenable<bool>? talking;
  const CloverSprite({super.key, required this.mood, this.size = 120, this.onTap, this.talking});
  @override
  State<CloverSprite> createState() => _CloverSpriteState();
}

class _CloverSpriteState extends State<CloverSprite> with TickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  late final AnimationController _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
  final _rng = Random();
  String _face = _basePath;
  String? _blink, _talk;
  bool _hasTail = false, _blinking = false, _mouthOpen = false;
  Timer? _blinkTimer, _talkTimer;

  @override
  void initState() {
    super.initState();
    _resolve();
    _pop.forward(from: 0);
    _scheduleBlink();
    widget.talking?.addListener(_onTalking);
  }

  @override
  void didUpdateWidget(CloverSprite old) {
    super.didUpdateWidget(old);
    if (old.talking != widget.talking) {
      old.talking?.removeListener(_onTalking);
      widget.talking?.addListener(_onTalking);
    }
    if (old.mood != widget.mood) {
      _resolve();
      _pop.forward(from: 0);
    }
  }

  Future<void> _resolve() async {
    final set = await _assetSet();
    final p = widget.mood.spritePath;
    final stem = p.substring(0, p.length - 4);
    if (!mounted) return;
    setState(() {
      _hasTail = set.contains(_tailPath) && set.contains(p);
      _face = set.contains(p) ? p : _basePath;
      _blink = set.contains('${stem}_blink.png') ? '${stem}_blink.png' : null;
      _talk = set.contains('${stem}_talk.png') ? '${stem}_talk.png' : null;
    });
    for (final a in [_face, _blink, _talk]) {
      if (a != null && mounted) precacheImage(AssetImage(a), context);
    }
  }

  void _scheduleBlink() {
    _blinkTimer = Timer(Duration(milliseconds: 2200 + _rng.nextInt(3500)), () {
      if (!mounted) return;
      setState(() => _blinking = true);
      _blinkTimer = Timer(const Duration(milliseconds: 140), () {
        if (!mounted) return;
        setState(() => _blinking = false);
        _scheduleBlink();
      });
    });
  }

  void _onTalking() {
    _talkTimer?.cancel();
    if (widget.talking?.value == true) {
      _talkTimer = Timer.periodic(Duration(milliseconds: 110 + _rng.nextInt(40)), (_) {
        if (mounted) setState(() => _mouthOpen = !_mouthOpen);
      });
    } else if (mounted) {
      setState(() => _mouthOpen = false);
    }
  }

  @override
  void dispose() {
    widget.talking?.removeListener(_onTalking);
    _blinkTimer?.cancel();
    _talkTimer?.cancel();
    _loop.dispose();
    _pop.dispose();
    super.dispose();
  }

  String get _frame => (_mouthOpen && _talk != null) ? _talk! : (_blinking && _blink != null ? _blink! : _face);

  Widget _img(String path, double s) =>
      Image.asset(path, width: s, height: s, filterQuality: FilterQuality.none, isAntiAlias: false, gaplessPlayback: true);

  @override
  Widget build(BuildContext context) {
    final mood = widget.mood;
    final reduce = MediaQuery.of(context).disableAnimations;
    return Semantics(
      label: 'Clover the raccoon, ${mood.label}',
      button: widget.onTap != null,
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.size * 1.35,
          height: widget.size * 1.2,
          child: AnimatedBuilder(
            animation: Listenable.merge([_loop, _pop]),
            builder: (context, _) {
              final t = reduce ? 0.0 : _loop.value * 2 * pi;
              final s = widget.size;
              final bounce = -sin(t * (1 + mood.bounce)).abs() * mood.bounce * s * 0.05;
              final shake = sin(t * 9) * mood.shake * s * 0.012;
              final pop = Curves.elasticOut.transform(_pop.value);
              final jump = mood.jump ? -sin(_pop.value * pi) * s * 0.18 : 0.0;
              final droop = mood.droop * s * 0.03;
              final squash = 1 + (mood.bounce > 1 ? sin(t * (1 + mood.bounce)) * 0.03 : 0);
              final tilt = mood.tilt * 0.08 + (mood.tilt != 0 ? sin(t) * 0.02 : 0);
              // Tail: happy moods wag fast and wide, low moods barely move.
              final wagSpeed = 2 + mood.bounce * 2, wagAmp = 0.06 + mood.bounce * 0.07 - mood.droop * 0.04;
              final wag = sin(t * wagSpeed) * wagAmp.clamp(0.02, 0.25);
              final body = _hasTail
                  ? Stack(children: [
                      // pivot where the tail meets the body (x 126/172, y 132/169 of the sprite)
                      Transform.rotate(angle: wag, alignment: const Alignment(126 / 86 - 1, 132 / 84.5 - 1), child: _img(_tailPath, s)),
                      _img(_frame, s),
                    ])
                  : _img(_frame, s);
              return Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
                Positioned(
                  bottom: 2,
                  child: Container(
                    width: s * (0.7 - (bounce.abs() + jump.abs()) / s),
                    height: s * 0.08,
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(s)),
                  ),
                ),
                Transform.translate(
                  offset: Offset(shake, bounce + jump + droop),
                  child: Transform.rotate(
                    angle: tilt,
                    alignment: Alignment.bottomCenter,
                    child: Transform.scale(
                      scaleX: (0.85 + 0.15 * pop) / squash,
                      scaleY: (0.85 + 0.15 * pop) * squash,
                      alignment: Alignment.bottomCenter,
                      child: Padding(padding: EdgeInsets.only(bottom: s * 0.05), child: body),
                    ),
                  ),
                ),
                if (mood.effect != CloverEffect.none)
                  Positioned(right: 0, top: 0, child: _Effect(mood.effect, s, reduce ? 0 : _loop.value)),
              ]);
            },
          ),
        ),
      ),
    );
  }
}
/// Small pixel-style glyphs (palette matches the reference's warm yellow marks).
class _Effect extends StatelessWidget {
  final CloverEffect e;
  final double s, t;
  const _Effect(this.e, this.s, this.t);
  static const yellow = Color(0xFFF2C94C);

  @override
  Widget build(BuildContext context) {
    final float = sin(t * 2 * pi) * s * 0.03;
    final fs = s * 0.2;
    Widget txt(String v, Color c) => Text(v,
        style: TextStyle(fontSize: fs, fontWeight: FontWeight.w900, color: c, fontFamily: 'monospace', height: 1,
            shadows: const [Shadow(color: Colors.black54, offset: Offset(1.5, 1.5))]));
    Widget ic(IconData i, Color c) => Icon(i, size: fs * 1.1, color: c);
    final child = switch (e) {
      CloverEffect.dollar => txt('\$\$', const Color(0xFF7BD88F)),
      CloverEffect.marks => Transform.rotate(angle: -0.4, child: txt('///', yellow)),
      CloverEffect.sparkle => ic(Icons.auto_awesome, yellow),
      CloverEffect.anger => ic(Icons.whatshot_rounded, const Color(0xFFFF6B6B)),
      CloverEffect.sigh => txt('~', Colors.white70),
      CloverEffect.exclaim => txt('!!', yellow),
      CloverEffect.sweat => ic(Icons.water_drop_rounded, const Color(0xFF7FB2FF)),
      CloverEffect.tears => ic(Icons.water_drop_outlined, const Color(0xFF7FB2FF)),
      CloverEffect.squint => txt('¬_¬', Colors.white70),
      CloverEffect.dots => txt('...', Colors.white70),
      CloverEffect.question => txt('?', yellow),
      CloverEffect.zzz => txt('z Z', const Color(0xFFB39DFF)),
      CloverEffect.heart => ic(Icons.favorite_rounded, const Color(0xFFF06292)),
      CloverEffect.confetti => ic(Icons.celebration_rounded, yellow),
      CloverEffect.fire => ic(Icons.local_fire_department_rounded, const Color(0xFFFFA94D)),
      CloverEffect.sun => ic(Icons.wb_sunny_rounded, yellow),
      CloverEffect.flat => txt('-_-', Colors.white54),
      CloverEffect.none => const SizedBox(),
    };
    return Transform.translate(offset: Offset(0, float), child: child);
  }
}

/// Clover + speech bubble + replay. Subtitles can be turned off; the bubble then shows an icon only.
class CloverCard extends StatelessWidget {
  final CloverSays says;
  final bool subtitles;
  final VoidCallback? onReplay, onTap;
  final double size;
  final ValueListenable<bool>? talking;
  const CloverCard({super.key, required this.says, this.subtitles = true, this.onReplay, this.onTap, this.size = 96, this.talking});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      CloverSprite(mood: says.mood, size: size, onTap: onTap, talking: talking),
      const SizedBox(width: 6),
      Expanded(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (c, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, .15), end: Offset.zero).animate(a), child: c)),
          child: Container(
            key: ValueKey(says.lineId + says.text),
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.14),
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18), topRight: Radius.circular(18), bottomRight: Radius.circular(18), bottomLeft: Radius.circular(4)),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('CLOVER · ${says.mood.label.toUpperCase()}',
                      style: TextStyle(fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: cs.primary)),
                  const SizedBox(height: 4),
                  Text(subtitles ? says.text : '(subtitles off)', style: const TextStyle(fontWeight: FontWeight.w600, height: 1.3)),
                ]),
              ),
              if (onReplay != null)
                IconButton(tooltip: 'Replay', onPressed: onReplay, icon: const Icon(Icons.replay_rounded, size: 20)),
            ]),
          ),
        ),
      ),
    ]);
  }
}
