// Dev tool: estimates Clover's art-pixel size and prints the native grid as characters.
import 'dart:io';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  final src = img.decodePng(File('assets/clover/clover_base.png').readAsBytesSync())!;
  final cell = args.isNotEmpty ? double.parse(args[0]) : 8.0;
  final ox = args.length > 1 ? double.parse(args[1]) : 0.0, oy = args.length > 2 ? double.parse(args[2]) : 0.0;
  final cols = ((src.width - ox) / cell).ceil(), rows = ((src.height - oy) / cell).ceil();
  stdout.writeln('size ${src.width}x${src.height} grid ${cols}x$rows');
  final palette = <String, String>{};
  for (var r = 0; r < rows; r++) {
    final sb = StringBuffer();
    for (var c = 0; c < cols; c++) {
      final x = (ox + (c + 0.5) * cell).floor().clamp(0, src.width - 1), y = (oy + (r + 0.5) * cell).floor().clamp(0, src.height - 1);
      final p = src.getPixel(x, y);
      if (p.a < 128) {
        sb.write('.');
        continue;
      }
      final lum = (p.r * 0.3 + p.g * 0.59 + p.b * 0.11);
      final ch = lum > 200 ? 'W' : lum > 150 ? 'L' : lum > 95 ? 'G' : lum > 55 ? 'd' : 'K';
      palette[ch] = '${p.r},${p.g},${p.b}';
      sb.write(ch);
    }
    stdout.writeln(sb);
  }
  stdout.writeln(palette);
}
