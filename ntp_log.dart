// lib/models/ntp_log.dart
import 'package:autheet/models/protocol_version.dart';
import 'package:autheet/models/find_model.dart';

class NtpLog {
  String server;
  int? offsetMs;
  int currentTimeMs;
  String? error;
  DateTime timestamp;

  NtpLog({
    required this.server,
    this.offsetMs,
    required this.currentTimeMs,
    this.error,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'autheet_protocol_version': autheetProtocolVersion,
    'server': server,
    'offsetMs': offsetMs,
    'currentTimeMs': currentTimeMs,
    'error': error,
    'timestamp': timestamp.toIso8601String(),
  };

  factory NtpLog.fromJson(Map<String, dynamic> json) => NtpLog(
    server: json['server'],
    offsetMs: json['offsetMs'],
    currentTimeMs: json['currentTimeMs'],
    error: json['error'],
    timestamp: DateTime.parse(json['timestamp']),
  );
}
