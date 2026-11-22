// One-off asset tool: turns the supplied Clover reference into a transparent sprite.
// Removes the background card and the "12" label, keeps Clover's pixels untouched.
// Run: dart run tool/crop_clover.dart
import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final src = img.decodeWebP(File('assets/clover/reference.webp').readAsBytesSync())!;
  final w = src.width, h = src.height;
  final bg = src.getPixel(w - 4, h - 4);
  bool isBg(img.Pixel p) =>
      (p.r - bg.r).abs() + (p.g - bg.g).abs() + (p.b - bg.b).abs() < 70;

  // Flood fill background from the border.
  final clear = List.filled(w * h, false);
  final stack = <int>[];
  for (var x = 0; x < w; x++) { stack..add(x)..add((h - 1) * w + x); }
  for (var y = 0; y < h; y++) { stack..add(y * w)..add(y * w + w - 1); }
  while (stack.isNotEmpty) {
    final i = stack.removeLast();
    if (clear[i]) continue;
    final x = i % w, y = i ~/ w;
    if (!isBg(src.getPixel(x, y))) continue;
    clear[i] = true;
    if (x > 0) stack.add(i - 1);
    if (x < w - 1) stack.add(i + 1);
    if (y > 0) stack.add(i - w);
    if (y < h - 1) stack.add(i + w);
  }

  // Connected components of what remains; keep the big ones (body, tail), drop label + spark marks.
  final comp = List.filled(w * h, -1);
  final sizes = <int>[];
  for (var s = 0; s < w * h; s++) {
    if (clear[s] || comp[s] >= 0) continue;
    final id = sizes.length;
    var n = 0;
    final q = [s];
    comp[s] = id;
    while (q.isNotEmpty) {
      final i = q.removeLast();
      n++;
      final x = i % w, y = i ~/ w;
      for (final j in [if (x > 0) i - 1, if (x < w - 1) i + 1, if (y > 0) i - w, if (y < h - 1) i + w]) {
        if (!clear[j] && comp[j] < 0) { comp[j] = id; q.add(j); }
      }
    }
    sizes.add(n);
  }
  final biggest = sizes.reduce((a, b) => a > b ? a : b);
  final keep = {for (var i = 0; i < sizes.length; i++) if (sizes[i] > biggest * 0.04) i};

  var minX = w, minY = h, maxX = 0, maxY = 0;
  for (var i = 0; i < w * h; i++) {
    if (comp[i] >= 0 && keep.contains(comp[i])) {
      final x = i % w, y = i ~/ w;
      if (x < minX) minX = x; if (x > maxX) maxX = x;
      if (y < minY) minY = y; if (y > maxY) maxY = y;
    }
  }
  final out = img.Image(width: maxX - minX + 1, height: maxY - minY + 1, numChannels: 4);
  for (var y = minY; y <= maxY; y++) {
    for (var x = minX; x <= maxX; x++) {
      final i = y * w + x;
      if (comp[i] >= 0 && keep.contains(comp[i])) {
        final p = src.getPixel(x, y);
        out.setPixelRgba(x - minX, y - minY, p.r, p.g, p.b, 255);
      }
    }
  }
  File('assets/clover/clover_base.png').writeAsBytesSync(img.encodePng(out));
  stdout.writeln('components=${sizes.length} kept=${keep.length} size=${out.width}x${out.height}');
}
