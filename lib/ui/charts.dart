// Minimal charts (CustomPainter). Values are cents; drawing converts to pixels only.
import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../core/money.dart';

class BarChart extends StatelessWidget {
  final List<List<int>> series; // groups: series[s][i]
  final List<Color> colors;
  final List<String> labels;
  const BarChart({super.key, required this.series, required this.colors, required this.labels});
  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _BarPainter(series, colors, labels, Theme.of(context).colorScheme.onSurfaceVariant),
        child: const SizedBox.expand(),
      );
}

class _BarPainter extends CustomPainter {
  final List<List<int>> series;
  final List<Color> colors;
  final List<String> labels;
  final Color text;
  _BarPainter(this.series, this.colors, this.labels, this.text);

  @override
  void paint(Canvas canvas, Size size) {
    if (labels.isEmpty) return;
    final maxV = max(1, series.expand((s) => s).fold<int>(0, max));
    const bottom = 20.0;
    final h = size.height - bottom;
    final groupW = size.width / labels.length;
    final barW = min(18.0, (groupW - 8) / series.length);
    for (var i = 0; i < labels.length; i++) {
      for (var s = 0; s < series.length; s++) {
        final v = series[s][i].clamp(0, maxV);
        final bh = h * v / maxV;
        final x = i * groupW + (groupW - barW * series.length) / 2 + s * barW;
        canvas.drawRRect(
          RRect.fromRectAndCorners(Rect.fromLTWH(x, h - bh, barW - 2, bh), topLeft: const Radius.circular(4), topRight: const Radius.circular(4)),
          Paint()..color = colors[s % colors.length],
        );
      }
      final tp = TextPainter(text: TextSpan(text: labels[i], style: TextStyle(fontSize: 9, color: text)), textDirection: TextDirection.ltr)
        ..layout(maxWidth: groupW);
      tp.paint(canvas, Offset(i * groupW + (groupW - tp.width) / 2, h + 4));
    }
    final tp = TextPainter(text: TextSpan(text: formatCents(maxV), style: TextStyle(fontSize: 9, color: text)), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, Offset.zero);
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => old.series != series;
}

class LineChart extends StatelessWidget {
  final List<List<int>> series;
  final List<Color> colors;
  final List<String> labels;
  const LineChart({super.key, required this.series, required this.colors, required this.labels});
  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _LinePainter(series, colors, labels, Theme.of(context).colorScheme.onSurfaceVariant),
        child: const SizedBox.expand(),
      );
}

class _LinePainter extends CustomPainter {
  final List<List<int>> series;
  final List<Color> colors;
  final List<String> labels;
  final Color text;
  _LinePainter(this.series, this.colors, this.labels, this.text);

  @override
  void paint(Canvas canvas, Size size) {
    final all = series.expand((s) => s).toList();
    if (all.length < 2) return;
    final hi = all.reduce(max), lo = min(0, all.reduce(min));
    final span = max(1, hi - lo);
    const bottom = 18.0;
    final h = size.height - bottom;
    double y(int v) => h - h * (v - lo) / span;
    final n = series.first.length;
    double x(int i) => n == 1 ? 0 : size.width * i / (n - 1);
    // zero line
    canvas.drawLine(Offset(0, y(0)), Offset(size.width, y(0)), Paint()..color = text.withValues(alpha: 0.3));
    for (var s = 0; s < series.length; s++) {
      final path = Path()..moveTo(x(0), y(series[s][0]));
      for (var i = 1; i < series[s].length; i++) {
        path.lineTo(x(i), y(series[s][i]));
      }
      canvas.drawPath(path, Paint()
        ..color = colors[s % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round);
      for (var i = 0; i < series[s].length; i++) {
        canvas.drawCircle(Offset(x(i), y(series[s][i])), 3, Paint()..color = colors[s % colors.length]);
      }
    }
    for (var i = 0; i < labels.length; i += max(1, labels.length ~/ 4)) {
      final tp = TextPainter(text: TextSpan(text: labels[i], style: TextStyle(fontSize: 9, color: text)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset((x(i) - tp.width / 2).clamp(0, size.width - tp.width), h + 4));
    }
    for (final v in [hi, lo]) {
      final tp = TextPainter(text: TextSpan(text: formatCents(v), style: TextStyle(fontSize: 9, color: text)), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, Offset(0, (y(v) - (v == hi ? 0 : tp.height)).clamp(0, h)));
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => true;
}
