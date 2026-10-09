"""
Firebase Realtime Database Test Publisher
------------------------------------------
Sends live physiological telemetry (BPM, SpO2, PI, RR, Temperature)
along with 25-sample Realtime PPG IR Waveform arrays and Living Body flags
to the Firebase Realtime Database node `/patient`.

Includes simulated emergency states:
- 'Normal Sinus Rhythm'
- 'Water Required'
- 'Emergency Required'
- 'Clinical Threshold Breach'
- 'Sensor Detached / Non-Living Body' (for AI Waveform verification testing)

Usage:
    python test_firebase_publisher.py
"""

import time
import random
import math
import urllib.request
import json

DATABASE_URL = "https://patient-monitor-1bf49-default-rtdb.firebaseio.com"
PATIENT_ENDPOINT = f"{DATABASE_URL}/patient.json"

def generate_ppg_samples(bpm: int, is_living: bool) -> list:
    """
    Generates 25 realistic photoplethysmogram (PPG) IR samples per second.
    Models the human cardiac pulse cycle:
    - Rapid systolic anacrotic rise to peak
    - Catacrotic decline with a distinct dicrotic notch & secondary diastolic wave
    - Diastolic runoff decay to baseline
    """
    if not is_living:
        # Flatline / baseline noise when not connected to living human body
        # Strict 0.0 flatline baseline when not connected to living human body
        return [0.0 for _ in range(25)]

    samples = []
    beats_per_sec = bpm / 60.0
    
    for i in range(25):
        t = (i / 25.0) * beats_per_sec
        phase = t % 1.0  # Normalized phase 0.0 to 1.0 within heartbeat
        
        # Physiological arterial pulse model:
        if phase < 0.18:
            val = math.sin((phase / 0.18) * (math.pi / 2)) * 85.0 + 15.0
        elif phase < 0.38:
            p_rel = (phase - 0.18) / 0.20
            val = 100.0 - (p_rel * 45.0)
        elif phase < 0.50:
            p_rel = (phase - 0.38) / 0.12
            val = 55.0 + math.sin(p_rel * math.pi) * 18.0
        else:
            p_rel = (phase - 0.50) / 0.50
            val = 55.0 * math.exp(-p_rel * 2.2) + 12.0
            
        val += random.uniform(-1.2, 1.2)
        samples.append(round(max(0.0, min(100.0, val)), 1))

    return samples

def send_vitals(bpm, spo2, pi, rr, temp, is_danger, status, is_living=True):
    ppg_samples = generate_ppg_samples(bpm, is_living)
    
    payload = {
        "bpm": bpm,
        "spo2": spo2,
        "pi": round(pi, 1),
        "rr": rr,
        "temp": round(temp, 1),
        "isDanger": is_danger,
        "status": status,
        "isLivingBody": is_living,
        "ppgSamples": ppg_samples,
        "patientId": "PT-9042",
        "patientName": "Eleanor Vance",
        "lastUpdated": int(time.time() * 1000)
    }
    
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        PATIENT_ENDPOINT,
        data=data,
        headers={"Content-Type": "application/json"},
        method="PUT"
    )

    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            if response.status == 200:
                living_str = "LIVING BODY OK" if is_living else "DETACHED/NO-BODY"
                print(f"[OK RTDB Live] Status: '{status}' | BPM: {bpm} | SpO2: {spo2}% | Temp: {round(temp, 1)}C | PPG: 25pts | {living_str}")
            else:
                print(f"[!] Server responded: {response.status}")
    except Exception as e:
        print(f"[!] Error updating Firebase RTDB: {e}")

def main():
    print("=" * 75)
    print("  ICU Telemetry & 25-Sample PPG Waveform Publisher -> Firebase /patient")
    print(f"  Target: {PATIENT_ENDPOINT}")
    print("=" * 75)
    print("Streaming live telemetry + PPG wave every 2 seconds (Ctrl+C to stop)...\n")

    counter = 0
    try:
        while True:
            counter += 1
            cycle = counter % 22
            if cycle == 6:
                bpm = random.randint(76, 84)
                spo2 = random.randint(96, 98)
                pi = round(random.uniform(2.8, 3.5), 1)
                rr = random.randint(16, 18)
                temp = random.uniform(36.8, 37.2)
                is_danger = True
                status = "Water Required"
                is_living = True
            elif cycle == 11:
                bpm = random.randint(112, 126)
                spo2 = random.randint(92, 95)
                pi = round(random.uniform(1.8, 2.5), 1)
                rr = random.randint(22, 26)
                temp = random.uniform(37.4, 38.0)
                is_danger = True
                status = "Emergency Required"
                is_living = True
            elif cycle == 16:
                bpm = 0
                spo2 = 0
                pi = 0.0
                rr = 0
                temp = 0.0
                is_danger = True
                status = "Sensor Detached / No Pulse"
                is_living = False
            elif cycle == 19 or cycle == 20:
                bpm = random.randint(132, 142)
                spo2 = random.randint(86, 89)
                pi = round(random.uniform(0.6, 0.9), 1)
                rr = random.randint(26, 32)
                temp = random.uniform(38.8, 39.4)
                is_danger = True
                status = "Clinical Threshold Breach (Tachycardia & Hypoxia)"
                is_living = True
            else:
                bpm = random.randint(72, 80)
                spo2 = random.randint(97, 99)
                pi = round(random.uniform(3.4, 4.8), 1)
                rr = random.randint(14, 18)
                temp = random.uniform(36.5, 37.1)
                is_danger = False
                status = "Normal Sinus Rhythm"
                is_living = True

            send_vitals(bpm, spo2, pi, rr, temp, is_danger, status, is_living)
            time.sleep(2)
    except KeyboardInterrupt:
        print("\nPublisher stopped.")

if __name__ == "__main__":
    main()
