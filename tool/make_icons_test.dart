// Makes the real app icons (iPhone home screen + Windows exe/taskbar/desktop) from the STAKD app
// icon art (assets/brand/stakd_app_icon_source.webp: purple coins in a rounded pixel frame).
//   $env:ICONS='1'; flutter test tool/make_icons_test.dart
// Windows gets transparent corners (the black outside the purple frame is removed); iPhone gets a
// solid square (iOS rounds the corners itself and doesn't allow see-through icons).
import 'dart:collection';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// The art with the black outside its frame made transparent (flood fill from the edges).
img.Image cutCorners(img.Image src) {
  final im = src.convert(numChannels: 4);
  final w = im.width, h = im.height;
  final seen = List.filled(w * h, false);
  final q = Queue<int>();
  void push(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    final i = y * w + x;
    if (seen[i]) return;
    final p = im.getPixel(x, y);
    if (p.r > 40 || p.g > 40 || p.b > 40) return; // stop at the purple frame
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
  return im;
}

void main() {
  test('make icons', () {
    final src = img.decodeImage(File('assets/brand/stakd_app_icon_source.webp').readAsBytesSync())!;
    final cut = cutCorners(src);
    final square = img.copyResize(cut, width: 1024, height: 1024, interpolation: img.Interpolation.average);

    // iPhone: solid square (corners filled with the icon's own dark background).
    final ios = img.Image(width: 1024, height: 1024, numChannels: 4);
    img.fill(ios, color: img.ColorRgba8(10, 3, 21, 255));
    img.compositeImage(ios, square);
    File('assets/brand/stakd_icon.png').writeAsBytesSync(img.encodePng(ios));
    const dir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    final slots = RegExp(r'Icon-App-([\d.]+)x[\d.]+@(\d)x\.png');
    for (final f in Directory(dir).listSync().whereType<File>()) {
      final m = slots.firstMatch(f.uri.pathSegments.last);
      if (m == null) continue;
      final px = (double.parse(m[1]!) * int.parse(m[2]!)).round();
      final out = img.copyResize(ios, width: px, height: px, interpolation: img.Interpolation.average);
      f.writeAsBytesSync(img.encodePng(out.convert(numChannels: 3))); // no alpha channel for iOS
    }

    // Windows: multi-size .ico with transparent corners, for the exe, taskbar and desktop shortcut.
    final sizes = [16, 24, 32, 48, 64, 128, 256];
    final ico = img.IcoEncoder().encodeImages([
      for (final s in sizes) img.copyResize(square, width: s, height: s, interpolation: img.Interpolation.average),
    ]);
    File('windows/runner/resources/app_icon.ico').writeAsBytesSync(ico);
    // ignore: avoid_print
    print('icons written');
  }, skip: Platform.environment['ICONS'] != '1');
}
