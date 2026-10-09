import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Represents a persistent audit or clinical action log item
class ActionLogItem {
  final String id;
  final DateTime timestamp;
  final String title;
  final String details;
  final String category; // 'emergency', 'ai', 'nurse', 'setting', 'threshold', 'hardware'
  final String severity; // 'critical', 'warning', 'info'

  ActionLogItem({
    required this.id,
    required this.timestamp,
    required this.title,
    required this.details,
    this.category = 'info',
    this.severity = 'info',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'title': title,
    'details': details,
    'category': category,
    'severity': severity,
  };

  factory ActionLogItem.fromJson(Map<String, dynamic> json) => ActionLogItem(
    id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
    timestamp: json['timestamp'] != null ? DateTime.tryParse(json['timestamp']) ?? DateTime.now() : DateTime.now(),
    title: json['title'] ?? 'Action Logged',
    details: json['details'] ?? '',
    category: json['category'] ?? 'info',
    severity: json['severity'] ?? 'info',
  );
}

/// Service to maintain persistent clinical and system action history
class ActionLogService {
  static final ActionLogService _instance = ActionLogService._internal();
  factory ActionLogService() => _instance;
  ActionLogService._internal();

  static const String _prefKey = 'persistent_patient_action_logs';
  final List<ActionLogItem> _logs = [];
  final ValueNotifier<List<ActionLogItem>> logsNotifier = ValueNotifier([]);

  List<ActionLogItem> get logs => List.unmodifiable(_logs);

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? jsonStr = prefs.getString(_prefKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List decoded = jsonDecode(jsonStr);
        _logs.clear();
        for (var item in decoded) {
          if (item is Map<String, dynamic>) {
            _logs.add(ActionLogItem.fromJson(item));
          } else if (item is Map) {
            _logs.add(ActionLogItem.fromJson(Map<String, dynamic>.from(item)));
          }
        }
        logsNotifier.value = List.unmodifiable(_logs);
      }
    } catch (e) {
      debugPrint('[ActionLogService] Error loading stored logs: $e');
    }
  }

  Future<void> logAction({
    required String title,
    required String details,
    String category = 'info',
    String severity = 'info',
  }) async {
    final item = ActionLogItem(
      id: '${DateTime.now().millisecondsSinceEpoch}_${_logs.length}',
      timestamp: DateTime.now(),
      title: title,
      details: details,
      category: category,
      severity: severity,
    );

    _logs.insert(0, item);
    if (_logs.length > 200) {
      _logs.removeRange(200, _logs.length);
    }
    logsNotifier.value = List.unmodifiable(_logs);

    // 1. Persist to device local storage
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_logs.map((e) => e.toJson()).toList());
      await prefs.setString(_prefKey, encoded);
    } catch (e) {
      debugPrint('[ActionLogService] Error saving to SharedPreferences: $e');
    }

    // 2. Backup to Firebase Realtime Database node `/patient_logs`
    try {
      final ref = FirebaseDatabase.instance.ref('patient_logs').push();
      await ref.set(item.toJson()).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('[ActionLogService] Firebase log sync skipped: $e');
    }
  }

  Future<void> clearLogs() async {
    _logs.clear();
    logsNotifier.value = [];
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefKey);
    } catch (e) {
      debugPrint('[ActionLogService] Error clearing logs: $e');
    }
  }
}
