import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'action_log_service.dart';
import 'alarm_audio_service.dart';

/// Full-screen high-priority emergency alert dialog
class EmergencyAlertDialog extends StatefulWidget {
  final String emergencyType; // 'Water Required', 'Emergency Required', 'Clinical Threshold Breach'
  final String patientName;
  final String bedWardId;
  final int bpm;
  final int spo2;
  final double temp;
  final int? rr;
  final double? pi;
  final List<String> breaches;
  final VoidCallback? onDismiss;
  final VoidCallback? onCallNurse;
  final VoidCallback? onCodeBlue;
  final VoidCallback? onSilence;
  final VoidCallback? onClearWaterRequest;

  const EmergencyAlertDialog({
    super.key,
    required this.emergencyType,
    required this.patientName,
    required this.bedWardId,
    required this.bpm,
    required this.spo2,
    required this.temp,
    this.rr,
    this.pi,
    this.breaches = const [],
    this.onDismiss,
    this.onCallNurse,
    this.onCodeBlue,
    this.onSilence,
    this.onClearWaterRequest,
  });

  @override
  State<EmergencyAlertDialog> createState() => _EmergencyAlertDialogState();
}

class _EmergencyAlertDialogState extends State<EmergencyAlertDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  Timer? _soundLoopTimer;

  bool get isWaterRequest =>
      widget.emergencyType.toLowerCase().contains('water');

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);

    // Play repeating high-priority audible siren out loud through speaker stream
    AlarmAudioService.instance.startAlarmSiren();

    // Log occurrence into persistent action history
    ActionLogService().logAction(
      title: 'Emergency Alert Triggered: ${widget.emergencyType}',
      details: 'Patient: ${widget.patientName} (${widget.bedWardId}) | HR: ${widget.bpm} BPM | SpO2: ${widget.spo2}% | Temp: ${widget.temp.toStringAsFixed(1)}°C${widget.breaches.isNotEmpty ? " | Breaches: " + widget.breaches.join(", ") : ""}',
      category: 'emergency',
      severity: 'critical',
    );
  }

  @override
  void dispose() {
    _soundLoopTimer?.cancel();
    AlarmAudioService.instance.stopAlarmSiren();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color mainColor = isWaterRequest ? const Color(0xFF00E5FF) : const Color(0xFFFF2E63);
    final Color secondaryColor = isWaterRequest ? const Color(0xFF0284C7) : const Color(0xFF881337);

    return PopScope(
      canPop: false,
      child: AnimatedBuilder(
        animation: _animController,
        builder: (context, child) {
          final glowOpacity = 0.2 + (_animController.value * 0.35);

          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 500),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0F1D),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: mainColor.withOpacity(0.8),
                  width: 3.0,
                ),
                boxShadow: [
                  BoxShadow(
                    color: mainColor.withOpacity(glowOpacity),
                    blurRadius: 30,
                    spreadRadius: 8,
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top Hazard Banner & Pulsing Icon
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: mainColor.withOpacity(0.18),
                        border: Border.all(color: mainColor, width: 2),
                      ),
                      child: Icon(
                        isWaterRequest
                            ? Icons.water_drop_rounded
                            : Icons.warning_amber_rounded,
                        color: mainColor,
                        size: 48,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Alert Title
                    Text(
                      isWaterRequest
                          ? 'URGENT PATIENT WATER REQUEST'
                          : (widget.emergencyType.toLowerCase().contains('emergency')
                              ? 'HIGH PRIORITY PATIENT EMERGENCY'
                              : 'CRITICAL CLINICAL THRESHOLD BREACH'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: mainColor,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Bed Location: ${widget.bedWardId} • ${widget.patientName}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Physiological Vitals Grid
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141C32),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF1E293B)),
                      ),
                      child: Column(
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.monitor_heart, size: 14, color: Color(0xFF64748B)),
                              SizedBox(width: 6),
                              Text(
                                'REAL-TIME TELEMETRY AT EVENT',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF64748B),
                                  letterSpacing: 0.6,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildVitalChip('HR', '${widget.bpm}', 'BPM', const Color(0xFFFF2E63)),
                              _buildVitalChip('SpO2', '${widget.spo2}', '%', const Color(0xFF00E5FF)),
                              _buildVitalChip('Temp', widget.temp.toStringAsFixed(1), '°C', const Color(0xFFF59E0B)),
                              if (widget.rr != null && widget.rr! > 0)
                                _buildVitalChip('RR', '${widget.rr}', 'RPM', const Color(0xFF10B981)),
                            ],
                          ),
                          if (widget.breaches.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            const Divider(color: Color(0xFF1E293B), height: 1),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Active Breaches: ${widget.breaches.join(" | ")}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFFF6B8B),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Primary Action Buttons
                    if (isWaterRequest && widget.onClearWaterRequest != null)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00E5FF),
                          foregroundColor: Colors.black,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text(
                          'Acknowledge & Confirm Water Provided',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        onPressed: () {
                          ActionLogService().logAction(
                            title: 'Water Request Acknowledged',
                            details: 'Staff attended to patient hydration request at ${widget.bedWardId}',
                            category: 'nurse',
                            severity: 'info',
                          );
                          widget.onClearWaterRequest?.call();
                          if (widget.onDismiss != null) {
                            widget.onDismiss!();
                          } else {
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                    if (isWaterRequest) const SizedBox(height: 10),

                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E293B),
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(46),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.call, size: 16, color: Color(0xFF00E5FF)),
                            label: const Text(
                              'Call Nurse Desk',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            onPressed: () {
                              ActionLogService().logAction(
                                title: 'Nurse Desk Dialed from Alert',
                                details: 'Attending emergency call initiated from popup',
                                category: 'nurse',
                                severity: 'warning',
                              );
                              widget.onCallNurse?.call();
                              if (widget.onDismiss != null) {
                                widget.onDismiss!();
                              } else {
                                Navigator.of(context).pop();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF2E63),
                              foregroundColor: Colors.white,
                              minimumSize: const Size.fromHeight(46),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: const Icon(Icons.notifications_active, size: 16),
                            label: const Text(
                              'Code Blue Crash',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            onPressed: () {
                              ActionLogService().logAction(
                                title: 'Code Blue Broadcast from Alert',
                                details: 'Emergency crash team alerted for ${widget.patientName}',
                                category: 'emergency',
                                severity: 'critical',
                              );
                              widget.onCodeBlue?.call();
                              if (widget.onDismiss != null) {
                                widget.onDismiss!();
                              } else {
                                Navigator.of(context).pop();
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Silence & Dismiss Button
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF94A3B8),
                      ),
                      icon: const Icon(Icons.volume_off, size: 16),
                      label: const Text(
                        'Silence Siren & Acknowledge (60s)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      onPressed: () {
                        ActionLogService().logAction(
                          title: 'Emergency Siren Silenced (1-Min Mute)',
                          details: 'Alert acknowledged and silenced for 60 seconds by medical staff',
                          category: 'emergency',
                          severity: 'info',
                        );
                        AlarmAudioService.instance.setOneMinuteMute();
                        widget.onSilence?.call();
                        if (widget.onDismiss != null) {
                          widget.onDismiss!();
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVitalChip(String label, String value, String unit, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color)),
            const SizedBox(width: 2),
            Text(unit, style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8))),
          ],
        ),
      ],
    );
  }
}
