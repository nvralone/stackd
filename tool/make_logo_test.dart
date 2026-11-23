// Turns the STAKD logo (white background) into a transparent, tightly cropped PNG for the app.
//   $env:LOGO='1'; flutter test tool/make_logo_test.dart
// The white around the logo is removed by flood-filling from the image edges, so white INSIDE the
// black outline (letters, raccoon face) stays white.
import 'dart:collection';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('make logo', () {
    final src = img.decodeImage(File('assets/brand/stakd_logo_source.webp').readAsBytesSync())!;
    final im = src.convert(numChannels: 4);
    final w = im.width, h = im.height;
    bool light(int x, int y) {
      final p = im.getPixel(x, y);
      return p.r > 225 && p.g > 225 && p.b > 225;
    }

    final seen = List.filled(w * h, false);
    final q = Queue<int>();
    void push(int x, int y) {
      if (x < 0 || y < 0 || x >= w || y >= h) return;
      final i = y * w + x;
      if (seen[i] || !light(x, y)) return;
      seen[i] = true;
      q.add(i);
    }

    for (var x = 0; x < w; x++) {
      push(x, 0);
      push(x, h - 1);
    }
    for (var y = 0; y < h; y++) {
      push(0, y);
      push(w - 1, y);
    }
    while (q.isNotEmpty) {
      final i = q.removeFirst();
      final x = i % w, y = i ~/ w;
      im.setPixelRgba(x, y, 0, 0, 0, 0);
      push(x + 1, y);
      push(x - 1, y);
      push(x, y + 1);
      push(x, y - 1);
    }
    // Soften the leftover light fringe next to the transparent area.
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = im.getPixel(x, y);
        if (p.a == 0) continue;
        var nearClear = false;
        for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final nx = x + dx, ny = y + dy;
          if (nx >= 0 && ny >= 0 && nx < w && ny < h && im.getPixel(nx, ny).a == 0) nearClear = true;
        }
        if (nearClear && p.r > 180 && p.g > 180 && p.b > 180) im.setPixelRgba(x, y, p.r, p.g, p.b, 90);
      }
    }
    // Crop to the logo.
    var minX = w, minY = h, maxX = 0, maxY = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (im.getPixel(x, y).a > 40) { // ignore near-invisible stray pixels
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    final cropped = img.copyCrop(im, x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1);
    final out = cropped.width > 900 ? img.copyResize(cropped, width: 900, interpolation: img.Interpolation.average) : cropped;
    File('assets/brand/stakd_logo.png').writeAsBytesSync(img.encodePng(out));
    // ignore: avoid_print
    print('source ${w}x$h -> logo ${out.width}x${out.height}');
  }, skip: Platform.environment['LOGO'] != '1');
}
