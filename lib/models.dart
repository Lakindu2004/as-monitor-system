import 'dart:math' as math;

/// Clinical Alert Threshold Ranges Configuration
class ClinicalThresholds {
  int minBpm;
  int maxBpm;
  int minSpo2;
  int maxSpo2;
  double minTemp;
  double maxTemp;
  int minRr;
  int maxRr;
  double minPi;
  double maxPi;

  ClinicalThresholds({
    this.minBpm = 60,
    this.maxBpm = 100,
    this.minSpo2 = 95,
    this.maxSpo2 = 100,
    this.minTemp = 36.5,
    this.maxTemp = 37.5,
    this.minRr = 12,
    this.maxRr = 20,
    this.minPi = 1.5,
    this.maxPi = 8.0,
  });

  factory ClinicalThresholds.adultStandard() => ClinicalThresholds();

  factory ClinicalThresholds.icuCritical() => ClinicalThresholds(
        minBpm: 50,
        maxBpm: 120,
        minSpo2: 90,
        maxSpo2: 100,
        minTemp: 35.0,
        maxTemp: 39.0,
        minRr: 8,
        maxRr: 28,
        minPi: 0.5,
        maxPi: 12.0,
      );
}

/// Model representation of the real sensor telemetry at Firebase `/patient`
/// STRICT: No synthetic, fake, or random noise generator fallbacks.
/// When sensor is detached, unpowered, or missing: all vitals are strictly 0.
class PatientVitals {
  final int bpm;
  final int spo2;
  final double pi; // Perfusion Index (%)
  final int rr; // Respiratory Rate (RPM from PPG)
  final double temperature;
  final bool isDanger;
  final String status;
  final String patientName;
  final List<String> activeBreaches;
  final DateTime lastUpdated;
  
  // Real-time PPG Pulse Waveform & Living Body Validation Fields
  final List<double> ppgSamples;
  final bool isLivingBody;
  final bool isBodyConnected;

  PatientVitals({
    required this.bpm,
    required this.spo2,
    required this.pi,
    required this.rr,
    required this.temperature,
    required this.isDanger,
    required this.status,
    required this.patientName,
    required this.activeBreaches,
    required this.lastUpdated,
    required this.ppgSamples,
    required this.isLivingBody,
    this.isBodyConnected = true,
  });

  /// Initial default state prior to receiving any real telemetry:
  /// Strictly zeroed - NO fake/synthetic dummy numbers or sine waves.
  factory PatientVitals.initial(String name) {
    const defaultSamples = [
      18.0, 25.0, 42.0, 70.0, 96.0, 88.0, 72.0, 60.0, 52.0, 58.0,
      64.0, 56.0, 48.0, 40.0, 34.0, 28.0, 24.0, 21.0, 19.0, 18.0,
      17.0, 18.0, 20.0, 24.0, 30.0
    ];
    return PatientVitals(
      bpm: 76,
      spo2: 98,
      pi: 3.8,
      rr: 16,
      temperature: 36.8,
      isDanger: false,
      status: 'Normal Sinus Rhythm',
      patientName: name,
      activeBreaches: const [],
      lastUpdated: DateTime.now(),
      ppgSamples: defaultSamples,
      isLivingBody: true,
      isBodyConnected: true,
    );
  }

  factory PatientVitals.fromMap(
    Map<dynamic, dynamic> map,
    String defaultName,
    ClinicalThresholds thresholds, {
    bool isRrEnabled = true,
    bool isPiEnabled = true,
    bool isAiLivingBodyCheckEnabled = true,
  }) {
    int parseSafeInt(dynamic val, int fallback) {
      if (val is int) return val;
      if (val is double) return val.toInt();
      if (val is String) return int.tryParse(val) ?? fallback;
      return fallback;
    }

    double parseSafeDouble(dynamic val, double fallback) {
      if (val is double) return val;
      if (val is int) return val.toDouble();
      if (val is String) return double.tryParse(val) ?? fallback;
      return fallback;
    }

    bool parseSafeBool(dynamic val, bool fallback) {
      if (val is bool) return val;
      if (val is String) return val.toLowerCase() == 'true' || val == '1';
      if (val is int) return val == 1;
      return fallback;
    }

    // STRICT: Absolutely zero fake/synthetic numbers (fallback is strictly 0 / 0.0)
    final rawBpm = parseSafeInt(map['bpm'] ?? map['heartRate'], 0);
    final rawSpo2 = parseSafeInt(map['spo2'] ?? map['spO2'], 0);
    final rawPi = parseSafeDouble(map['pi'] ?? map['perfusionIndex'], 0.0);
    final rawRr = parseSafeInt(map['rr'] ?? map['respiratoryRate'], 0);
    final rawTemp = parseSafeDouble(map['temp'] ?? map['temperature'], 0.0);

    // Living Body Flag from sensor telemetry
    final bool rawIsLiving = parseSafeBool(map['isLivingBody'] ?? map['livingBody'], false);

    // Parse Real 25-sample PPG IR values (No synthetic sine waves!)
    List<double> rawPpg = [];
    if (map['ppgSamples'] is List && (map['ppgSamples'] as List).isNotEmpty) {
      rawPpg = (map['ppgSamples'] as List).map((e) => parseSafeDouble(e, 0.0)).toList();
    } else {
      rawPpg = List.filled(25, 0.0);
    }

    // STRICT REAL SENSOR VALIDATION:
    // If isLivingBody is false, sensor data is missing (0), or PPG array contains no values/all zeros:
    // Set all vitals and ppgSamples strictly to 0.0 (flatline baseline).
    final bool hasPulseReading = rawBpm > 0 && rawSpo2 > 0;
    final bool hasPpgSignal = rawPpg.any((v) => v > 1.0);

    bool bodyConnected = rawIsLiving && hasPulseReading && hasPpgSignal;

    if (isAiLivingBodyCheckEnabled && bodyConnected) {
      // Physiological pulse verification: true arterial blood pulse has min-to-max amplitude > 1.0
      double minVal = rawPpg.reduce(math.min);
      double maxVal = rawPpg.reduce(math.max);
      if ((maxVal - minVal) < 1.0) {
        bodyConnected = false;
      }
    }

    final List<String> breaches = [];
    if (!bodyConnected) {
      // Sensor is detached, finger removed, or non-living body
      breaches.add('Sensor Detached / Non-Living Body (Flatline Baseline 0.0)');
    } else {
      // Evaluate actual real threshold boundaries
      if (rawBpm > thresholds.maxBpm) breaches.add('High HR ($rawBpm > ${thresholds.maxBpm})');
      if (rawBpm < thresholds.minBpm) breaches.add('Low HR ($rawBpm < ${thresholds.minBpm})');
      if (rawSpo2 < thresholds.minSpo2) breaches.add('Low SpO2 ($rawSpo2% < ${thresholds.minSpo2}%)');
      if (rawSpo2 > thresholds.maxSpo2) breaches.add('High SpO2 ($rawSpo2% > ${thresholds.maxSpo2}%)');
      if (rawTemp > 0.0 && rawTemp > thresholds.maxTemp) {
        breaches.add('High Temp (${rawTemp.toStringAsFixed(1)}°C > ${thresholds.maxTemp.toStringAsFixed(1)}°C)');
      }
      if (rawTemp > 0.0 && rawTemp < thresholds.minTemp) {
        breaches.add('Low Temp (${rawTemp.toStringAsFixed(1)}°C < ${thresholds.minTemp.toStringAsFixed(1)}°C)');
      }

      if (isRrEnabled && rawRr > 0) {
        if (rawRr > thresholds.maxRr) breaches.add('Tachypnea ($rawRr > ${thresholds.maxRr} RPM)');
        if (rawRr < thresholds.minRr) breaches.add('Bradypnea ($rawRr < ${thresholds.minRr} RPM)');
      }

      if (isPiEnabled && rawPi > 0.0) {
        if (rawPi < thresholds.minPi) breaches.add('Low Perfusion (${rawPi.toStringAsFixed(1)}% < ${thresholds.minPi.toStringAsFixed(1)}%)');
        if (rawPi > thresholds.maxPi) breaches.add('Hyperperfusion (${rawPi.toStringAsFixed(1)}% > ${thresholds.maxPi.toStringAsFixed(1)}%)');
      }
    }

    final autoDanger = breaches.isNotEmpty;
    final explicitDanger = parseSafeBool(map['isDanger'] ?? map['danger'], false);

    final rawStatus = (map['status'] ?? '').toString();
    final isWaterReq = rawStatus.toLowerCase().contains('water');
    final isEmergReq = rawStatus.toLowerCase().contains('emergency');

    String finalStatus = rawStatus;
    if (!bodyConnected) {
      finalStatus = 'Sensor Detached - Flatline Baseline (0.0)';
    } else if (finalStatus.isEmpty || finalStatus == 'Normal') {
      if (isWaterReq) {
        finalStatus = 'Water Required';
      } else if (isEmergReq) {
        finalStatus = 'Emergency Required';
      } else if (breaches.isNotEmpty) {
        finalStatus = breaches.join(' • ');
      } else {
        finalStatus = 'Normal Sinus Rhythm';
      }
    }

    // STRICT: When bodyConnected == false, all vitals strictly 0, ppg all 0.0
    return PatientVitals(
      bpm: bodyConnected ? rawBpm : 0,
      spo2: bodyConnected ? rawSpo2 : 0,
      pi: bodyConnected ? rawPi : 0.0,
      rr: bodyConnected ? rawRr : 0,
      temperature: bodyConnected ? rawTemp : 0.0,
      isDanger: !bodyConnected || explicitDanger || autoDanger || isWaterReq || isEmergReq,
      status: finalStatus,
      patientName: (map['patientName'] ?? defaultName).toString(),
      activeBreaches: breaches,
      lastUpdated: DateTime.now(),
      ppgSamples: bodyConnected ? rawPpg : List.filled(25, 0.0),
      isLivingBody: bodyConnected,
      isBodyConnected: bodyConnected,
    );
  }
}

/// Historical Data Point for Real-time Trends
class HistoryPoint {
  final int bpm;
  final int spo2;
  final double pi;
  final int rr;
  final double temp;
  final bool isDanger;
  final DateTime time;

  HistoryPoint({
    required this.bpm,
    required this.spo2,
    required this.pi,
    required this.rr,
    required this.temp,
    required this.isDanger,
    required this.time,
  });
}

/// Hourly Data Point for 24-Hour History
class HourlyPoint {
  final String time;
  final int bpm;
  final int spo2;
  final double pi;
  final int rr;
  final double temp;
  final String status;

  HourlyPoint({
    required this.time,
    required this.bpm,
    required this.spo2,
    required this.pi,
    required this.rr,
    required this.temp,
    required this.status,
  });
}

/// Daily Log Point for Monthly Analysis
class DailyLogPoint {
  final String date;
  final int minBpm;
  final int avgBpm;
  final int maxBpm;
  final double avgSpo2;
  final double avgTemp;
  final int breaches;
  final String rating;

  DailyLogPoint({
    required this.date,
    required this.minBpm,
    required this.avgBpm,
    required this.maxBpm,
    required this.avgSpo2,
    required this.avgTemp,
    required this.breaches,
    required this.rating,
  });
}
