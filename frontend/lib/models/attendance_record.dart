import 'package:intl/intl.dart';

class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.timestamp,
    required this.date,
    required this.time,
    required this.selfieUrl,
    required this.latitude,
    required this.longitude,
    this.matchConfidence,
  });

  final String id;

  /// When attendance was marked, in the viewer's local time.
  final DateTime timestamp;

  /// [timestamp] pre-formatted for display.
  final String date;
  final String time;
  final String selfieUrl;
  final double latitude;
  final double longitude;
  final double? matchConfidence;

  /// The backend stores `date` and `time` as UTC (they're plain columns with
  /// no zone), so they're combined and converted to the viewer's local time
  /// here — otherwise an IST admin would see times 5h30m off.
  static AttendanceRecord fromJson(Map<String, dynamic> json) {
    final utc = DateTime.parse('${json['date']}T${(json['time'] as String).substring(0, 8)}Z');
    final local = utc.toLocal();

    return AttendanceRecord(
      id: json['id'] as String,
      timestamp: local,
      date: DateFormat('dd MMM yyyy').format(local),
      time: DateFormat('hh:mm a').format(local),
      selfieUrl: json['selfie_url'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      matchConfidence: (json['match_confidence'] as num?)?.toDouble(),
    );
  }
}
