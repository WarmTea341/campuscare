enum UserRole {
  student,
  admin;

  /// Unknown values fall back to student (least privilege).
  static UserRole parse(String? value) => value == 'admin' ? admin : student;
}

class ProfileModel {
  final String id;
  final String fullName;
  final String? studentNumber;
  final UserRole role;

  const ProfileModel({
    required this.id,
    required this.fullName,
    this.studentNumber,
    required this.role,
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) => ProfileModel(
        id: json['id'] as String,
        fullName: json['full_name'] as String,
        studentNumber: json['student_number'] as String?,
        role: UserRole.parse(json['role'] as String?),
      );

  /// For screen routing only. The database enforces real permissions.
  bool get isAdmin => role == UserRole.admin;
}
