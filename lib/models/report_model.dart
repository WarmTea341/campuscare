class ReportModel {
  final String id;
  final String reporterId;
  final String roomId;
  final String category;
  final List<String> issueDetails;
  final String? description;
  final String? photoPath;
  final String status;
  final String? priority;
  final String? adminNotes;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? roomNumber; // display only, from nested rooms
  final String? buildingName; // display only, from nested rooms.buildings
  final String? reporterName; // display only, from nested profiles
  final String? reporterStudentNumber; // display only, from nested profiles

  const ReportModel({
    required this.id,
    required this.reporterId,
    required this.roomId,
    required this.category,
    required this.issueDetails,
    this.description,
    this.photoPath,
    required this.status,
    this.priority,
    this.adminNotes,
    required this.createdAt,
    required this.updatedAt,
    this.roomNumber,
    this.buildingName,
    this.reporterName,
    this.reporterStudentNumber,
  });

  /// Select with: /reports?select=*,rooms(id,room_number,buildings(id,name))
  factory ReportModel.fromJson(Map<String, dynamic> json) {
    final room = json['rooms'] as Map<String, dynamic>?;
    final building = room?['buildings'] as Map<String, dynamic>?;
    final reporter = json['profiles'] as Map<String, dynamic>?;
    return ReportModel(
      id: json['id'] as String,
      reporterId: json['reporter_id'] as String,
      roomId: json['room_id'] as String,
      category: json['category'] as String,
      issueDetails: (json['issue_details'] as List<dynamic>? ?? const [])
          .map((e) => e as String)
          .toList(),
      description: json['description'] as String?,
      photoPath: json['photo_path'] as String?,
      status: json['status'] as String,
      priority: json['priority'] as String?,
      adminNotes: json['admin_notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
      roomNumber: room?['room_number'] as String?,
      buildingName: building?['name'] as String?,
      reporterName: reporter?['full_name'] as String?,
      reporterStudentNumber: reporter?['student_number'] as String?,
    );
  }

  /// For tests/serialization only. Never send this for edits - use the DTOs.
  Map<String, dynamic> toJson() => {
        'id': id,
        'reporter_id': reporterId,
        'room_id': roomId,
        'category': category,
        'issue_details': issueDetails,
        'description': description,
        'photo_path': photoPath,
        'status': status,
        'priority': priority,
        'admin_notes': adminNotes,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'rooms': {
          'room_number': roomNumber,
          'buildings': {'name': buildingName},
        },
        'profiles': {
          'full_name': reporterName,
          'student_number': reporterStudentNumber,
        },
      };

  String get displayTitle =>
      '$category - ${buildingName ?? 'Unknown building'}, ${roomNumber ?? 'Unknown room'}';

  bool get isPending => status == 'Pending';
}
