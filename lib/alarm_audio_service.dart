import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';

/// Professional ICU Medical Alarm Audio Engine
/// - Integrates audioplayers with speakerphone & alarm stream priority
/// - Synthesizes offline in-memory 16-bit PCM alternating two-tone medical sirens
/// - Initializes and unlocks hardware audio stream on first user interaction/touch
/// - Enforces strict 1-Minute Mute suppression timer (Duration(minutes: 1))
class AlarmAudioService {
  static final AlarmAudioService _instance = AlarmAudioService._internal();
  static AlarmAudioService get instance => _instance;
  AlarmAudioService._internal();

  AudioPlayer? _player;
  bool _isAudioInitialized = false;
  bool _isPlayingLoop = false;
  Timer? _loopTimer;
  DateTime? _mutedUntil;
  Uint8List? _cachedSirenBytes;
  bool _isAudioEnabled = true;

  bool get isAudioEnabled => _isAudioEnabled;
  set isAudioEnabled(bool val) {
    _isAudioEnabled = val;
    if (!val) stopAlarmSiren();
  }

  /// Returns true if alarm audio & overlays are suppressed under the 1-minute mute timer
  bool get isMuted {
    if (_mutedUntil == null) return false;
    if (DateTime.now().isBefore(_mutedUntil!)) {
      return true;
    }
    _mutedUntil = null;
    return false;
  }

  /// Number of seconds remaining in active 1-minute mute window
  int get remainingMuteSeconds {
    if (_mutedUntil == null) return 0;
    final diff = _mutedUntil!.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  DateTime? get mutedUntil => _mutedUntil;

  /// Unlocks & configures audio engine on first user touch/tap
  Future<void> initializeOnUserInteraction() async {
    if (_isAudioInitialized) return;
    try {
      _player ??= AudioPlayer();
      await _player!.setAudioContext(AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {
            AVAudioSessionOptions.defaultToSpeaker,
          },
        ),
      ));
      await _player!.setVolume(1.0);
      _cachedSirenBytes ??= _generateMedicalSirenWav();
      _isAudioInitialized = true;
      debugPrint('[AlarmAudioService] Audio engine unlocked & routed to alarm speaker stream.');
    } catch (e) {
      debugPrint('[AlarmAudioService] Audio initialize warning: $e');
    }
  }

  /// Sets a strict 1-minute mute window (Duration(minutes: 1))
  void setOneMinuteMute([DateTime? until]) {
    _mutedUntil = until ?? DateTime.now().add(const Duration(minutes: 1));
    stopAlarmSiren();
    debugPrint('[AlarmAudioService] 1-Minute Mute activated until ${_mutedUntil!.toIso8601String()}');
  }

  /// Clears mute immediately to re-arm alarms
  void clearMute() {
    _mutedUntil = null;
    debugPrint('[AlarmAudioService] Mute cleared. Alarms re-armed.');
  }

  /// Starts repeating high-urgency siren loop (plays out loud through speaker)
  Future<void> startAlarmSiren({bool force = false}) async {
    if ((isMuted || !_isAudioEnabled) && !force) {
      debugPrint('[AlarmAudioService] Siren suppressed - 1-minute mute active ($remainingMuteSeconds s left)');
      return;
    }
    if (_isPlayingLoop) return;
    _isPlayingLoop = true;

    // Trigger immediate pulse
    await _playSingleBurst();

    _loopTimer?.cancel();
    _loopTimer = Timer.periodic(const Duration(milliseconds: 1400), (_) async {
      if ((isMuted || !_isAudioEnabled) && !force) {
        stopAlarmSiren();
        return;
      }
      await _playSingleBurst();
    });
  }

  /// Stops siren loop immediately
  Future<void> stopAlarmSiren() async {
    _isPlayingLoop = false;
    _loopTimer?.cancel();
    _loopTimer = null;
    try {
      await _player?.stop();
    } catch (_) {}
  }

  /// Plays a single test siren pulse on command
  Future<void> playTestSiren() async {
    await initializeOnUserInteraction();
    await _playSingleBurst();
  }

  Future<void> _playSingleBurst() async {
    try {
      await SystemSound.play(SystemSoundType.alert);
      await HapticFeedback.heavyImpact();

      _cachedSirenBytes ??= _generateMedicalSirenWav();
      if (_player != null && _cachedSirenBytes != null) {
        await _player!.stop();
        await _player!.play(BytesSource(_cachedSirenBytes!));
      }
    } catch (e) {
      debugPrint('[AlarmAudioService] Fallback alert sound: $e');
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    }
  }

  /// Synthesizes an offline 16-bit PCM WAV medical siren (960Hz / 720Hz alternating tones)
  static Uint8List _generateMedicalSirenWav({
    int sampleRate = 22050,
    double durationSec = 1.1,
  }) {
    final int totalSamples = (sampleRate * durationSec).toInt();
    final int byteCount = totalSamples * 2;
    final int subchunk2Size = byteCount;
    final int chunkSize = 36 + subchunk2Size;

    final buffer = Uint8List(44 + byteCount);
    final ByteData bd = ByteData.view(buffer.buffer);

    // RIFF header
    buffer[0] = 0x52; // 'R'
    buffer[1] = 0x49; // 'I'
    buffer[2] = 0x46; // 'F'
    buffer[3] = 0x46; // 'F'
    bd.setUint32(4, chunkSize, Endian.little);
    buffer[8] = 0x57;  // 'W'
    buffer[9] = 0x41;  // 'A'
    buffer[10] = 0x56; // 'V'
    buffer[11] = 0x45; // 'E'

    // fmt subchunk
    buffer[12] = 0x66; // 'f'
    buffer[13] = 0x6D; // 'm'
    buffer[14] = 0x74; // 't'
    buffer[15] = 0x20; // ' '
    bd.setUint32(16, 16, Endian.little); // Subchunk1Size
    bd.setUint16(20, 1, Endian.little);  // PCM format
    bd.setUint16(22, 1, Endian.little);  // Mono
    bd.setUint32(24, sampleRate, Endian.little); // Sample rate
    bd.setUint32(28, sampleRate * 2, Endian.little); // Byte rate
    bd.setUint16(32, 2, Endian.little);  // Block align
    bd.setUint16(34, 16, Endian.little); // Bits per sample

    // data subchunk
    buffer[36] = 0x64; // 'd'
    buffer[37] = 0x61; // 'a'
    buffer[38] = 0x74; // 't'
    buffer[39] = 0x61; // 'a'
    bd.setUint32(40, subchunk2Size, Endian.little);

    // Alternating 960Hz and 720Hz siren pulse
    int offset = 44;
    final int switchInterval = sampleRate ~/ 4; // switches every 250ms
    for (int i = 0; i < totalSamples; i++) {
      final double freq = ((i ~/ switchInterval) % 2 == 0) ? 960.0 : 720.0;
      final double t = i / sampleRate;
      final double sample = math.sin(2.0 * math.pi * freq * t) * 0.85 +
          math.sin(4.0 * math.pi * freq * t) * 0.12;
      final int intSample = (sample * 30000).clamp(-32767.0, 32767.0).toInt();
      bd.setInt16(offset, intSample, Endian.little);
      offset += 2;
    }

    return buffer;
  }

  void dispose() {
    _loopTimer?.cancel();
    _player?.dispose();
  }
}
