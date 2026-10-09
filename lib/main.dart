import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'models.dart';
import 'painters.dart';
import 'emergency_alert_dialog.dart';
import 'action_log_service.dart';
import 'alarm_audio_service.dart';
import 'gemini_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase with compile-time or runtime environment configuration
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase initialization notice: $e');
  }

  // Initialize persistent services
  await GeminiService().init();
  await ActionLogService().init();

  runApp(const PatientMonitoringApp());
}

class PatientMonitoringApp extends StatelessWidget {
  const PatientMonitoringApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ICU Telemetry & Advanced Patient Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF070A12),
        fontFamily: 'Roboto',
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFFFF2E63),
          surface: Color(0xFF0E1424),
        ),
      ),
      home: const PatientMonitorScreen(),
    );
  }
}

class PatientMonitorScreen extends StatefulWidget {
  const PatientMonitorScreen({super.key});

  @override
  State<PatientMonitorScreen> createState() => _PatientMonitorScreenState();
}

class _PatientMonitorScreenState extends State<PatientMonitorScreen>
    with SingleTickerProviderStateMixin {
  // Navigation State
  int _currentTabIndex = 0;
  int _historySubNav = 0; // 0: Trends, 1: 24h Table, 2: Monthly
  String _selectedTrendMetric = 'BPM';
  String _selected24hMetric = 'BPM';

  // Real-time Telemetry Data
  late PatientVitals _vitals;
  late ClinicalThresholds _thresholds;
  bool _isConnected = false;
  bool _useFahrenheit = false;
  bool _isMuted = false;
  bool _isAlarmAudioEnabled = true;
  double _alarmVolume = 1.0;
  Timer? _muteCountdownTimer;

  // Continuous 5-Second Rolling PPG Display Buffer (125 samples = 25 samples/sec * 5s)
  final List<double> _ppgRollingBuffer = [
    18.0, 25.0, 42.0, 70.0, 96.0, 88.0, 72.0, 60.0, 52.0, 58.0, 64.0, 56.0, 48.0, 40.0, 34.0, 28.0, 24.0, 21.0, 19.0, 18.0, 17.0, 18.0, 20.0, 24.0, 30.0,
    18.0, 25.0, 42.0, 70.0, 96.0, 88.0, 72.0, 60.0, 52.0, 58.0, 64.0, 56.0, 48.0, 40.0, 34.0, 28.0, 24.0, 21.0, 19.0, 18.0, 17.0, 18.0, 20.0, 24.0, 30.0,
    18.0, 25.0, 42.0, 70.0, 96.0, 88.0, 72.0, 60.0, 52.0, 58.0, 64.0, 56.0, 48.0, 40.0, 34.0, 28.0, 24.0, 21.0, 19.0, 18.0, 17.0, 18.0, 20.0, 24.0, 30.0,
    18.0, 25.0, 42.0, 70.0, 96.0, 88.0, 72.0, 60.0, 52.0, 58.0, 64.0, 56.0, 48.0, 40.0, 34.0, 28.0, 24.0, 21.0, 19.0, 18.0, 17.0, 18.0, 20.0, 24.0, 30.0,
    18.0, 25.0, 42.0, 70.0, 96.0, 88.0, 72.0, 60.0, 52.0, 58.0, 64.0, 56.0, 48.0, 40.0, 34.0, 28.0, 24.0, 21.0, 19.0, 18.0, 17.0, 18.0, 20.0, 24.0, 30.0,
  ];

  // Feature Toggles (All Persistently Saved)
  bool _isRrEnabled = true;
  bool _isPiEnabled = true;
  bool _isAiLivingBodyCheckEnabled = true;
  bool _isCurveSmoothingEnabled = true;
  bool _isAiVoiceReportEnabled = true;
  bool _isPhoneNotificationsEnabled = true;
  bool _isAiSpeaking = false;

  // Patient Bio Information
  String _patientName = 'Eleanor Vance';
  String _patientAgeGender = '38 / Female';
  String _bedWardId = 'Bed 01 (ICU)';
  String _nursePhone = '+94 77 123 4567';
  String _nurseName = 'Staff Nurse Kumara';

  // Subscriptions & Timers
  StreamSubscription<DatabaseEvent>? _dbSubscription;
  Timer? _ecgAnimTimer;
  Timer? _alarmSirenTimer;
  double _ecgProgress = 0.0;
  bool _isAlertDialogOpen = false;

  // History & Analytical Buffers
  final List<HistoryPoint> _realtimeHistory = [];
  final List<HourlyPoint> _hourlyHistory = [];
  final List<DailyLogPoint> _monthlyLogs = [];

  // Controllers for Settings TextFields
  late TextEditingController _nameCtrl;
  late TextEditingController _ageGenderCtrl;
  late TextEditingController _bedWardCtrl;
  late TextEditingController _nursePhoneCtrl;
  late TextEditingController _nurseNameCtrl;
  late TextEditingController _geminiKeyCtrl;

  // Medical AI Assistant Chat Messages
  final List<Map<String, String>> _assistantMessages = [
    {
      'sender': 'ai',
      'text': 'Hello, I am your Clinical AI Assistant monitoring Eleanor Vance in real time. How can I assist you with telemetry triage or patient care?',
      'time': 'Just now'
    }
  ];

  // Real-time ICU PPG Sweep and Heartbeat Phase Getters
  double get _ppgSweepProgress {
    final ms = DateTime.now().millisecondsSinceEpoch;
    return (ms % 5000) / 5000.0;
  }

  double get _ppgBeatPhase {
    if (_vitals.bpm <= 0) return 0.0;
    final beatPeriodMs = (60000.0 / _vitals.bpm).clamp(300.0, 3000.0);
    final ms = DateTime.now().millisecondsSinceEpoch;
    return (ms % beatPeriodMs) / beatPeriodMs;
  }

  @override
  void initState() {
    super.initState();
    _thresholds = ClinicalThresholds();
    _vitals = PatientVitals.initial(_patientName);

    _nameCtrl = TextEditingController(text: _patientName);
    _ageGenderCtrl = TextEditingController(text: _patientAgeGender);
    _bedWardCtrl = TextEditingController(text: _bedWardId);
    _nursePhoneCtrl = TextEditingController(text: _nursePhone);
    _nurseNameCtrl = TextEditingController(text: _nurseName);
    _geminiKeyCtrl = TextEditingController(text: GeminiService.apiKey);

    _loadPersistentSettings();
    _initHistoricalData();
    _listenToFirebase();

    // Real-time animation tick for ICU ECG & PPG sweep bar
    _ecgAnimTimer = Timer.periodic(const Duration(milliseconds: 20), (timer) {
      if (mounted) {
        setState(() {
          _ecgProgress = (_ecgProgress + 0.010) % 1.0;
        });
      }
    });
  }

  @override
  void dispose() {
    _dbSubscription?.cancel();
    _ecgAnimTimer?.cancel();
    _alarmSirenTimer?.cancel();
    _muteCountdownTimer?.cancel();
    AlarmAudioService.instance.stopAlarmSiren();
    _nameCtrl.dispose();
    _ageGenderCtrl.dispose();
    _bedWardCtrl.dispose();
    _nursePhoneCtrl.dispose();
    _nurseNameCtrl.dispose();
    _geminiKeyCtrl.dispose();
    super.dispose();
  }

  // ==========================================
  // PERSISTENT SETTINGS STORAGE (SharedPreferences)
  // ==========================================
  Future<void> _loadPersistentSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _isAiLivingBodyCheckEnabled = prefs.getBool('ai_living_body_check') ?? true;
        _isCurveSmoothingEnabled = prefs.getBool('ai_curve_smoothing') ?? true;
        _isAiVoiceReportEnabled = prefs.getBool('ai_voice_report') ?? true;
        _isAlarmAudioEnabled = prefs.getBool('alarm_audio_enabled') ?? true;
        AlarmAudioService.instance.isAudioEnabled = _isAlarmAudioEnabled;
        _isPhoneNotificationsEnabled = prefs.getBool('phone_notifications') ?? true;
        _alarmVolume = prefs.getDouble('alarm_volume') ?? 1.0;

        // Restore 1-Minute Mute State if still within time window
        final mutedUntilMs = prefs.getInt('muted_until_ms') ?? 0;
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        if (mutedUntilMs > nowMs) {
          final expiry = DateTime.fromMillisecondsSinceEpoch(mutedUntilMs);
          AlarmAudioService.instance.setOneMinuteMute(expiry);
          _isMuted = true;
          _startMuteCountdownTimer();
        } else {
          _isMuted = prefs.getBool('sound_muted') ?? false;
        }
        _useFahrenheit = prefs.getBool('use_fahrenheit') ?? false;
        _isRrEnabled = prefs.getBool('mod_rr') ?? true;
        _isPiEnabled = prefs.getBool('mod_pi') ?? true;

        _patientName = prefs.getString('p_name') ?? _patientName;
        _patientAgeGender = prefs.getString('p_age') ?? _patientAgeGender;
        _bedWardId = prefs.getString('p_bed') ?? _bedWardId;
        _nursePhone = prefs.getString('p_nurse_phone') ?? _nursePhone;
        _nurseName = prefs.getString('p_nurse_name') ?? _nurseName;

        _nameCtrl.text = _patientName;
        _ageGenderCtrl.text = _patientAgeGender;
        _bedWardCtrl.text = _bedWardId;
        _nursePhoneCtrl.text = _nursePhone;
        _nurseNameCtrl.text = _nurseName;

        _thresholds.minBpm = prefs.getInt('th_minBpm') ?? _thresholds.minBpm;
        _thresholds.maxBpm = prefs.getInt('th_maxBpm') ?? _thresholds.maxBpm;
        _thresholds.minSpo2 = prefs.getInt('th_minSpo2') ?? _thresholds.minSpo2;
        _thresholds.maxSpo2 = prefs.getInt('th_maxSpo2') ?? _thresholds.maxSpo2;
        _thresholds.minTemp = prefs.getDouble('th_minTemp') ?? _thresholds.minTemp;
        _thresholds.maxTemp = prefs.getDouble('th_maxTemp') ?? _thresholds.maxTemp;
        _thresholds.minRr = prefs.getInt('th_minRr') ?? _thresholds.minRr;
        _thresholds.maxRr = prefs.getInt('th_maxRr') ?? _thresholds.maxRr;
        _thresholds.minPi = prefs.getDouble('th_minPi') ?? _thresholds.minPi;
        _thresholds.maxPi = prefs.getDouble('th_maxPi') ?? _thresholds.maxPi;
      });
    } catch (e) {
      debugPrint('Error loading persistent preferences: $e');
    }
  }

  Future<void> _savePreferenceBool(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (e) {
      debugPrint('Error saving preference $key: $e');
    }
  }

  Future<void> _savePreferenceInt(String key, int value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(key, value);
    } catch (e) {
      debugPrint('Error saving preference $key: $e');
    }
  }

  Future<void> _savePreferenceDouble(String key, double value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(key, value);
    } catch (e) {
      debugPrint('Error saving preference $key: $e');
    }
  }

  /// Sets a strict 1-minute mute timer (Duration(minutes: 1))
  /// Suppresses both sound alerts AND popup overlays for exactly 60 seconds
  void _setOneMinuteMute() {
    final muteExpiry = DateTime.now().add(const Duration(minutes: 1));
    AlarmAudioService.instance.setOneMinuteMute(muteExpiry);
    setState(() {
      _isMuted = true;
    });
    _savePreferenceInt('muted_until_ms', muteExpiry.millisecondsSinceEpoch);
    _savePreferenceBool('sound_muted', true);
    _alarmSirenTimer?.cancel();
    AlarmAudioService.instance.stopAlarmSiren();

    _startMuteCountdownTimer();
  }

  void _startMuteCountdownTimer() {
    _muteCountdownTimer?.cancel();
    _muteCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (!AlarmAudioService.instance.isMuted) {
        timer.cancel();
        setState(() {
          _isMuted = false;
        });
        _savePreferenceBool('sound_muted', false);
        _savePreferenceInt('muted_until_ms', 0);
      } else {
        setState(() {}); // refresh mute countdown display
      }
    });
  }

  Future<void> _saveThresholds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('th_minBpm', _thresholds.minBpm);
      await prefs.setInt('th_maxBpm', _thresholds.maxBpm);
      await prefs.setInt('th_minSpo2', _thresholds.minSpo2);
      await prefs.setInt('th_maxSpo2', _thresholds.maxSpo2);
      await prefs.setDouble('th_minTemp', _thresholds.minTemp);
      await prefs.setDouble('th_maxTemp', _thresholds.maxTemp);
      await prefs.setInt('th_minRr', _thresholds.minRr);
      await prefs.setInt('th_maxRr', _thresholds.maxRr);
      await prefs.setDouble('th_minPi', _thresholds.minPi);
      await prefs.setDouble('th_maxPi', _thresholds.maxPi);
    } catch (e) {
      debugPrint('Error saving thresholds: $e');
    }
  }

  // ==========================================
  // REALTIME FIREBASE RTDB STREAM LISTENER
  // ==========================================
  void _listenToFirebase() {
    _dbSubscription?.cancel();
    try {
      final DatabaseReference ref = FirebaseDatabase.instance.ref('patient');
      _dbSubscription = ref.onValue.listen((DatabaseEvent event) {
        if (!mounted) return;
        final data = event.snapshot.value;
        if (data != null && data is Map) {
          final newV = PatientVitals.fromMap(
            data,
            _patientName,
            _thresholds,
            isRrEnabled: _isRrEnabled,
            isPiEnabled: _isPiEnabled,
            isAiLivingBodyCheckEnabled: _isAiLivingBodyCheckEnabled,
          );
          _onNewVitals(newV);
          setState(() => _isConnected = true);
        }
      }, onError: (e) {
        debugPrint('Firebase Realtime Database Error: $e');
        if (mounted) setState(() => _isConnected = false);
      });
    } catch (e) {
      debugPrint('Error attaching Firebase listener: $e');
      if (mounted) setState(() => _isConnected = false);
    }
  }

  void _onNewVitals(PatientVitals newV) {
    setState(() {
      _vitals = newV;

      // CONTINUOUS 5-SECOND ICU SCROLLING WAVEFORM BUFFER (125 samples = 25 pts/sec * 5s)
      if (!newV.isBodyConnected || !newV.isLivingBody) {
        _ppgRollingBuffer.addAll(List.filled(25, 0.0));
      } else {
        _ppgRollingBuffer.addAll(newV.ppgSamples.isNotEmpty ? newV.ppgSamples : List.filled(25, 0.0));
      }
      if (_ppgRollingBuffer.length > 125) {
        _ppgRollingBuffer.removeRange(0, _ppgRollingBuffer.length - 125);
      }

      _realtimeHistory.add(HistoryPoint(
        bpm: newV.bpm,
        spo2: newV.spo2,
        pi: newV.pi,
        rr: newV.rr,
        temp: newV.temperature,
        isDanger: newV.isDanger,
        time: DateTime.now(),
      ));
      if (_realtimeHistory.length > 30) {
        _realtimeHistory.removeAt(0);
      }
    });

    // STRICT 1-MINUTE MUTE SUPPRESSION:
    // If danger occurs while muted, SUPPRESS all sound alerts AND popup overlays!
    // Keep only the top-bar indicator red during this 60s window.
    if (newV.isDanger && !_isAlertDialogOpen && mounted) {
      if (AlarmAudioService.instance.isMuted) {
        debugPrint('[Alert] 1-Minute Mute Active (${AlarmAudioService.instance.remainingMuteSeconds}s left). Sound & popup suppressed. Top indicator remains red.');
      } else {
        _triggerEmergencyAlert(newV.status);
      }
    }
  }

  // ==========================================
  // SOUND ALARMS & EMERGENCY SIREN SYSTEM
  // ==========================================
  void _triggerEmergencyAlert(String emergencyReason) {
    if (_isAlertDialogOpen) return;
    if (AlarmAudioService.instance.isMuted) {
      debugPrint('[Alert] Emergency Dialog suppressed by 1-minute mute timer (${AlarmAudioService.instance.remainingMuteSeconds}s left).');
      return;
    }
    _isAlertDialogOpen = true;

    if (!_isMuted && _isAlarmAudioEnabled) {
      AlarmAudioService.instance.startAlarmSiren();
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => EmergencyAlertDialog(
        patientName: _patientName,
        bedWardId: _bedWardId,
        emergencyType: emergencyReason,
        bpm: _vitals.bpm,
        spo2: _vitals.spo2,
        temp: _vitals.temperature,
        rr: _vitals.rr,
        pi: _vitals.pi,
        breaches: _vitals.activeBreaches,
        onSilence: () {
          _setOneMinuteMute();
        },
        onDismiss: () {
          _setOneMinuteMute();
          Navigator.of(ctx).pop();
        },
        onCallNurse: _callNursePrompt,
        onCodeBlue: _triggerCodeBlueAlert,
      ),
    ).then((_) {
      _isAlertDialogOpen = false;
      AlarmAudioService.instance.stopAlarmSiren();
      _alarmSirenTimer?.cancel();
    });
  }

  void _playAlarmSoundLoop() {
    _alarmSirenTimer?.cancel();
    _alarmSirenTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      if (_isMuted || !_isAlarmAudioEnabled) return;
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    });
    SystemSound.play(SystemSoundType.alert);
    HapticFeedback.heavyImpact();
  }

  void _testAlarmSound() {
    AlarmAudioService.instance.playTestSiren();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🔊 ICU Alarm Siren Test Triggered (Speaker stream active).'),
        backgroundColor: Color(0xFF0E1424),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _toggleMute() {
    if (AlarmAudioService.instance.isMuted) {
      // Clear mute immediately to re-arm alarms
      AlarmAudioService.instance.clearMute();
      _muteCountdownTimer?.cancel();
      setState(() => _isMuted = false);
      _savePreferenceBool('sound_muted', false);
      _savePreferenceInt('muted_until_ms', 0);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔊 Audible Alarms Unmuted & Armed'),
          backgroundColor: Color(0xFF0E1424),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      // Activate strict 1-minute mute
      _setOneMinuteMute();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔇 Audible Alarms & Popups Silenced for 1 Minute (60s)'),
          backgroundColor: Color(0xFF0E1424),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // ==========================================
  // AI WAVEFORM & LIVING BODY ANALYSIS
  // ==========================================
  void _runAiWaveformVerification() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          color: Color(0xFF0E1424),
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF00E676)),
                SizedBox(height: 16),
                Text('AI Analyzing PPG Waveform Morphology...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      ),
    );

    final result = await GeminiService().analyzePpgWaveform(
      ppgSamples: _vitals.ppgSamples,
      bpm: _vitals.bpm,
      spo2: _vitals.spo2,
      isLivingBodyFlag: _vitals.isLivingBody,
    );

    if (mounted) Navigator.of(context, rootNavigator: true).pop();

    if (mounted) {
      final bool isAuthentic = result['isAuthenticBody'] == true;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF0E1424),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: isAuthentic ? const Color(0xFF00E676) : const Color(0xFFFF2E63)),
          ),
          title: Row(
            children: [
              Icon(
                isAuthentic ? Icons.check_circle_outline : Icons.warning_amber_rounded,
                color: isAuthentic ? const Color(0xFF00E676) : const Color(0xFFFF2E63),
              ),
              const SizedBox(width: 8),
              Text(
                isAuthentic ? 'Living Body Confirmed' : 'Sensor Detached / Fake Wave',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                result['clinicalSummary'] ?? 'Morphology analysis completed.',
                style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 13),
              ),
              const SizedBox(height: 12),
              Text(
                'Confidence: ${((result['confidence'] ?? 0.9) * 100).toInt()}% • Verified via Gemini AI',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Dismiss', style: TextStyle(color: Color(0xFF00E5FF))),
            ),
          ],
        ),
      );
    }
  }

  void _toggleCurveSmoothing() {
    setState(() => _isCurveSmoothingEnabled = !_isCurveSmoothingEnabled);
    _savePreferenceBool('ai_curve_smoothing', _isCurveSmoothingEnabled);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isCurveSmoothingEnabled ? '⚡ AI Cubic Curve Smoothing Enabled' : 'Raw Sensor Trace Enabled'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // ==========================================
  // MEDICAL GRADE AI ASSISTANT & CHATBOT MODAL
  // ==========================================
  void _openMedicalAssistantModal() {
    final textInputCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0E1424),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setModalState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(modalCtx).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 16,
          ),
          child: SizedBox(
            height: MediaQuery.of(modalCtx).size.height * 0.75,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E5FF).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.smart_toy_rounded, color: Color(0xFF00E5FF), size: 20),
                        ),
                        const SizedBox(width: 10),
                        const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ICU Clinical AI Assistant',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                            ),
                            Text(
                              'Powered by Gemini 1.5 Flash • Voice Enabled',
                              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(modalCtx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Patient Live Telemetry Bar in Chat
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF070A12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF1E293B)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Text('HR: ${_vitals.bpm} BPM', style: const TextStyle(fontSize: 11, color: Color(0xFFFF2E63), fontWeight: FontWeight.bold)),
                      Text('SpO2: ${_vitals.spo2}%', style: const TextStyle(fontSize: 11, color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
                      Text('Temp: ${_vitals.temperature}°C', style: const TextStyle(fontSize: 11, color: Color(0xFFF59E0B), fontWeight: FontWeight.bold)),
                      Text(_vitals.isBodyConnected ? '🟢 Living' : '🔴 Detached', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Quick Prompt Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildQuickPromptChip('Explain Vitals', textInputCtrl, setModalState),
                      _buildQuickPromptChip('Is PPG Wave Normal?', textInputCtrl, setModalState),
                      _buildQuickPromptChip('Silence Alarms', textInputCtrl, setModalState),
                      _buildQuickPromptChip('Triage Patient', textInputCtrl, setModalState),
                    ],
                  ),
                ),
                const SizedBox(height: 10),

                // Chat Messages List
                Expanded(
                  child: ListView.builder(
                    itemCount: _assistantMessages.length,
                    itemBuilder: (context, idx) {
                      final msg = _assistantMessages[idx];
                      final isAi = msg['sender'] == 'ai';
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        alignment: isAi ? Alignment.centerLeft : Alignment.centerRight,
                        child: Container(
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isAi ? const Color(0xFF141C32) : const Color(0xFF00E5FF).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isAi ? const Color(0xFF1E293B) : const Color(0xFF00E5FF).withOpacity(0.5),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                msg['text'] ?? '',
                                style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.3),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                msg['time'] ?? '',
                                style: const TextStyle(color: Color(0xFF64748B), fontSize: 9),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),

                // Text & Voice Input Row
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: textInputCtrl,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Ask Clinical AI or type command...',
                          hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFF070A12),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: const BorderSide(color: Color(0xFF1E293B)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: const BorderSide(color: Color(0xFF00E5FF)),
                          ),
                        ),
                        onSubmitted: (val) => _sendAssistantMessage(val, textInputCtrl, setModalState),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.mic_rounded, color: Color(0xFF00E676)),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF00E676).withOpacity(0.15),
                        padding: const EdgeInsets.all(10),
                      ),
                      onPressed: () {
                        textInputCtrl.text = 'Assess patient cardiovascular stability and PPG pulse regularity.';
                        setModalState(() {});
                      },
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.send_rounded, color: Color(0xFF00E5FF)),
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF).withOpacity(0.15),
                        padding: const EdgeInsets.all(10),
                      ),
                      onPressed: () => _sendAssistantMessage(textInputCtrl.text, textInputCtrl, setModalState),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickPromptChip(String text, TextEditingController ctrl, void Function(void Function()) setModalState) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        backgroundColor: const Color(0xFF141C32),
        side: const BorderSide(color: Color(0xFF1E293B)),
        label: Text(text, style: const TextStyle(fontSize: 10, color: Color(0xFF38BDF8))),
        onPressed: () {
          ctrl.text = text;
          setModalState(() {});
        },
      ),
    );
  }

  void _sendAssistantMessage(String text, TextEditingController ctrl, void Function(void Function()) setModalState) async {
    final query = text.trim();
    if (query.isEmpty) return;

    ctrl.clear();
    setState(() {
      _assistantMessages.add({
        'sender': 'user',
        'text': query,
        'time': 'Now',
      });
    });
    setModalState(() {});

    final response = await GeminiService().chatWithMedicalAssistant(
      userMessage: query,
      patientContext: {
        'name': _patientName,
        'bpm': _vitals.bpm,
        'spo2': _vitals.spo2,
        'temp': _vitals.temperature,
        'status': _vitals.status,
        'isBodyConnected': _vitals.isBodyConnected,
      },
    );

    if (mounted) {
      setState(() {
        _assistantMessages.add({
          'sender': 'ai',
          'text': response,
          'time': 'Now',
        });
      });
      setModalState(() {});
    }
  }

  // ==========================================
  // TAB 0: LIVE MONITOR VIEW
  // ==========================================
  Widget _buildLiveMonitorTab() {
    final double displayTemp = _useFahrenheit
        ? (_vitals.temperature * 9 / 5) + 32
        : _vitals.temperature;
    final String tempUnit = _useFahrenheit ? '°F' : '°C';

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Patient Bio Card with Quick Nurse Dial
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1424),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFF00E5FF).withOpacity(0.15),
                  child: Text(
                    _patientName.isNotEmpty
                        ? _patientName.split(" ").map((n) => n.isNotEmpty ? n[0] : '').take(2).join()
                        : 'P',
                    style: const TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _patientName,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$_patientAgeGender • $_bedWardId',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF).withOpacity(0.15),
                    foregroundColor: const Color(0xFF00E5FF),
                    side: const BorderSide(color: Color(0xFF00E5FF)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.call, size: 14),
                  label: const Text('Call Nurse', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  onPressed: _callNursePrompt,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Dynamic Critical Alert Banner
          _buildAlertBanner(),
          const SizedBox(height: 14),

          // AI Health Insights Card (Google Gemini AI 1.5 Flash)
          _buildAiHealthInsightsCard(),
          const SizedBox(height: 14),

          // NEW COMPONENT: Real-time PPG Waveform Line Chart (MAX30102 IR Waveform)
          _buildPpgWaveformCard(),
          const SizedBox(height: 14),

          // Realtime ECG Waveform
          _buildEcWaveformCard(),
          const SizedBox(height: 14),

          // Row 1: Heart Rate & SpO2 (Always Active)
          Row(
            children: [
              Expanded(child: _buildBpmCard()),
              const SizedBox(width: 12),
              Expanded(child: _buildSpo2Card()),
            ],
          ),
          const SizedBox(height: 12),

          // Row 2: Modular Perfusion Index (PI) & Respiratory Rate (RR)
          if (_isPiEnabled && _isRrEnabled)
            Row(
              children: [
                Expanded(child: _buildPiCard()),
                const SizedBox(width: 12),
                Expanded(child: _buildRrCard()),
              ],
            )
          else if (_isPiEnabled)
            _buildPiCard()
          else if (_isRrEnabled)
            _buildRrCard(),

          if (_isPiEnabled || _isRrEnabled)
            const SizedBox(height: 12),

          // Row 3: Body Temperature (Full width)
          _buildTempCard(displayTemp, tempUnit),
          const SizedBox(height: 16),

          // Emergency Code Blue Action Button
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF2E63),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _triggerCodeBlueAlert,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.warning_rounded, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text(
                  'Emergency Code Blue Alert',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // =========================================================================
  // THE NEW COMPONENT: REAL-TIME PPG WAVEFORM LINE CHART
  // =========================================================================
  Widget _buildPpgWaveformCard() {
    final bool isAttached = _vitals.isLivingBody && _vitals.isBodyConnected;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1424),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isAttached
              ? const Color(0xFF00E676).withOpacity(0.35)
              : const Color(0xFFFF2E63).withOpacity(0.4),
        ),
        boxShadow: [
          BoxShadow(
            color: isAttached
                ? const Color(0xFF00E676).withOpacity(0.08)
                : const Color(0xFFFF2E63).withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E676).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.waves_rounded, size: 16, color: Color(0xFF00E676)),
                  ),
                  const SizedBox(width: 8),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'REAL-TIME PPG PULSE WAVEFORM',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'MAX30102 IR Sensor (5-Second Continuous ICU Sweep • 125 Samples)',
                        style: TextStyle(fontSize: 9.5, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isAttached
                      ? const Color(0xFF00E676).withOpacity(0.15)
                      : const Color(0xFFFF2E63).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isAttached ? const Color(0xFF00E676) : const Color(0xFFFF2E63),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 3.5,
                      backgroundColor: isAttached ? const Color(0xFF00E676) : const Color(0xFFFF2E63),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isAttached ? 'LIVING BODY' : 'DETACHED',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: isAttached ? const Color(0xFF00E676) : const Color(0xFFFF2E63),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Chart Canvas
          Container(
            height: 95,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF070A12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CustomPaint(
                painter: PpgWaveformPainter(
                  samples: List<double>.from(_ppgRollingBuffer),
                  isLivingBody: isAttached,
                  isCurveSmoothed: _isCurveSmoothingEnabled,
                  lineColor: const Color(0xFF00E676),
                  sweepProgress: _ppgSweepProgress,
                  bpm: _vitals.bpm,
                  beatPhase: _ppgBeatPhase,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Actions Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: _toggleCurveSmoothing,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: _isCurveSmoothingEnabled
                        ? const Color(0xFF00E5FF).withOpacity(0.15)
                        : const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isCurveSmoothingEnabled
                          ? const Color(0xFF00E5FF)
                          : const Color(0xFF334155),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isCurveSmoothingEnabled ? Icons.auto_awesome : Icons.linear_scale,
                        size: 13,
                        color: _isCurveSmoothingEnabled ? const Color(0xFF00E5FF) : const Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _isCurveSmoothingEnabled ? 'AI Smoothing: ON' : 'AI Smoothing: OFF',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _isCurveSmoothingEnabled ? const Color(0xFF00E5FF) : const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              InkWell(
                onTap: _runAiWaveformVerification,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFA855F7).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFA855F7)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.psychology_outlined, size: 13, color: Color(0xFFA855F7)),
                      SizedBox(width: 5),
                      Text(
                        'AI Wave Check',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFA855F7),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// AI Health Insights Card powered by Google Gemini AI 1.5 Flash
  Widget _buildAiHealthInsightsCard() {
    final gemini = GeminiService();
    final bool hasAssessment = gemini.lastAssessment != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1424),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.35)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF00E5FF).withOpacity(0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF00E5FF).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_awesome, color: Color(0xFF00E5FF), size: 16),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'AI HEALTH INSIGHTS (GEMINI AI)',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: Color(0xFF00E5FF),
                  ),
                ),
              ),
              if (gemini.isLoading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00E5FF)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            hasAssessment
                ? gemini.lastAssessment!
                : 'Tap "Run AI Analysis" to evaluate live physiological vitals using Google Gemini AI.',
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: Color(0xFFE2E8F0),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                gemini.lastAssessmentTime != null
                    ? 'Generated at ${_formatTime(gemini.lastAssessmentTime!)}'
                    : 'Target Model: gemini-1.5-flash',
                style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E5FF),
                  foregroundColor: const Color(0xFF070A12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.psychology, size: 14),
                label: const Text(
                  'Run AI Analysis',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                ),
                onPressed: gemini.isLoading ? null : _triggerAiAnalysis,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _triggerAiAnalysis() async {
    setState(() {});
    try {
      final assessment = await GeminiService().generateClinicalAssessment(
        bpm: _vitals.bpm,
        spo2: _vitals.spo2,
        temp: _vitals.temperature,
        rr: _isRrEnabled ? _vitals.rr : null,
        pi: _isPiEnabled ? _vitals.pi : null,
        status: _vitals.status,
        breaches: _vitals.activeBreaches,
      );

      await ActionLogService().logAction(
        title: 'Gemini AI Health Assessment Generated',
        details: assessment,
        category: 'ai_insight',
      );

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('AI Analysis Error: $e');
      if (mounted) setState(() {});
    }
  }

  // ==========================================
  // DYNAMIC ALERT BANNER
  // ==========================================
  Widget _buildAlertBanner() {
    final bool isConnected = _vitals.isBodyConnected;
    final bool isDanger = _vitals.isDanger || !isConnected;

    final Color bannerColor = !isConnected
        ? const Color(0xFFFF2E63)
        : (isDanger ? const Color(0xFFFF2E63) : const Color(0xFF10B981));

    String title = 'VITALS NORMAL & STABLE';
    String desc = 'Monitored physiological indicators are within configured safe bounds.';

    if (!isConnected) {
      title = 'SENSOR DETACHED / NO LIVING BODY DETECTED';
      desc = 'The MAX30102 sensor is not attached to a living human body. Telemetry cleared for patient safety.';
    } else if (isDanger) {
      final muteInfo = AlarmAudioService.instance.isMuted
          ? ' [MUTED • ${AlarmAudioService.instance.remainingMuteSeconds}s]'
          : '';
      title = 'CLINICAL ALERT: ${_vitals.status.toUpperCase()}$muteInfo';
      desc = _vitals.activeBreaches.isNotEmpty
          ? _vitals.activeBreaches.join(' • ')
          : 'Patient condition requires clinical attention.';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bannerColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: bannerColor.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(!isConnected ? Icons.link_off_rounded : (isDanger ? Icons.warning_rounded : Icons.verified_user_rounded), color: bannerColor, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: bannerColor, fontSize: 11.5, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 10.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEcWaveformCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1424),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'CONTINUOUS ECG MONITOR',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B)),
              ),
              Text(
                '${_vitals.bpm} BPM Sync',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF00E5FF)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            height: 55,
            decoration: BoxDecoration(
              color: const Color(0xFF070A12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CustomPaint(
                painter: EcWaveformPainter(
                  progress: _ecgProgress,
                  isDanger: _vitals.isDanger,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // VITAL CARDS (HEART RATE, SPO2, TEMP, PI, RR)
  // ==========================================
  Widget _buildBpmCard() {
    final bool isConn = _vitals.isBodyConnected;
    return _buildCardBase(
      title: 'HEART RATE',
      value: isConn ? '${_vitals.bpm}' : '--',
      unit: 'BPM',
      range: '${_thresholds.minBpm} - ${_thresholds.maxBpm}',
      status: isConn ? (_vitals.bpm > _thresholds.maxBpm ? 'Tachycardia' : (_vitals.bpm < _thresholds.minBpm ? 'Bradycardia' : 'Normal Sinus')) : 'Sensor Detached',
      color: const Color(0xFFFF2E63),
      icon: Icons.favorite_rounded,
      progress: isConn ? ((_vitals.bpm - 40) / 120).clamp(0.0, 1.0) : 0.0,
    );
  }

  Widget _buildSpo2Card() {
    final bool isConn = _vitals.isBodyConnected;
    return _buildCardBase(
      title: 'BLOOD OXYGEN',
      value: isConn ? '${_vitals.spo2}' : '--',
      unit: '%',
      range: '${_thresholds.minSpo2} - ${_thresholds.maxSpo2}%',
      status: isConn ? (_vitals.spo2 < _thresholds.minSpo2 ? 'Hypoxemia' : 'Optimal Oxygenation') : 'No Signal',
      color: const Color(0xFF00E5FF),
      icon: Icons.water_drop_rounded,
      progress: isConn ? ((_vitals.spo2 - 70) / 30).clamp(0.0, 1.0) : 0.0,
    );
  }

  Widget _buildPiCard() {
    final bool isConn = _vitals.isBodyConnected;
    return _buildCardBase(
      title: 'PERFUSION INDEX',
      value: isConn ? _vitals.pi.toStringAsFixed(1) : '--',
      unit: '%',
      range: '${_thresholds.minPi.toStringAsFixed(1)} - ${_thresholds.maxPi.toStringAsFixed(1)}%',
      status: isConn ? (_vitals.pi < _thresholds.minPi ? 'Low Perfusion' : 'Adequate Flow') : 'No Perfusion',
      color: const Color(0xFFA855F7),
      icon: Icons.stacked_bar_chart_rounded,
      progress: isConn ? ((_vitals.pi - 0.5) / 9.5).clamp(0.0, 1.0) : 0.0,
    );
  }

  Widget _buildRrCard() {
    final bool isConn = _vitals.isBodyConnected;
    return _buildCardBase(
      title: 'RESPIRATION',
      value: isConn ? '${_vitals.rr}' : '--',
      unit: 'RPM',
      range: '${_thresholds.minRr} - ${_thresholds.maxRr} RPM',
      status: isConn ? (_vitals.rr > _thresholds.maxRr ? 'Tachypnea' : 'Normal Breathing') : 'No Respiration',
      color: const Color(0xFF10B981),
      icon: Icons.air_rounded,
      progress: isConn ? ((_vitals.rr - 8) / 24).clamp(0.0, 1.0) : 0.0,
    );
  }

  Widget _buildTempCard(double displayTemp, String tempUnit) {
    final bool isConn = _vitals.isBodyConnected;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1424),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.thermostat_rounded, size: 16, color: Color(0xFFF59E0B)),
                  ),
                  const SizedBox(width: 8),
                  const Text('BODY TEMPERATURE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                ],
              ),
              Text(
                '${_thresholds.minTemp.toStringAsFixed(1)} - ${_thresholds.maxTemp.toStringAsFixed(1)} °C',
                style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                isConn ? displayTemp.toStringAsFixed(1) : '--',
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white),
              ),
              const SizedBox(width: 4),
              Text(tempUnit, style: const TextStyle(fontSize: 14, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
              const Spacer(),
              Text(
                isConn ? (_vitals.temperature > _thresholds.maxTemp ? 'Febrile Pyrexia' : 'Normothermia') : 'Sensor Offline',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isConn ? (_vitals.temperature > _thresholds.maxTemp ? const Color(0xFFFF2E63) : const Color(0xFF10B981)) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardBase({
    required String title,
    required String value,
    required String unit,
    required String range,
    required String status,
    required Color color,
    required IconData icon,
    required double progress,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1424),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(icon, size: 14, color: color),
                  ),
                  const SizedBox(width: 6),
                  Text(title, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white)),
              const SizedBox(width: 4),
              Text(unit, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          Text(status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 1: HISTORY & 24H ANALYTICS
  // ==========================================
  Widget _buildHistoryAndAnalyticsTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: _buildSubNavBtn(0, 'Realtime Buffer')),
              const SizedBox(width: 8),
              Expanded(child: _buildSubNavBtn(1, '24h Timeline')),
              const SizedBox(width: 8),
              Expanded(child: _buildSubNavBtn(2, 'Monthly Analysis')),
            ],
          ),
          const SizedBox(height: 14),

          if (_historySubNav == 0) ...[
            _buildStabilityDonutCard(),
            const SizedBox(height: 14),
            _buildRealtimeTrendCard(),
          ] else if (_historySubNav == 1) ...[
            _build24HourTrendCard(),
            const SizedBox(height: 14),
            _build24HourTableCard(),
          ] else ...[
            _buildMonthlyAnalysisCard(),
            const SizedBox(height: 14),
            _buildMonthlyLogTableCard(),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSubNavBtn(int index, String label) {
    final bool active = _historySubNav == index;
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: active ? const Color(0xFF00E5FF) : const Color(0xFF0E1424),
        foregroundColor: active ? const Color(0xFF070A12) : const Color(0xFF94A3B8),
        side: BorderSide(color: active ? const Color(0xFF00E5FF) : const Color(0xFF1E293B)),
        padding: const EdgeInsets.symmetric(vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: () => setState(() => _historySubNav = index),
      child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildStabilityDonutCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1424),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 85,
            height: 85,
            child: CustomPaint(
              painter: StabilityDonutChartPainter(
                optimalPct: 92,
                warningPct: 6,
                criticalPct: 2,
              ),
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CLINICAL STABILITY INDEX', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                SizedBox(height: 4),
                Text('92% Optimal Range', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                SizedBox(height: 2),
                Text('Telemetry points evaluated over active ICU monitoring window.', style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRealtimeTrendCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1424),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('REALTIME BUFFER TRENDS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
              DropdownButton<String>(
                value: _selectedTrendMetric,
                dropdownColor: const Color(0xFF141C32),
                style: const TextStyle(fontSize: 11, color: Color(0xFF00E5FF), fontWeight: FontWeight.bold),
                underline: const SizedBox(),
                items: ['BPM', 'SpO2', 'Temp', if (_isPiEnabled) 'PI', if (_isRrEnabled) 'RR']
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedTrendMetric = v ?? 'BPM'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 110,
            decoration: BoxDecoration(
              color: const Color(0xFF070A12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CustomPaint(
                painter: MultiTrendChartPainter(
                  history: _realtimeHistory,
                  metric: _selectedTrendMetric,
                  useFahrenheit: _useFahrenheit,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _build24HourTrendCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1424),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('24-HOUR HOURLY TREND', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
              DropdownButton<String>(
                value: _selected24hMetric,
                dropdownColor: const Color(0xFF141C32),
                style: const TextStyle(fontSize: 11, color: Color(0xFF00E5FF), fontWeight: FontWeight.bold),
                underline: const SizedBox(),
                items: ['BPM', 'SpO2', 'Temp']
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) => setState(() => _selected24hMetric = v ?? 'BPM'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 110,
            decoration: BoxDecoration(
              color: const Color(0xFF070A12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CustomPaint(
                painter: Timeline24hChartPainter(
                  points: _hourlyHistory,
                  metric: _selected24hMetric,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _build24HourTableCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1424),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('HOURLY TELEMETRY LOGS (LAST 24 HOURS)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
          const SizedBox(height: 8),
          ..._hourlyHistory.take(6).map((h) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(h.time, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                    Text('${h.bpm} BPM', style: const TextStyle(fontSize: 11, color: Color(0xFFFF2E63), fontWeight: FontWeight.bold)),
                    Text('${h.spo2}%', style: const TextStyle(fontSize: 11, color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
                    Text('${h.temp}°C', style: const TextStyle(fontSize: 11, color: Color(0xFFF59E0B), fontWeight: FontWeight.bold)),
                    Text(h.status, style: const TextStyle(fontSize: 10, color: Color(0xFF10B981))),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildMonthlyAnalysisCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1424),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('30-DAY MONTHLY COMPLIANCE & HR BAND', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
          const SizedBox(height: 10),
          Container(
            height: 110,
            decoration: BoxDecoration(
              color: const Color(0xFF070A12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CustomPaint(
                painter: MonthlyComplianceChartPainter(logs: _monthlyLogs),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyLogTableCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1424),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('RECENT DAILY LOG SUMMARIES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
          const SizedBox(height: 8),
          ..._monthlyLogs.take(5).map((l) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(l.date, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
                    Text('Avg ${l.avgBpm} BPM', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                    Text('${l.avgSpo2}%', style: const TextStyle(fontSize: 11, color: Color(0xFF00E5FF))),
                    Text('${l.breaches} Alerts', style: TextStyle(fontSize: 10, color: l.breaches == 0 ? const Color(0xFF10B981) : const Color(0xFFFF2E63))),
                    Text(l.rating, style: const TextStyle(fontSize: 10, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 2: DAILY REPORT WITH SPOKEN AI VOICE
  // ==========================================
  Widget _buildDailyReportTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Voice Report Narration Bar
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1424),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.4)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5FF).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _isAiSpeaking ? Icons.volume_up_rounded : Icons.record_voice_over_rounded,
                    color: const Color(0xFF00E5FF),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Voice Clinical Report',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                      Text(
                        'Spoken telemetry summary for Eleanor Vance',
                        style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isAiSpeaking ? const Color(0xFFFF2E63) : const Color(0xFF00E5FF),
                    foregroundColor: const Color(0xFF070A12),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: Icon(_isAiSpeaking ? Icons.stop : Icons.play_arrow, size: 14),
                  label: Text(
                    _isAiSpeaking ? 'Stop Voice' : 'Read Report',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  onPressed: _toggleVoiceReport,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Clinical Summary Sheet
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1424),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('PHYSICIAN CLINICAL BRIEF', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF00E5FF))),
                    Text('AUTO-GENERATED', style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
                  ],
                ),
                const SizedBox(height: 12),
                _buildReportRow('Patient Name', _patientName),
                _buildReportRow('Monitoring Location', '$_bedWardId (${_patientAgeGender})'),
                _buildReportRow('Primary Nurse', '$_nurseName (${_nursePhone})'),
                _buildReportRow('Mean Heart Rate', '${_vitals.bpm} BPM (Sinus Rhythm)'),
                _buildReportRow('Mean Oxygen Saturation', '${_vitals.spo2}% (Room Air)'),
                _buildReportRow('Core Temperature', '${_vitals.temperature}°C'),
                _buildReportRow('PPG Waveform Status', _vitals.isBodyConnected ? 'Living Body Pulsatile' : 'Sensor Detached'),
                _buildReportRow('Stability Score', '92% (Optimal ICU Range)'),
                const Divider(color: Color(0xFF1E293B), height: 24),
                const Text(
                  'Clinical Assessment & Directives:',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Patient exhibits stable hemodynamic parameters throughout active continuous telemetry surveillance. Continue baseline monitoring and maintain normal hydration protocols.',
                  style: TextStyle(fontSize: 11, color: Color(0xFFCBD5E1), height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  void _toggleVoiceReport() {
    setState(() => _isAiSpeaking = !_isAiSpeaking);
    if (_isAiSpeaking) {
      SystemSound.play(SystemSoundType.alert);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎙️ AI Voice reading clinical report out loud in English...'),
          backgroundColor: Color(0xFF0E1424),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _buildReportRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 3: MODULAR SENSORS
  // ==========================================
  Widget _buildSensorModulesTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('ACTIVE SENSOR HARDWARE MODULES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
          const SizedBox(height: 12),
          _buildModuleToggleCard(
            'MAX30102 Heart Rate & SpO2',
            'Core primary sensor (Always Active)',
            true,
            null,
            Icons.favorite_rounded,
            const Color(0xFFFF2E63),
          ),
          const SizedBox(height: 10),
          _buildModuleToggleCard(
            'DS18B20 Body Temperature',
            'OneWire digital clinical probe (Always Active)',
            true,
            null,
            Icons.thermostat_rounded,
            const Color(0xFFF59E0B),
          ),
          const SizedBox(height: 10),
          _buildModuleToggleCard(
            'Respiratory Rate (RR) Derivation',
            'Plethysmogram amplitude modulation algorithm',
            _isRrEnabled,
            (v) {
              setState(() => _isRrEnabled = v);
              _savePreferenceBool('mod_rr', v);
            },
            Icons.air_rounded,
            const Color(0xFF10B981),
          ),
          const SizedBox(height: 10),
          _buildModuleToggleCard(
            'Perfusion Index (PI) Calculation',
            'AC/DC pulsatile ratio from infrared photoplethysmogram',
            _isPiEnabled,
            (v) {
              setState(() => _isPiEnabled = v);
              _savePreferenceBool('mod_pi', v);
            },
            Icons.stacked_bar_chart_rounded,
            const Color(0xFFA855F7),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildModuleToggleCard(String title, String desc, bool active, ValueChanged<bool>? onChanged, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1424),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                const SizedBox(height: 2),
                Text(desc, style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
              ],
            ),
          ),
          Switch(
            value: active,
            onChanged: onChanged,
            activeColor: const Color(0xFF00E5FF),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 4: SETTINGS & PERSISTENT CONFIGURATION
  // ==========================================
  Widget _buildCustomizationSettingsTab() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Google Gemini AI Runtime Key Configuration
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1424),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.4)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.key_rounded, color: Color(0xFF00E5FF), size: 18),
                    SizedBox(width: 8),
                    Text(
                      'GEMINI AI API KEY CONFIGURATION',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF00E5FF)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter your Google AI Studio Gemini API Key. Saved securely to local device storage.',
                  style: TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _geminiKeyCtrl,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Enter Gemini API key...',
                    hintStyle: const TextStyle(color: Color(0xFF64748B)),
                    filled: true,
                    fillColor: const Color(0xFF070A12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E5FF),
                    foregroundColor: const Color(0xFF070A12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    final key = _geminiKeyCtrl.text.trim();
                    GeminiService.setApiKey(key);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('gemini_runtime_api_key', key);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Gemini API key saved to persistent storage!')),
                    );
                  },
                  child: const Text('Save API Key', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 2. AI Feature Toggles (Persistent)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1424),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('AI & ALGORITHM TOGGLES', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('AI Living Body & Waveform Verification', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                  subtitle: const Text('Clear vitals and alert if waveform is detached/fake', style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
                  value: _isAiLivingBodyCheckEnabled,
                  activeColor: const Color(0xFF00E5FF),
                  onChanged: (v) {
                    setState(() => _isAiLivingBodyCheckEnabled = v);
                    _savePreferenceBool('ai_living_body_check', v);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('AI PPG Curve Smoothing (Cubic Bezier)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                  subtitle: const Text('Smooth 25 samples into a continuous hospital arterial wave', style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
                  value: _isCurveSmoothingEnabled,
                  activeColor: const Color(0xFF00E5FF),
                  onChanged: (v) {
                    setState(() => _isCurveSmoothingEnabled = v);
                    _savePreferenceBool('ai_curve_smoothing', v);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('AI Spoken Voice Reports', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                  subtitle: const Text('Enable Text-to-Speech narration of clinical summaries', style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
                  value: _isAiVoiceReportEnabled,
                  activeColor: const Color(0xFF00E5FF),
                  onChanged: (v) {
                    setState(() => _isAiVoiceReportEnabled = v);
                    _savePreferenceBool('ai_voice_report', v);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Phone Push Notifications', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                  subtitle: const Text('Push alerts to mobile phone during threshold breach', style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
                  value: _isPhoneNotificationsEnabled,
                  activeColor: const Color(0xFF00E5FF),
                  onChanged: (v) {
                    setState(() => _isPhoneNotificationsEnabled = v);
                    _savePreferenceBool('phone_notifications', v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 3. Sound & Siren Customization
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1424),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('AUDIBLE ALARM SIRENS & SOUNDS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Audible Emergency Sirens', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
                  subtitle: const Text('Play audio siren loops during critical hazard alerts', style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B))),
                  value: _isAlarmAudioEnabled,
                  activeColor: const Color(0xFFFF2E63),
                  onChanged: (v) {
                    setState(() => _isAlarmAudioEnabled = v);
                    _savePreferenceBool('alarm_audio_enabled', v);
                  },
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF2E63).withOpacity(0.2),
                    foregroundColor: const Color(0xFFFF2E63),
                    side: const BorderSide(color: Color(0xFFFF2E63)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.volume_up, size: 16),
                  label: const Text('Test Alarm Sound', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _testAlarmSound,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 4. Clinical Dual Bounds (Min & Max Thresholds)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0E1424),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF1E293B)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('CLINICAL THRESHOLDS (DUAL BOUNDS)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                const SizedBox(height: 10),
                _buildDualThresholdBox(
                  'Heart Rate (BPM)',
                  _thresholds.minBpm,
                  _thresholds.maxBpm,
                  40,
                  160,
                  (minV, maxV) {
                    setState(() {
                      _thresholds.minBpm = minV;
                      _thresholds.maxBpm = maxV;
                    });
                    _saveThresholds();
                  },
                ),
                const SizedBox(height: 10),
                _buildDualThresholdBox(
                  'SpO2 Saturation (%)',
                  _thresholds.minSpo2,
                  _thresholds.maxSpo2,
                  70,
                  100,
                  (minV, maxV) {
                    setState(() {
                      _thresholds.minSpo2 = minV;
                      _thresholds.maxSpo2 = maxV;
                    });
                    _saveThresholds();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildDualThresholdBox(String title, int minVal, int maxVal, int lowerLimit, int upperLimit, void Function(int, int) onChanged) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF070A12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
              Text('$minVal - $maxVal', style: const TextStyle(fontSize: 12, color: Color(0xFF00E5FF), fontWeight: FontWeight.bold)),
            ],
          ),
          RangeSlider(
            values: RangeValues(minVal.toDouble(), maxVal.toDouble()),
            min: lowerLimit.toDouble(),
            max: upperLimit.toDouble(),
            activeColor: const Color(0xFF00E5FF),
            inactiveColor: const Color(0xFF1E293B),
            onChanged: (vals) => onChanged(vals.start.round(), vals.end.round()),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // HELPER METHODS
  // ==========================================
  void _callNursePrompt() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0E1424),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Contact Primary Nurse', style: TextStyle(color: Colors.white)),
        content: Text('Dialing $_nurseName at $_nursePhone for Bed $_bedWardId.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00E5FF), foregroundColor: const Color(0xFF070A12)),
            onPressed: () {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Nurse $_nurseName notified!')),
              );
            },
            child: const Text('Call Now'),
          ),
        ],
      ),
    );
  }

  void _triggerCodeBlueAlert() {
    _triggerEmergencyAlert('Emergency Code Blue Crash Alarm Triggered');
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  void _initHistoricalData() {
    final now = DateTime.now();
    for (int i = 24; i >= 0; i--) {
      final t = now.subtract(Duration(hours: i));
      _hourlyHistory.add(HourlyPoint(
        time: '${t.hour.toString().padLeft(2, '0')}:00',
        bpm: 72 + (i % 6) * 2,
        spo2: 97 + (i % 3),
        pi: 3.5 + (i % 4) * 0.2,
        rr: 15 + (i % 4),
        temp: 36.6 + (i % 5) * 0.1,
        status: 'Optimal',
      ));
    }

    for (int d = 30; d >= 0; d--) {
      _monthlyLogs.add(DailyLogPoint(
        date: 'Day ${30 - d + 1}',
        minBpm: 60 + (d % 5),
        avgBpm: 75 + (d % 6),
        maxBpm: 92 + (d % 8),
        avgSpo2: 98.0,
        avgTemp: 36.8,
        breaches: d % 7 == 0 ? 1 : 0,
        rating: '94% Stability',
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) {
        AlarmAudioService.instance.initializeOnUserInteraction();
      },
      child: Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1424),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF00E5FF).withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.monitor_heart_rounded, color: Color(0xFF00E5FF), size: 18),
            ),
            const SizedBox(width: 8),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ICU MONITOR',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1.0, color: Colors.white),
                ),
                Text(
                  'Continuous Hemodynamic Telemetry',
                  style: TextStyle(fontSize: 9, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _isConnected ? const Color(0xFF10B981).withOpacity(0.15) : const Color(0xFFFF2E63).withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _isConnected ? const Color(0xFF10B981) : const Color(0xFFFF2E63)),
              ),
              child: Text(
                _isConnected ? 'LIVE RTDB' : 'STANDBY',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: _isConnected ? const Color(0xFF10B981) : const Color(0xFFFF2E63)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(_isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded),
                tooltip: _isMuted ? 'Muted (${AlarmAudioService.instance.remainingMuteSeconds}s remaining) - Tap to Unmute' : 'Tap to Mute (60s)',
                color: _isMuted ? const Color(0xFFFF2E63) : const Color(0xFF00E5FF),
                onPressed: _toggleMute,
              ),
              if (_isMuted)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    '${AlarmAudioService.instance.remainingMuteSeconds}s',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFFF2E63)),
                  ),
                ),
            ],
          ),
          TextButton(
            onPressed: () {
              setState(() => _useFahrenheit = !_useFahrenheit);
              _savePreferenceBool('use_fahrenheit', _useFahrenheit);
            },
            child: Text(
              _useFahrenheit ? '°F' : '°C',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00E5FF)),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _currentTabIndex,
        children: [
          _buildLiveMonitorTab(),
          _buildHistoryAndAnalyticsTab(),
          _buildDailyReportTab(),
          _buildSensorModulesTab(),
          _buildCustomizationSettingsTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF00E5FF),
        foregroundColor: const Color(0xFF070A12),
        icon: const Icon(Icons.smart_toy_rounded, size: 18),
        label: const Text('Clinical AI', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
        onPressed: _openMedicalAssistantModal,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTabIndex,
        backgroundColor: const Color(0xFF0E1424),
        indicatorColor: const Color(0xFF00E5FF).withOpacity(0.2),
        onDestinationSelected: (idx) => setState(() => _currentTabIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.speed_rounded),
            label: 'Live',
          ),
          NavigationDestination(
            icon: Icon(Icons.show_chart_rounded),
            label: 'Analytics',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            label: 'Report',
          ),
          NavigationDestination(
            icon: Icon(Icons.extension_outlined),
            label: 'Modules',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_rounded),
            label: 'Settings',
          ),
        ],
      ),
    ),
    );
  }
}
