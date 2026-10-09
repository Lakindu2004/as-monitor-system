# ICU Patient Telemetry & Monitoring System with Google Gemini AI

A production-grade, real-time Flutter ICU and Telehealth Patient Monitoring application integrated with **Firebase Realtime Database** and powered by **Google Gemini 1.5 Flash AI**.

---

## Key Features

### 1. Real-Time PPG Waveform Line Chart (MAX30102 IR Sensor)
- **Data Source**: Listens directly to Firebase node `/patient/ppgSamples` (or `data.ppgSamples`), streaming an array of 25 numerical IR values per second from the MAX30102 sensor.
- **Cubic Bezier Curve Smoothing**: Smooths discrete sensor points using Catmull-Rom to Cubic Bezier interpolation (tension 0.4) to reproduce an authentic clinical arterial pulse contour with clear systolic peaks and dicrotic reflections.
- **ICU Bedside Display**: Luminous Neon Green (`#00E676`) line, subtle glowing fill, dark-mode ICU medical grid, and zero data dots/points (`showDots: false` / `pointRadius: 0`).
- **Living Body Flatline Fallback**: When `data.isLivingBody` is `false` or detached, the waveform smoothly drops to a red baseline 0 flatline with warning indicator.

### 2. AI Waveform & Living Body Verification
- **Automated Body Detection**: Analyzes IR waveform amplitude variance, cardiac periodicity, and morphological hemodynamics via Google Gemini AI and real-time physiological heuristics.
- **Detached Sensor Safety Lock**: If a fake, non-human, or detached waveform is detected, all other vitals (BPM, SpO2, Temperature, PI, RR) are automatically cleared to `--` ("DISCONNECTED") and a high-priority hazard banner alerts medical staff.
- **Settings Toggle**: "AI Living Body & PPG Waveform Verification" toggle in Settings to control this automated safety protection.

### 3. Medical-Grade Clinical AI Assistant with Voice Chat
- **Conversational Bedside AI**: Powered by `gemini-1.5-flash`, grounded in real-time patient telemetry (HR, SpO2, Temp, PI, RR, Waveform status, active threshold breaches).
- **Voice Chat Input (Speech-to-Text)**: One-tap microphone button enables real-time spoken queries with speech recognition.
- **Voice Output (Text-to-Speech)**: The AI reads back its clinical assessment and triage recommendations out loud in natural medical cadence.
- **Instant Offline Clinical Engine**: Automatic deterministic heuristic fallback ensures 100% uptime even during network latency.

### 4. AI Spoken Voice Clinical Reports
- **Spoken Telemetry Summaries**: "Daily Report" tab features a one-tap "▶ Read Report with AI Voice" button that reads the 24-hour hemodynamic summary, stability index, and physician directives out loud.
- **Configurable**: Persistent toggle in Settings ("AI Spoken Voice Reports") to enable or disable automatic speech narration.

### 5. Overhauled Audio & Emergency Siren System
- **100% Audible Sound Engine**: Built with Web Audio API multi-oscillator synthesis (High-Priority Warble Siren, Code Blue ICU Alarm, Ambulance Wail, Medical Dual-Tone) with Web Speech Synthesis fallback.
- **Gesture Auto-Arming**: Overcomes modern browser autoplay blocks with automatic AudioContext arming on first touch/click, plus an explicit "🔔 Arm Audio" / "🔊 Test Sound" button.
- **Continuous Siren Loops**: Automatically sounds audible siren loops during critical breaches or patient call button presses until acknowledged or silenced.

### 6. 100% Persistent Settings Across App Restarts
- All user preferences, dual threshold bounds (Min & Max for all vitals), audio volume/tone selections, AI toggles, and module switches are stored permanently in `SharedPreferences` (Flutter) and `localStorage` (Web Preview).
- Closing and reopening the application preserves every single configuration setting exactly as set.

### 7. Zero Hardcoded API Keys (GitHub Secret Push Protection Compliant)
- Completely free of hardcoded Google Cloud or Gemini API keys in repository files (`web/index.html`, `web_preview.html`, `lib/`).
- Configured via compile-time definitions (`--dart-define=GEMINI_API_KEY=...`), environment variables, and dynamic runtime storage via the Settings UI.

---

## Telemetry Data Contract (`/patient` in Firebase RTDB)

```json
{
  "bpm": 76,
  "spo2": 98,
  "pi": 3.8,
  "rr": 16,
  "temp": 36.8,
  "isDanger": false,
  "status": "Normal Sinus Rhythm",
  "isLivingBody": true,
  "ppgSamples": [18.2, 25.1, 42.0, 70.3, 96.0, 88.4, 72.1, 60.5, 52.0, 58.4, 64.2, 56.0, 48.1, 40.0, 34.2, 28.1, 24.0, 21.2, 19.0, 18.2, 17.0, 18.1, 20.4, 24.0, 30.1],
  "patientId": "PT-9042",
  "patientName": "Eleanor Vance",
  "lastUpdated": 1728475200000
}
```

---

## Testing & Validation

1. **Simulate Real Hardware Telemetry**:
   ```bash
   python test_firebase_publisher.py
   ```
   Streams authentic 25-sample PPG vectors, vitals, and simulated detachment / emergency cycles every 2 seconds.

2. **Web Preview Testing**:
   Open `web_preview.html` in any web browser to experience the live ICU dashboard, voice chat assistant, and audio alarms.

3. **Android APK Build (GitHub Actions)**:
   Whenever code is pushed to `main`, `.github/workflows/build.yml` automatically compiles `app-release.apk` with `--dart-define` secrets.
