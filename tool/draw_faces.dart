// Generates Clover's mood sprites from the official base sprite.
// Body, hood, ears, mask and colors stay exactly as in the reference; only the face
// (eyes, mouth, blush, tears, accessories) is redrawn in chunky 4px pixels.
// Outputs (all 172x169, tail removed): assets/clover/moods/<mood>.png, <mood>_blink.png, <mood>_talk.png
// and assets/clover/moods/tail.png (the tail alone, for the wag animation).
// Run: dart run tool/draw_faces.dart
import 'dart:io';
import 'package:image/image.dart' as img;

const cell = 4;
const eyeL = (54, 67), eyeR = (95, 73); // eye centers in the base sprite
const mouthX = 74, mouthTop = 101; // on the white muzzle below the mask
const blushL = (42, 93), blushR = (106, 101);
const tailX = 126, tailY = 104; // everything right/below this corner is tail

late img.Image base;
late img.Color maskC;
final white = img.ColorRgba8(241, 235, 237, 255);
final dark = img.ColorRgba8(44, 41, 50, 255);
final colors = <String, img.Color>{
  'W': img.ColorRgba8(241, 235, 237, 255), // body white
  'K': img.ColorRgba8(44, 41, 50, 255), // outline dark
  'R': img.ColorRgba8(222, 92, 110, 255), // tongue
  'P': img.ColorRgba8(242, 160, 180, 255), // blush
  'B': img.ColorRgba8(127, 178, 255, 255), // tears / sweat
  'G': img.ColorRgba8(123, 216, 143, 255), // dollar green
  'Y': img.ColorRgba8(242, 201, 76, 255), // gold
  'S': img.ColorRgba8(20, 18, 26, 255), // sunglasses
  'L': img.ColorRgba8(150, 148, 160, 255), // lens shine
};

// ---------------------------------------------------------------- shapes (W on the dark mask; K on the white muzzle)
const shapes = <String, List<String>>{
  'open': ['.WWWW.', 'WWWWWW', 'WWKKWW', 'WWKKWW', 'WWWWWW', '.WWWW.'],
  'up': ['.WWWW.', 'WKKWWW', 'WKKWWW', 'WWWWWW', 'WWWWWW', '.WWWW.'],
  'side': ['.WWWW.', 'WWWWWW', 'WWWWKK', 'WWWWKK', 'WWWWWW', '.WWWW.'],
  'half': ['......', '......', 'WWWWWW', 'WWWKKW', 'WWWKKW', '.WWWW.'],
  'halfSide': ['......', '......', 'WWWWWW', 'WWWWKK', 'WWWWKK', '.WWWW.'],
  'squint': ['......', '......', 'WWWWWW', '.WKKW.', '......', '......'],
  'blink': ['......', '......', '......', 'WWWWWW', '......', '......'],
  'sleep': ['......', '......', 'W....W', '.WWWW.', '......', '......'],
  'arc': ['..WW..', '.WWWW.', 'WW..WW', 'W....W', '......', '......'],
  'shock': ['..WWW..', '.WWWWW.', 'WWWWWWW', 'WWWKWWW', 'WWWWWWW', '.WWWWW.', '..WWW..'],
  'shiny': ['..WWW..', '.WKKKW.', 'WKWWKKW', 'WKWKKKW', 'WKKKKKW', '.WKKKW.', '..WWW..'],
  'dollar': ['..G..', '.GGGG', 'G.G..', '.GGG.', '..G.G', 'GGGG.', '..G..'],
  'dot': ['WW', 'WW'],
  'spiral': ['WWWWW', '....W', '.WW.W', '.W..W', '.WWWW'],
  'star': ['..W..', '.WWW.', 'WWWWW', '.WWW.', '.W.W.'],
  'angryL': ['W.....', 'WWW...', 'WWWWW.', 'WWWKKW', 'WWWKKW', '.WWWW.'],
  'detL': ['......', 'WW....', 'WWWWW.', 'WWWKKW', '.WWWW.', '......'],
  'sadL': ['......', '...WWW', '.WWWWW', 'WWWKKW', 'WWWKKW', '.WWWW.'],
  // mouths
  'smile': ['K...K', '.KKK.'],
  'grin': ['KKKKK', 'KRRRK', '.KKK.'],
  'bigGrin': ['KKKKKKK', 'KRRRRRK', '.KRRRK.', '..KKK..'],
  'o': ['.KK.', 'KKKK', 'KKKK', '.KK.'],
  'oSmall': ['KK', 'KK'],
  'talk': ['.KK.', 'KRRK', '.KK.'],
  'flat': ['KKKK'],
  'frown': ['.KKK.', 'K...K'],
  'wobble': ['.K.K.', 'K.K.K'],
  'smirk': ['....K', 'KKKK.'],
  'squiggle': ['.K..K', 'K.KK.'],
  'tongue': ['KKKKK', 'K...K', '.KRK.', '..R..'],
  'blush': ['PPP'],
  'tear': ['B', 'B', 'B', 'B', 'B', 'B', 'BB'],
  'drop': ['.B.', 'BBB', 'BBB', '.B.'],
  'glasses': ['SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS'], // placeholder, drawn procedurally
};

List<String> mirror(List<String> s) => [for (final r in s) r.split('').reversed.join()];

class Face {
  final String? l, r, mouth, talk; // shape names; r defaults to l (mirrored for *L shapes)
  final bool blush, tears, keepEyes, glasses, sweat;
  final bool canBlink;
  const Face({this.l, this.r, this.mouth, this.talk, this.blush = false, this.tears = false, this.keepEyes = false,
      this.glasses = false, this.sweat = false, this.canBlink = true});
}

const faces = <String, Face>{
  'happy': Face(keepEyes: true, talk: 'talk', canBlink: false),
  'proud': Face(l: 'arc', mouth: 'smile', talk: 'grin', blush: true, canBlink: false),
  'dollar_eyes': Face(l: 'dollar', mouth: 'grin', talk: 'bigGrin', canBlink: false),
  'excited': Face(l: 'star', mouth: 'bigGrin', talk: 'grin', blush: true, canBlink: false),
  'angry': Face(l: 'angryL', mouth: 'frown', talk: 'grin'),
  'disappointed': Face(l: 'half', mouth: 'frown', talk: 'talk'),
  'shocked': Face(l: 'shock', mouth: 'o', talk: 'oSmall'),
  'panicking': Face(l: 'spiral', mouth: 'wobble', talk: 'o', sweat: true, canBlink: false),
  'crying': Face(l: 'sadL', mouth: 'wobble', talk: 'o', tears: true),
  'suspicious': Face(l: 'squint', r: 'side', mouth: 'flat', talk: 'talk'),
  'thinking': Face(l: 'up', mouth: 'smirk', talk: 'talk'),
  'confused': Face(l: 'open', r: 'squint', mouth: 'squiggle', talk: 'talk'),
  'sleepy': Face(l: 'sleep', mouth: 'oSmall', talk: 'talk', canBlink: false),
  'bored': Face(l: 'half', mouth: 'flat', talk: 'talk'),
  'smug': Face(l: 'halfSide', mouth: 'smirk', talk: 'grin', blush: true),
  'begging': Face(l: 'shiny', mouth: 'smile', talk: 'tongue', blush: true),
  'celebrating': Face(l: 'arc', mouth: 'bigGrin', talk: 'grin', blush: true, canBlink: false),
  'determined': Face(l: 'detL', mouth: 'smirk', talk: 'grin'),
  'vacation': Face(glasses: true, mouth: 'smile', talk: 'grin', canBlink: false),
  'dead_inside': Face(l: 'dot', mouth: 'flat', talk: 'oSmall'),
};

// ---------------------------------------------------------------- drawing
void stamp(img.Image im, List<String> s, (int, int) center) {
  final h = s.length, w = s.first.length;
  final x0 = center.$1 - w * cell ~/ 2, y0 = center.$2 - h * cell ~/ 2;
  for (var r = 0; r < h; r++) {
    for (var c = 0; c < w; c++) {
      final col = colors[s[r][c]];
      if (col == null) continue;
      img.fillRect(im, x1: x0 + c * cell, y1: y0 + r * cell, x2: x0 + c * cell + cell - 1, y2: y0 + r * cell + cell - 1, color: col);
    }
  }
}

double lum(img.Pixel p) => p.r * 0.3 + p.g * 0.59 + p.b * 0.11;

/// Paints the original eye whites with mask color (only light blobs fully inside each eye box).
void eraseEyes(img.Image im) {
  for (final (cx, cy) in [eyeL, eyeR]) {
    final x0 = cx - 18, x1 = cx + 18, y0 = cy - 14, y1 = cy + 14;
    final seen = <int>{};
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final k = y * im.width + x;
        if (seen.contains(k) || im.getPixel(x, y).a < 128 || lum(im.getPixel(x, y)) < 110) continue;
        // flood light blob
        final blob = <int>[];
        var touchesEdge = false;
        final q = [k];
        seen.add(k);
        while (q.isNotEmpty) {
          final p = q.removeLast();
          blob.add(p);
          final px = p % im.width, py = p ~/ im.width;
          if (px <= x0 || px >= x1 || py <= y0 || py >= y1) touchesEdge = true;
          for (final n in [p - 1, p + 1, p - im.width, p + im.width]) {
            final nx = n % im.width, ny = n ~/ im.width;
            if (nx < x0 - 2 || nx > x1 + 2 || ny < y0 - 2 || ny > y1 + 2 || seen.contains(n)) continue;
            final np = im.getPixel(nx, ny);
            if (np.a < 128 || lum(np) < 110) continue;
            seen.add(n);
            q.add(n);
          }
        }
        if (touchesEdge) continue;
        for (final p in blob) {
          im.setPixel(p % im.width, p ~/ im.width, maskC);
        }
        // soften anti-aliased leftovers around the blob
        for (final p in blob) {
          for (final n in [p - 1, p + 1, p - im.width, p + im.width, p - 2, p + 2, p - 2 * im.width, p + 2 * im.width]) {
            final nx = n % im.width, ny = n ~/ im.width;
            final np = im.getPixel(nx, ny);
            if (np.a > 128 && lum(np) >= 60) im.setPixel(nx, ny, maskC);
          }
        }
      }
    }
  }
}

void drawGlasses(img.Image im) {
  final s = colors['S']!, l = colors['L']!;
  // two lenses + bridge, tilted with the head (right eye sits lower)
  img.fillRect(im, x1: eyeL.$1 - 15, y1: eyeL.$2 - 9, x2: eyeL.$1 + 13, y2: eyeL.$2 + 9, color: s);
  img.fillRect(im, x1: eyeR.$1 - 13, y1: eyeR.$2 - 9, x2: eyeR.$1 + 15, y2: eyeR.$2 + 9, color: s);
  img.fillRect(im, x1: eyeL.$1 + 13, y1: eyeL.$2 - 5, x2: eyeR.$1 - 13, y2: eyeL.$2 - 1, color: s);
  img.fillRect(im, x1: eyeL.$1 - 11, y1: eyeL.$2 - 6, x2: eyeL.$1 - 6, y2: eyeL.$2 - 3, color: l);
  img.fillRect(im, x1: eyeR.$1 - 9, y1: eyeR.$2 - 6, x2: eyeR.$1 - 4, y2: eyeR.$2 - 3, color: l);
}

img.Image withoutTail(img.Image src) {
  final o = src.clone();
  for (var y = tailY; y < o.height; y++) {
    for (var x = tailX; x < o.width; x++) {
      o.setPixelRgba(x, y, 0, 0, 0, 0);
    }
  }
  return o;
}

img.Image tailOnly(img.Image src) {
  final o = img.Image(width: src.width, height: src.height, numChannels: 4);
  for (var y = tailY; y < src.height; y++) {
    for (var x = tailX; x < src.width; x++) {
      final p = src.getPixel(x, y);
      if (p.a > 0) o.setPixelRgba(x, y, p.r, p.g, p.b, p.a);
    }
  }
  return o;
}

img.Image render(Face f, {bool blink = false, bool talk = false}) {
  final im = withoutTail(base);
  if (!f.keepEyes || blink) {
    eraseEyes(im);
    if (f.glasses) {
      drawGlasses(im);
    } else {
      final l = blink ? 'blink' : f.l!;
      final r = blink ? 'blink' : (f.r ?? f.l!);
      stamp(im, shapes[l]!, eyeL);
      stamp(im, r.endsWith('L') ? mirror(shapes[r]!) : shapes[r]!, eyeR);
    }
  }
  if (f.blush) {
    stamp(im, shapes['blush']!, blushL);
    stamp(im, shapes['blush']!, blushR);
  }
  if (f.tears) {
    stamp(im, shapes['tear']!, (eyeL.$1 - 6, eyeL.$2 + 22));
    stamp(im, shapes['tear']!, (eyeR.$1 + 6, eyeR.$2 + 22));
  }
  if (f.sweat) stamp(im, shapes['drop']!, (128, 50));
  final mouth = talk ? f.talk : f.mouth;
  if (mouth != null) stamp(im, shapes[mouth]!, (mouthX, mouthTop + shapes[mouth]!.length * cell ~/ 2));
  return im;
}

void main() {
  base = img.decodePng(File('assets/clover/clover_base.png').readAsBytesSync())!;
  maskC = base.getPixel(75, 56).clone();
  final out = Directory('assets/clover/moods')..createSync(recursive: true);
  File('${out.path}/tail.png').writeAsBytesSync(img.encodePng(tailOnly(base)));
  final sheet = img.Image(width: 5 * 180, height: 4 * 3 * 175, numChannels: 4);
  img.fill(sheet, color: img.ColorRgba8(30, 26, 40, 255));
  var i = 0;
  for (final e in faces.entries) {
    final frames = {'': render(e.value), '_talk': render(e.value, talk: true), if (e.value.canBlink) '_blink': render(e.value, blink: true)};
    for (final fr in frames.entries) {
      File('${out.path}/${e.key}${fr.key}.png').writeAsBytesSync(img.encodePng(fr.value));
    }
    // contact sheet: row group per frame type
    final cx = (i % 5) * 180, cy = (i ~/ 5) * 175 * 3;
    var k = 0;
    for (final fr in [frames['']!, frames['_talk']!, frames['_blink'] ?? frames['']!]) {
      final withTail = fr.clone();
      img.compositeImage(withTail, tailOnly(base));
      img.compositeImage(sheet, withTail, dstX: cx + 4, dstY: cy + k * 175 + 3);
      k++;
    }
    i++;
  }
  File('docs/clover_contact_sheet.png').writeAsBytesSync(img.encodePng(sheet));
  stdout.writeln('wrote ${faces.length} moods');
}
