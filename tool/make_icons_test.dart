// Makes the real app icons (iPhone home screen + Windows exe/taskbar/desktop) from the STAKD logo:
// the full STAKD logo centered on a deep-purple square.
//   $env:ICONS='1'; flutter test tool/make_icons_test.dart
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

img.Image makeIcon() {
  // The whole logo (Clover + STAKD), already cropped to its edges by make_logo_test.dart.
  final art = img.decodeImage(File('assets/brand/stakd_logo.png').readAsBytesSync())!.convert(numChannels: 4);
  const size = 1024;
  final icon = img.Image(width: size, height: size, numChannels: 4);
  // Deep purple, a little lighter in the middle (opaque: iOS icons can't be see-through).
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final d = sqrt(pow(x - size / 2, 2) + pow(y - size * 0.45, 2)) / (size * 0.72);
      final t = d.clamp(0.0, 1.0);
      icon.setPixelRgba(x, y, (78 - 44 * t).round(), (46 - 28 * t).round(), (140 - 78 * t).round(), 255);
    }
  }
  final w = (size * 0.9).round();
  final scaled = img.copyResize(art, width: w, interpolation: img.Interpolation.average);
  img.compositeImage(icon, scaled, dstX: (size - scaled.width) ~/ 2, dstY: (size - scaled.height) ~/ 2);
  return icon;
}

void main() {
  test('make icons', () {
    final icon = makeIcon();
    File('assets/brand/stakd_icon.png').writeAsBytesSync(img.encodePng(icon));

    // iPhone: overwrite every slot listed in the asset catalog.
    const dir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
    final slots = RegExp(r'Icon-App-([\d.]+)x[\d.]+@(\d)x\.png');
    for (final f in Directory(dir).listSync().whereType<File>()) {
      final m = slots.firstMatch(f.uri.pathSegments.last);
      if (m == null) continue;
      final px = (double.parse(m[1]!) * int.parse(m[2]!)).round();
      final out = img.copyResize(icon, width: px, height: px, interpolation: img.Interpolation.average);
      f.writeAsBytesSync(img.encodePng(out.convert(numChannels: 3))); // no alpha channel for iOS
    }

    // Windows: multi-size .ico for the exe, taskbar and desktop shortcut.
    final sizes = [16, 24, 32, 48, 64, 128, 256];
    final ico = img.IcoEncoder().encodeImages([
      for (final s in sizes) img.copyResize(icon, width: s, height: s, interpolation: img.Interpolation.average),
    ]);
    File('windows/runner/resources/app_icon.ico').writeAsBytesSync(ico);
    // ignore: avoid_print
    print('icons written');
  }, skip: Platform.environment['ICONS'] != '1');
}
