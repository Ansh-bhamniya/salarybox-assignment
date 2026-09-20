import 'dart:convert';

enum UserRole { admin, staff }

/// The logged-in session. For a staff user, [staffId] is that staff
/// member's own id — used both to scope which attendance record they can
/// create and to fetch their own enrolled face embedding.
class Session {
  const Session({
    required this.token,
    required this.role,
    this.staffId,
    this.staffName,
    this.employeeId,
  });

  final String token;
  final UserRole role;
  final String? staffId;
  final String? staffName;
  final String? employeeId;

  Map<String, dynamic> toJson() => {
        'token': token,
        'role': role.name,
        'staffId': staffId,
        'staffName': staffName,
        'employeeId': employeeId,
      };

  static Session fromJson(Map<String, dynamic> json) => Session(
        token: json['token'] as String,
        role: UserRole.values.byName(json['role'] as String),
        staffId: json['staffId'] as String?,
        staffName: json['staffName'] as String?,
        employeeId: json['employeeId'] as String?,
      );

  String encode() => jsonEncode(toJson());

  static Session decode(String raw) => Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
