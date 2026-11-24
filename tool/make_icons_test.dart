// Makes the real app icons (iPhone home screen + Windows exe/taskbar/desktop) from the STAKD app
// icon art (assets/brand/stakd_app_icon_source.webp: purple coins in a rounded pixel frame).
//   $env:ICONS='1'; flutter test tool/make_icons_test.dart
// Windows gets transparent corners (the black outside the purple frame is removed); iPhone gets a
// solid square (iOS rounds the corners itself and doesn't allow see-through icons).
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

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

/// Standard .ico: one PNG-compressed 32-bit image per size, with the header fields Windows Explorer
/// expects (planes 1, 32 bits per pixel, 0 meaning 256 px). Explorer showed a blank icon otherwise.
List<int> writeIco(List<img.Image> images) {
  // Classic 32-bit bitmaps (BGRA, bottom-up, plus an all-zero AND mask): the desktop and taskbar showed a
  // blank icon with PNG-compressed entries on this PC.
  List<int> dib(img.Image i) {
    final w = i.width, h = i.height;
    final b = BytesBuilder();
    void le(int v, int n) => b.add([for (var k = 0; k < n; k++) (v >> (8 * k)) & 0xff]);
    le(40, 4); // BITMAPINFOHEADER size
    le(w, 4);
    le(h * 2, 4); // colour rows + mask rows
    le(1, 2); // planes
    le(32, 2); // bits per pixel
    le(0, 4); // no compression
    le(w * h * 4, 4);
    le(0, 4);
    le(0, 4);
    le(0, 4);
    le(0, 4);
    for (var y = h - 1; y >= 0; y--) {
      for (var x = 0; x < w; x++) {
        final p = i.getPixel(x, y);
        b.add([p.b.toInt(), p.g.toInt(), p.r.toInt(), p.a.toInt()]);
      }
    }
    final maskRow = ((w + 31) ~/ 32) * 4;
    b.add(List.filled(maskRow * h, 0));
    return b.takeBytes();
  }

  final pngs = [for (final i in images) dib(i.convert(numChannels: 4))]; // classic bitmaps at every size (PNG entries showed blank)
  final out = BytesBuilder();
  void u16(int v) => out.add([v & 0xff, (v >> 8) & 0xff]);
  void u32(int v) => out.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
  u16(0); // reserved
  u16(1); // type: icon
  u16(images.length);
  var offset = 6 + 16 * images.length;
  for (var k = 0; k < images.length; k++) {
    final w = images[k].width, h = images[k].height;
    out.add([w >= 256 ? 0 : w, h >= 256 ? 0 : h, 0, 0]); // width, height, colors, reserved
    u16(1); // planes
    u16(32); // bits per pixel
    u32(pngs[k].length);
    u32(offset);
    offset += pngs[k].length;
  }
  for (final p in pngs) {
    out.add(p);
  }
  return out.takeBytes();
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
    File('windows/runner/resources/app_icon.ico').writeAsBytesSync(writeIco([
      for (final s in sizes) img.copyResize(square, width: s, height: s, interpolation: img.Interpolation.average),
    ]));
    // ignore: avoid_print
    print('icons written');
  }, skip: Platform.environment['ICONS'] != '1');
}
