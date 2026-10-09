import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'models.dart';

/// Donut chart painter for patient stability
class StabilityDonutChartPainter extends CustomPainter {
  final int optimalPct;
  final int warningPct;
  final int criticalPct;

  StabilityDonutChartPainter({
    required this.optimalPct,
    required this.warningPct,
    required this.criticalPct,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    const strokeWidth = 14.0;

    final bgPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, bgPaint);

    final total = optimalPct + warningPct + criticalPct;
    if (total == 0) return;

    double startAngle = -math.pi / 2;

    void drawArcSlice(double pct, Color color) {
      if (pct <= 0) return;
      final sweepAngle = (pct / total) * 2 * math.pi;
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        paint,
      );
      startAngle += sweepAngle;
    }

    drawArcSlice(optimalPct.toDouble(), const Color(0xFF10B981));
    drawArcSlice(warningPct.toDouble(), const Color(0xFFF59E0B));
    drawArcSlice(criticalPct.toDouble(), const Color(0xFFFF2E63));
  }

  @override
  bool shouldRepaint(covariant StabilityDonutChartPainter oldDelegate) => true;
}

/// Custom Multi-Trend Chart Painter for Realtime buffer
class MultiTrendChartPainter extends CustomPainter {
  final List<HistoryPoint> history;
  final String metric;
  final bool useFahrenheit;

  MultiTrendChartPainter({
    required this.history,
    required this.metric,
    required this.useFahrenheit,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (history.length < 2) return;

    final gridPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..strokeWidth = 1;

    for (int i = 1; i <= 3; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    List<double> values = history.map((pt) {
      if (metric == 'BPM') return pt.bpm.toDouble();
      if (metric == 'SpO2') return pt.spo2.toDouble();
      if (metric == 'PI') return pt.pi;
      if (metric == 'RR') return pt.rr.toDouble();
      return useFahrenheit ? (pt.temp * 9 / 5) + 32 : pt.temp;
    }).toList();

    double minV = values.reduce(math.min);
    double maxV = values.reduce(math.max);
    if (maxV == minV) maxV += 1;

    Color strokeColor = const Color(0xFF00E5FF);
    if (metric == 'BPM') strokeColor = const Color(0xFFFF2E63);
    if (metric == 'PI') strokeColor = const Color(0xFFA855F7);
    if (metric == 'RR') strokeColor = const Color(0xFF10B981);
    if (metric == 'Temp') strokeColor = const Color(0xFFF59E0B);

    final linePaint = Paint()
      ..color = strokeColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final double stepX = size.width / (values.length - 1);

    for (int i = 0; i < values.length; i++) {
      final normY = 1.0 - ((values[i] - minV) / (maxV - minV)).clamp(0.0, 1.0);
      final x = i * stepX;
      final y = normY * (size.height - 20) + 10;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant MultiTrendChartPainter oldDelegate) => true;
}

/// 24-Hour Timeline Chart Painter
class Timeline24hChartPainter extends CustomPainter {
  final List<HourlyPoint> points;
  final String metric;

  Timeline24hChartPainter({required this.points, required this.metric});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final gridPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..strokeWidth = 1;

    for (int i = 1; i <= 3; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    List<double> values = points.map((pt) {
      if (metric == 'BPM') return pt.bpm.toDouble();
      if (metric == 'SpO2') return pt.spo2.toDouble();
      if (metric == 'PI') return pt.pi;
      if (metric == 'RR') return pt.rr.toDouble();
      return pt.temp;
    }).toList();

    double minV = values.reduce(math.min);
    double maxV = values.reduce(math.max);
    if (maxV == minV) maxV += 1;

    Color color = const Color(0xFF38BDF8);
    if (metric == 'BPM') color = const Color(0xFFFF2E63);
    if (metric == 'PI') color = const Color(0xFFA855F7);
    if (metric == 'RR') color = const Color(0xFF10B981);
    if (metric == 'Temp') color = const Color(0xFFF59E0B);

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    final double stepX = size.width / (values.length - 1);

    for (int i = 0; i < values.length; i++) {
      final normY = 1.0 - ((values[i] - minV) / (maxV - minV)).clamp(0.0, 1.0);
      final x = i * stepX;
      final y = normY * (size.height - 24) + 12;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 3, Paint()..color = color);
    }
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant Timeline24hChartPainter oldDelegate) => true;
}

/// Monthly Compliance 30-Day Chart Painter
class MonthlyComplianceChartPainter extends CustomPainter {
  final List<DailyLogPoint> logs;

  MonthlyComplianceChartPainter({required this.logs});

  @override
  void paint(Canvas canvas, Size size) {
    if (logs.length < 2) return;

    final gridPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..strokeWidth = 1;

    for (int i = 1; i <= 3; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final double stepX = size.width / (logs.length - 1);

    final bandPath = Path();
    for (int i = 0; i < logs.length; i++) {
      final yMax = (1.0 - ((logs[i].maxBpm - 50) / 100).clamp(0.0, 1.0)) * (size.height - 24) + 12;
      if (i == 0) bandPath.moveTo(i * stepX, yMax);
      else bandPath.lineTo(i * stepX, yMax);
    }
    for (int i = logs.length - 1; i >= 0; i--) {
      final yMin = (1.0 - ((logs[i].minBpm - 50) / 100).clamp(0.0, 1.0)) * (size.height - 24) + 12;
      bandPath.lineTo(i * stepX, yMin);
    }
    bandPath.close();
    canvas.drawPath(bandPath, Paint()..color = const Color(0xFF00E5FF).withOpacity(0.08));

    final avgPath = Path();
    for (int i = 0; i < logs.length; i++) {
      final y = (1.0 - ((logs[i].avgBpm - 50) / 100).clamp(0.0, 1.0)) * (size.height - 24) + 12;
      if (i == 0) avgPath.moveTo(i * stepX, y);
      else avgPath.lineTo(i * stepX, y);
    }
    canvas.drawPath(avgPath, Paint()..color = const Color(0xFF10B981)..strokeWidth = 2.5..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(covariant MonthlyComplianceChartPainter oldDelegate) => true;
}

/// Realtime ECG Waveform Painter (Legacy monitor wave)
class EcWaveformPainter extends CustomPainter {
  final double progress;
  final bool isDanger;

  EcWaveformPainter({required this.progress, required this.isDanger});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = isDanger ? const Color(0xFFFF2E63) : const Color(0xFF00E5FF)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final double midY = size.height / 2;
    const int pts = 70;
    final double step = size.width / pts;

    for (int i = 0; i <= pts; i++) {
      final x = i * step;
      final norm = ((i / pts) + progress) % 1.0;
      double y = midY;

      if (norm > 0.40 && norm < 0.44) {
        y -= size.height * 0.18;
      } else if (norm >= 0.44 && norm < 0.47) {
        y += size.height * 0.12;
      } else if (norm >= 0.47 && norm < 0.52) {
        y -= size.height * 0.45;
      } else if (norm >= 0.52 && norm < 0.56) {
        y += size.height * 0.22;
      } else if (norm >= 0.56 && norm < 0.65) {
        y -= size.height * 0.22;
      }

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant EcWaveformPainter oldDelegate) => true;
}

/// =========================================================================
/// NEW COMPONENT: Real-time PPG Waveform Line Chart (MAX30102 IR Waveform)
/// =========================================================================
/// - Renders 25 numerical IR samples received every second from Firebase
/// - Cubic Bezier / Smooth Curve interpolation (tension ~0.4)
/// - Neon Green (#00E676) glowing continuous stroke (no dots/points)
/// - Dark-mode ICU bedside pulse monitor grid
/// - Smooth flatline to 0 when isLivingBody is false
/// =========================================================================
/// =========================================================================
/// REAL-TIME PPG WAVEFORM LINE CHART (5-Second Continuous ICU Monitor Sweep)
/// =========================================================================
/// - Holds rolling 5-second PPG display buffer (up to 125 continuous sample points)
/// - Appends new 25-sample batch every 1s from Firebase and discards oldest 25
/// - Cubic Bezier / Smooth Curve interpolation (tension ~0.4)
/// - Neon Green (#00E676) glowing continuous stroke (no dots/points)
/// - 5-Second Hospital ICU Bedside grid with 1-second interval vertical markers
/// - Flatline baseline at 0.0 when isLivingBody is false
/// =========================================================================

/// =========================================================================
/// REAL-TIME ICU PPG WAVEFORM PAINTER (BEDSIDE SWEEP BAR & CUBIC BEZIER SMOOTHING)
/// =========================================================================
/// Features:
/// 1. Real Data Array: Renders the actual 25-sample/125-sample IR data array from index 0
/// 2. Cubic Bezier Smoothing: Smooth medical pulse curve with tension 0.4 (showDots: false)
/// 3. ICU Bedside Continuous Sweep Bar: Erases leading gap ahead of scan line
/// 4. Strict Living Body Check: Smooth flatline baseline at 0.0 when isLivingBody is false
/// 5. Neon Green (#00E676) glowing trace with gradient fill
/// =========================================================================
class PpgWaveformPainter extends CustomPainter {
  final List<double> samples;
  final bool isLivingBody;
  final bool isCurveSmoothed;
  final Color lineColor;
  final double sweepProgress;
  final int bpm;
  final double beatPhase;

  PpgWaveformPainter({
    required this.samples,
    required this.isLivingBody,
    this.isCurveSmoothed = true,
    this.lineColor = const Color(0xFF00E676), // Neon Green ICU pulse
    this.sweepProgress = 0.0,
    this.bpm = 75,
    this.beatPhase = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Dark-Mode ICU Monitor Medical Grid (5-Second Time Domain)
    final gridPaint = Paint()
      ..color = const Color(0xFF1E293B).withOpacity(0.55)
      ..strokeWidth = 1.0;

    final subGridPaint = Paint()
      ..color = const Color(0xFF1E293B).withOpacity(0.25)
      ..strokeWidth = 0.5;

    // Horizontal amplitude lines (4 divisions)
    for (int i = 1; i <= 4; i++) {
      final y = size.height * (i / 5.0);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Vertical time grid lines (5 major 1-second divisions across 5s window)
    for (int i = 1; i <= 5; i++) {
      final x = size.width * (i / 5.0);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);

      // Subdivisions (every 200ms = 5 intervals per second)
      for (int sub = 1; sub < 5; sub++) {
        final subX = (i - 1 + sub / 5.0) * (size.width / 5.0);
        canvas.drawLine(Offset(subX, 0), Offset(subX, size.height), subGridPaint);
      }
    }

    // Baseline indicator
    final baselineY = size.height - 8.0;
    final bool allZero = samples.isEmpty || samples.every((v) => v <= 0.05);

    // 2. Fallback: If not a living body, sensor detached, or empty/zeroed samples -> drop wave flatline at 0.0
    if (!isLivingBody || bpm <= 0 || allZero) {
      final flatPaint = Paint()
        ..color = const Color(0xFFFF2E63).withOpacity(0.95) // Red flatline
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final flatPath = Path();
      flatPath.moveTo(0, baselineY);
      flatPath.lineTo(size.width, baselineY);
      canvas.drawPath(flatPath, flatPaint);

      // Warning text on canvas
      final textPainter = TextPainter(
        text: const TextSpan(
          text: '--- SENSOR DETACHED / FLATLINE BASELINE 0.0 ---',
          style: TextStyle(
            color: Color(0xFFFF2E63),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.4,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset((size.width - textPainter.width) / 2, size.height / 2 - 6),
      );
      return;
    }

    // 3. Render Real Incoming IR Samples Array (flowing from index 0 across the canvas)
    final int count = samples.length;
    double minV = samples.reduce(math.min);
    double maxV = samples.reduce(math.max);
    if ((maxV - minV) < 1.0) {
      maxV = minV + 1.0;
    }

    final double stepX = count > 1 ? size.width / (count - 1) : size.width;
    final List<Offset> points = [];

    for (int i = 0; i < count; i++) {
      final normY = 1.0 - ((samples[i] - minV) / (maxV - minV)).clamp(0.0, 1.0);
      final x = i * stepX;
      // Reserve top 10px and bottom 12px margin for medical amplitude headroom
      final y = normY * (size.height - 26.0) + 12.0;
      points.add(Offset(x, y));
    }

    // 4. Sweep Bar Cursor & Leading Erase Gap Parameters
    final double curSweep = (sweepProgress % 1.0 + 1.0) % 1.0;
    final double cursorX = curSweep * size.width;
    final double gapWidth = size.width * 0.06; // 6% leading erase gap ahead of scan line
    final double eraseStart = cursorX;
    final double eraseEnd = cursorX + gapWidth;

    // Partition points into Fresh Pass (behind cursor) and Previous Pass (ahead of gap)
    final List<Offset> freshPoints = [];
    final List<Offset> oldPoints = [];

    for (int i = 0; i < points.length; i++) {
      final pt = points[i];
      bool inGap = false;
      bool isFresh = false;
      bool isOld = false;

      if (eraseEnd <= size.width) {
        inGap = (pt.dx >= eraseStart && pt.dx <= eraseEnd);
        isFresh = (pt.dx < eraseStart);
        isOld = (pt.dx > eraseEnd);
      } else {
        final double wrappedEnd = eraseEnd - size.width;
        inGap = (pt.dx >= eraseStart || pt.dx <= wrappedEnd);
        isFresh = (pt.dx > wrappedEnd && pt.dx < eraseStart);
        isOld = false;
      }

      if (!inGap) {
        if (isFresh) {
          freshPoints.add(pt);
        } else if (isOld) {
          oldPoints.add(pt);
        }
      }
    }

    // Path builder using Catmull-Rom to Cubic Bezier spline with exact tension 0.4
    Path createCubicPath(List<Offset> pts, bool smoothed) {
      final path = Path();
      if (pts.isEmpty) return path;
      path.moveTo(pts[0].dx, pts[0].dy);

      if (smoothed && pts.length > 2) {
        const double tension = 0.4;
        for (int i = 0; i < pts.length - 1; i++) {
          final p0 = i > 0 ? pts[i - 1] : pts[i];
          final p1 = pts[i];
          final p2 = pts[i + 1];
          final p3 = i < pts.length - 2 ? pts[i + 2] : p2;

          final cp1x = p1.dx + (p2.dx - p0.dx) * tension * 0.5;
          final cp1y = p1.dy + (p2.dy - p0.dy) * tension * 0.5;
          final cp2x = p2.dx - (p3.dx - p1.dx) * tension * 0.5;
          final cp2y = p2.dy - (p3.dy - p1.dy) * tension * 0.5;

          path.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
        }
      } else {
        for (int i = 1; i < pts.length; i++) {
          path.lineTo(pts[i].dx, pts[i].dy);
        }
      }
      return path;
    }

    // 5. Draw Previous Pass ahead of erase gap (ICU phosphor decay effect)
    if (oldPoints.length > 1) {
      final oldPath = createCubicPath(oldPoints, isCurveSmoothed);
      final oldStrokePaint = Paint()
        ..color = lineColor.withOpacity(0.28)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(oldPath, oldStrokePaint);
    }

    // 6. Draw Fresh Wave behind cursor (Glowing Neon Green trace with gradient fill)
    if (freshPoints.length > 1) {
      final freshPath = createCubicPath(freshPoints, isCurveSmoothed);

      // Gradient Fill under curve
      final fillPath = Path.from(freshPath)
        ..lineTo(freshPoints.last.dx, size.height)
        ..lineTo(freshPoints.first.dx, size.height)
        ..close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            lineColor.withOpacity(0.22),
            lineColor.withOpacity(0.03),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
        ..style = PaintingStyle.fill;
      canvas.drawPath(fillPath, fillPaint);

      // Wide Glow Stroke Layer
      final glowPaint = Paint()
        ..color = lineColor.withOpacity(0.38)
        ..strokeWidth = 4.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(freshPath, glowPaint);

      // Core Sharp Neon Green Line (pointRadius: 0 / showDots: false)
      final corePaint = Paint()
        ..color = lineColor
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(freshPath, corePaint);
    }

    // 7. Draw Hospital ICU Bedside Sweep Bar & Luminous Head Dot
    double cursorY = size.height / 2;
    if (points.isNotEmpty) {
      final int relIdx = ((cursorX / size.width) * (points.length - 1)).clamp(0, points.length - 1).toInt();
      cursorY = points[relIdx].dy;
    }

    // Scanning Beam Line (Vertical cyan/green accent line)
    final beamPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF00E5FF).withOpacity(0.10),
          const Color(0xFF00E5FF).withOpacity(0.70),
          const Color(0xFF00E5FF).withOpacity(0.10),
        ],
      ).createShader(Rect.fromLTWH(cursorX - 0.75, 0, 1.5, size.height))
      ..strokeWidth = 1.2;
    canvas.drawLine(Offset(cursorX, 4), Offset(cursorX, size.height - 4), beamPaint);

    // Glowing Cursor Head Dot
    final outerGlowPaint = Paint()
      ..color = lineColor.withOpacity(0.45)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cursorX, cursorY), 5.5, outerGlowPaint);

    final innerCorePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cursorX, cursorY), 2.5, innerCorePaint);
  }

  @override
  bool shouldRepaint(covariant PpgWaveformPainter oldDelegate) => true;
}

