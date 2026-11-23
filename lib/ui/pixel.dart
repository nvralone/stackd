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
/// Two hand-made versions: a small one for phones and a wider one with trees for PC / tablet.
/// Everything is drawn in fixed-size pixels anchored to the bottom-right corner, so it never stretches
/// with the card's height.
class NightScene extends StatelessWidget {
  final Color tint;
  /// null = pick by screen width (phone under 600 px wide).
  final bool? phone;
  const NightScene({super.key, required this.tint, this.phone});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _NightPainter(tint, phone ?? MediaQuery.sizeOf(context).width < 600), size: Size.infinite);
}

/// 13x13 crescent moon: '#' light, '+' crater, ' ' empty.
const _moon = [
  '     ###     ',
  '   ####      ',
  '  ##+#       ',
  ' #####       ',
  ' #####       ',
  '###+##       ',
  '######       ',
  '#######      ',
  ' ##+####     ',
  ' ########### ',
  '  ####+####  ',
  '   #######   ',
  '     ###     ',
];

/// 5x9 pine tree.
const _tree = [
  '  #  ',
  '  #  ',
  ' ### ',
  ' ### ',
  '#####',
  ' ### ',
  '#####',
  '#####',
  '  #  ',
];

class _NightPainter extends CustomPainter {
  final Color tint;
  final bool phone;
  _NightPainter(this.tint, this.phone);

  @override
  void paint(Canvas canvas, Size s) {
    final px = phone ? 3.0 : 4.0;
    // small boxes (side menu, card corners) use their whole width
    final areaW = s.width < 260 ? s.width : min(s.width * (phone ? 0.5 : 0.42), phone ? 170.0 : 420.0);
    final left = s.width - areaW;
    void dot(double x, double y, Paint p, [double w = 1, double h = 1]) =>
        canvas.drawRect(Rect.fromLTWH(left + x * px, y * px, w * px, h * px), p);

    // stars: fixed spots in the scene's area (grid units)
    final cols = (areaW / px).floor();
    final rows = (s.height / px).floor();
    final star = Paint()..color = Colors.white.withValues(alpha: 0.6);
    final dim = Paint()..color = Colors.white.withValues(alpha: 0.3);
    final rng = Random(7);
    for (var i = 0; i < (phone ? 9 : 22); i++) {
      final x = rng.nextInt(max(1, cols - 2)).toDouble();
      final y = rng.nextInt(max(1, (rows * 0.55).floor())).toDouble();
      dot(x, y, i % 3 == 0 ? star : dim);
    }

    // moon sprite, top-right
    final light = Paint()..color = const Color(0xFFEDE3FF).withValues(alpha: 0.9);
    final shade = Paint()..color = const Color(0xFFC9B8F0).withValues(alpha: 0.9);
    final mx = cols - 13 - (phone ? 3 : 5);
    final my = phone ? 3 : 4;
    for (var r = 0; r < _moon.length; r++) {
      for (var c = 0; c < _moon[r].length; c++) {
        final ch = _moon[r][c];
        if (ch != ' ') dot((mx + c).toDouble(), (my + r).toDouble(), ch == '+' ? shade : light);
      }
    }

    // hills: hand-shaped heights (grid units from the bottom), back layer then front layer
    void hills(List<int> shape, Color c) {
      final p = Paint()..color = c;
      final step = cols / shape.length;
      for (var x = 0; x < cols; x++) {
        final h = shape[min(shape.length - 1, (x / step).floor())];
        canvas.drawRect(Rect.fromLTWH(left + x * px, s.height - h * px, px, h * px), p);
      }
    }

    if (phone) {
      hills(const [5, 6, 7, 8, 8, 9, 9, 8, 7, 7, 6, 6], tint.withValues(alpha: 0.22));
      hills(const [2, 3, 3, 4, 4, 5, 5, 4, 4, 3, 3, 4], tint.withValues(alpha: 0.4));
    } else {
      hills(const [6, 8, 10, 12, 13, 14, 13, 12, 10, 9, 10, 12, 14, 15, 15, 14, 12, 10], tint.withValues(alpha: 0.2));
      hills(const [3, 4, 5, 6, 6, 7, 7, 6, 5, 5, 6, 7, 8, 8, 7, 6, 5, 5], tint.withValues(alpha: 0.38));
      // a few pine trees on the front hills
      final tp = Paint()..color = tint.withValues(alpha: 0.55);
      for (final fx in const [0.12, 0.2, 0.62, 0.7, 0.86]) {
        final tx = (cols * fx).floorToDouble();
        final base = rows - 6;
        for (var r = 0; r < _tree.length; r++) {
          for (var c = 0; c < 5; c++) {
            if (_tree[r][c] == '#') dot(tx + c, (base - _tree.length + r).toDouble(), tp);
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(_NightPainter o) => o.tint != tint || o.phone != phone;
}
