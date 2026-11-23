// Pixel-art UI pieces drawn in code (no image or font files): a 5x7 bitmap font for titles,
// block progress bars, a stepped-corner speech bubble, and a small night scene for hero cards.
import 'dart:math';

import 'package:material_ui/material_ui.dart';

/// 5x7 glyphs, one string per row ('#' = pixel on). Lowercase text is drawn in capitals.
const _glyphs = <String, List<String>>{
  'A': [' ### ', '#   #', '#   #', '#####', '#   #', '#   #', '#   #'],
  'B': ['#### ', '#   #', '#   #', '#### ', '#   #', '#   #', '#### '],
  'C': [' ### ', '#   #', '#    ', '#    ', '#    ', '#   #', ' ### '],
  'D': ['#### ', '#   #', '#   #', '#   #', '#   #', '#   #', '#### '],
  'E': ['#####', '#    ', '#    ', '#### ', '#    ', '#    ', '#####'],
  'F': ['#####', '#    ', '#    ', '#### ', '#    ', '#    ', '#    '],
  'G': [' ### ', '#   #', '#    ', '# ###', '#   #', '#   #', ' ####'],
  'H': ['#   #', '#   #', '#   #', '#####', '#   #', '#   #', '#   #'],
  'I': [' ### ', '  #  ', '  #  ', '  #  ', '  #  ', '  #  ', ' ### '],
  'J': ['  ###', '   # ', '   # ', '   # ', '   # ', '#  # ', ' ##  '],
  'K': ['#   #', '#  # ', '# #  ', '##   ', '# #  ', '#  # ', '#   #'],
  'L': ['#    ', '#    ', '#    ', '#    ', '#    ', '#    ', '#####'],
  'M': ['#   #', '## ##', '# # #', '# # #', '#   #', '#   #', '#   #'],
  'N': ['#   #', '##  #', '# # #', '#  ##', '#   #', '#   #', '#   #'],
  'O': [' ### ', '#   #', '#   #', '#   #', '#   #', '#   #', ' ### '],
  'P': ['#### ', '#   #', '#   #', '#### ', '#    ', '#    ', '#    '],
  'Q': [' ### ', '#   #', '#   #', '#   #', '# # #', '#  # ', ' ## #'],
  'R': ['#### ', '#   #', '#   #', '#### ', '# #  ', '#  # ', '#   #'],
  'S': [' ####', '#    ', '#    ', ' ### ', '    #', '    #', '#### '],
  'T': ['#####', '  #  ', '  #  ', '  #  ', '  #  ', '  #  ', '  #  '],
  'U': ['#   #', '#   #', '#   #', '#   #', '#   #', '#   #', ' ### '],
  'V': ['#   #', '#   #', '#   #', '#   #', '#   #', ' # # ', '  #  '],
  'W': ['#   #', '#   #', '#   #', '# # #', '# # #', '# # #', ' # # '],
  'X': ['#   #', '#   #', ' # # ', '  #  ', ' # # ', '#   #', '#   #'],
  'Y': ['#   #', '#   #', ' # # ', '  #  ', '  #  ', '  #  ', '  #  '],
  'Z': ['#####', '    #', '   # ', '  #  ', ' #   ', '#    ', '#####'],
  '0': [' ### ', '#   #', '#  ##', '# # #', '##  #', '#   #', ' ### '],
  '1': ['  #  ', ' ##  ', '  #  ', '  #  ', '  #  ', '  #  ', ' ### '],
  '2': [' ### ', '#   #', '    #', '   # ', '  #  ', ' #   ', '#####'],
  '3': ['#### ', '    #', '    #', ' ### ', '    #', '    #', '#### '],
  '4': ['#   #', '#   #', '#   #', '#####', '    #', '    #', '    #'],
  '5': ['#####', '#    ', '#    ', '#### ', '    #', '    #', '#### '],
  '6': [' ### ', '#    ', '#    ', '#### ', '#   #', '#   #', ' ### '],
  '7': ['#####', '    #', '   # ', '  #  ', '  #  ', '  #  ', '  #  '],
  '8': [' ### ', '#   #', '#   #', ' ### ', '#   #', '#   #', ' ### '],
  '9': [' ### ', '#   #', '#   #', ' ####', '    #', '    #', ' ### '],
  '!': ['  #  ', '  #  ', '  #  ', '  #  ', '  #  ', '     ', '  #  '],
  '?': [' ### ', '#   #', '    #', '   # ', '  #  ', '     ', '  #  '],
  '.': ['     ', '     ', '     ', '     ', '     ', '     ', '  #  '],
  ',': ['     ', '     ', '     ', '     ', '     ', '  #  ', ' #   '],
  "'": ['  #  ', '  #  ', '     ', '     ', '     ', '     ', '     '],
  '-': ['     ', '     ', '     ', '#####', '     ', '     ', '     '],
  ':': ['     ', '  #  ', '     ', '     ', '     ', '  #  ', '     '],
  '/': ['    #', '    #', '   # ', '  #  ', ' #   ', '#    ', '#    '],
  '&': [' ##  ', '#  # ', '#  # ', ' ##  ', '# # #', '#  # ', ' ## #'],
  '\$': ['  #  ', ' ####', '# #  ', ' ### ', '  # #', '#### ', '  #  '],
  '%': ['##  #', '##  #', '   # ', '  #  ', ' #   ', '#  ##', '#  ##'],
  '+': ['     ', '  #  ', '  #  ', '#####', '  #  ', '  #  ', '     '],
  '(': ['   # ', '  #  ', ' #   ', ' #   ', ' #   ', '  #  ', '   # '],
  ')': [' #   ', '  #  ', '   # ', '   # ', '   # ', '  #  ', ' #   '],
  ' ': ['     ', '     ', '     ', '     ', '     ', '     ', '     '],
};

/// Title text in a chunky pixel font. [size] is the cap height in logical pixels.
class PixelText extends StatelessWidget {
  final String text;
  final double size;
  final Color? color;
  final Color? shadow;
  const PixelText(this.text, {super.key, this.size = 14, this.color, this.shadow});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurface;
    final px = size / 7;
    final chars = text.toUpperCase().split('');
    final w = chars.length * 6 * px - px;
    return Semantics(
      label: text,
      child: ExcludeSemantics(
        child: CustomPaint(size: Size(max(w, 0) + (shadow != null ? px : 0), size + (shadow != null ? px : 0)),
            painter: _PixelTextPainter(chars, px, c, shadow)),
      ),
    );
  }
}

class _PixelTextPainter extends CustomPainter {
  final List<String> chars;
  final double px;
  final Color color;
  final Color? shadow;
  _PixelTextPainter(this.chars, this.px, this.color, this.shadow);

  void _draw(Canvas canvas, Paint p, double dx, double dy) {
    var x = dx;
    for (final ch in chars) {
      final g = _glyphs[ch] ?? _glyphs['?']!;
      for (var r = 0; r < 7; r++) {
        for (var col = 0; col < 5; col++) {
          if (g[r][col] == '#') canvas.drawRect(Rect.fromLTWH(x + col * px, dy + r * px, px + 0.3, px + 0.3), p);
        }
      }
      x += 6 * px;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (shadow != null) _draw(canvas, Paint()..color = shadow!, px, px);
    _draw(canvas, Paint()..color = color, 0, 0);
  }

  @override
  bool shouldRepaint(_PixelTextPainter o) => o.chars.join() != chars.join() || o.color != color || o.px != px || o.shadow != shadow;
}

/// Progress bar made of pixel blocks with a soft highlight. Animates when the value changes.
class PixelBar extends StatelessWidget {
  final double value; // 0..1
  final Color color;
  final double height;
  final bool danger;
  const PixelBar(this.value, {super.key, required this.color, this.height = 10, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.clamp(0, 1)),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      builder: (_, v, _) => SizedBox(
        height: height,
        child: CustomPaint(painter: _PixelBarPainter(v, danger ? const Color(0xFFFF6B6B) : color, track), size: Size.infinite),
      ),
    );
  }
}

class _PixelBarPainter extends CustomPainter {
  final double v;
  final Color color, track;
  _PixelBarPainter(this.v, this.color, this.track);
  @override
  void paint(Canvas canvas, Size s) {
    final r = RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(s.height / 2));
    canvas.drawRRect(r, Paint()..color = track);
    if (v <= 0) return;
    canvas.save();
    canvas.clipRRect(r);
    final w = s.width * v;
    final fill = Rect.fromLTWH(0, 0, w, s.height);
    canvas.drawRect(fill, Paint()..shader = LinearGradient(colors: [color.withValues(alpha: 0.75), color]).createShader(fill));
    // pixel block seams + top highlight
    final seam = Paint()..color = Colors.black.withValues(alpha: 0.18);
    final step = s.height * 1.2;
    for (var x = step; x < w; x += step) {
      canvas.drawRect(Rect.fromLTWH(x, 0, max(1, s.height * 0.12), s.height), seam);
    }
    canvas.drawRect(Rect.fromLTWH(0, 0, w, s.height * 0.3), Paint()..color = Colors.white.withValues(alpha: 0.22));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PixelBarPainter o) => o.v != v || o.color != color || o.track != track;
}

/// Rectangle with stepped (pixel) corners and a 2-px outline, for Clover's speech bubble.
class PixelBorder extends ShapeBorder {
  final double step;
  final Color color;
  final double width;
  const PixelBorder({this.step = 4, this.color = Colors.white, this.width = 2});

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(width);

  Path _path(Rect r) {
    final s = step;
    return Path()
      ..moveTo(r.left + 2 * s, r.top)
      ..lineTo(r.right - 2 * s, r.top)
      ..lineTo(r.right - 2 * s, r.top + s)
      ..lineTo(r.right - s, r.top + s)
      ..lineTo(r.right - s, r.top + 2 * s)
      ..lineTo(r.right, r.top + 2 * s)
      ..lineTo(r.right, r.bottom - 2 * s)
      ..lineTo(r.right - s, r.bottom - 2 * s)
      ..lineTo(r.right - s, r.bottom - s)
      ..lineTo(r.right - 2 * s, r.bottom - s)
      ..lineTo(r.right - 2 * s, r.bottom)
      ..lineTo(r.left + 2 * s, r.bottom)
      ..lineTo(r.left + 2 * s, r.bottom - s)
      ..lineTo(r.left + s, r.bottom - s)
      ..lineTo(r.left + s, r.bottom - 2 * s)
      ..lineTo(r.left, r.bottom - 2 * s)
      ..lineTo(r.left, r.top + 2 * s)
      ..lineTo(r.left + s, r.top + 2 * s)
      ..lineTo(r.left + s, r.top + s)
      ..lineTo(r.left + 2 * s, r.top + s)
      ..close();
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => _path(rect.deflate(width));
  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);
  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    canvas.drawPath(_path(rect.deflate(width / 2)), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color);
  }

  @override
  ShapeBorder scale(double t) => PixelBorder(step: step * t, color: color, width: width * t);
}

/// Pixel night scene (stars, moon, hills) used behind hero cards. Purely decorative.
class NightScene extends StatelessWidget {
  final Color tint;
  const NightScene({super.key, required this.tint});
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _NightPainter(tint), size: Size.infinite);
}

class _NightPainter extends CustomPainter {
  final Color tint;
  _NightPainter(this.tint);
  @override
  void paint(Canvas canvas, Size s) {
    final px = max(3.0, s.height / 40);
    final rng = Random(4);
    final star = Paint()..color = Colors.white.withValues(alpha: 0.55);
    for (var i = 0; i < 26; i++) {
      final x = s.width * (0.55 + rng.nextDouble() * 0.45);
      final y = s.height * rng.nextDouble() * 0.6;
      canvas.drawRect(Rect.fromLTWH((x / px).floorToDouble() * px, (y / px).floorToDouble() * px, px * 0.7, px * 0.7), star);
    }
    // moon: pixelated disc
    final mc = Offset(s.width * 0.86, s.height * 0.3);
    final mr = min(s.height * 0.14, 36.0);
    final moon = Paint()..color = const Color(0xFFE9DDFF).withValues(alpha: 0.85);
    for (var y = -mr; y <= mr; y += px) {
      for (var x = -mr; x <= mr; x += px) {
        if (x * x + y * y <= mr * mr) canvas.drawRect(Rect.fromLTWH(mc.dx + x, mc.dy + y, px, px), moon);
      }
    }
    // hills: two stepped layers
    void hills(double base, double amp, double freq, double phase, Color c) {
      final p = Paint()..color = c;
      for (var x = s.width * 0.6; x < s.width; x += px) {
        final h = base + amp * sin(x / s.width * freq + phase);
        final top = (s.height - h) / px * px;
        canvas.drawRect(Rect.fromLTWH(x, (top / px).floorToDouble() * px, px + 0.5, s.height), p);
      }
    }

    hills(s.height * 0.26, s.height * 0.08, 9, 1, tint.withValues(alpha: 0.22));
    hills(s.height * 0.15, s.height * 0.05, 14, 3, tint.withValues(alpha: 0.38));
  }

  @override
  bool shouldRepaint(_NightPainter o) => o.tint != tint;
}

/// The STACKD logo: pixel letters with a little crown.
class StackdLogo extends StatelessWidget {
  final double size;
  const StackdLogo({super.key, this.size = 22});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(clipBehavior: Clip.none, children: [
      PixelText('STACKD', size: size, color: cs.onSurface, shadow: cs.primary),
      Positioned(right: -size * 0.55, top: -size * 0.55, child: Icon(Icons.workspace_premium_rounded, size: size * 0.8, color: const Color(0xFFFFD166))),
    ]);
  }
}
