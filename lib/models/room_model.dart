class RoomModel {
  final String id;
  final String buildingId;
  final String roomNumber;
  const RoomModel({required this.id, required this.buildingId, required this.roomNumber});

  factory RoomModel.fromJson(Map<String, dynamic> json) => RoomModel(
        id: json['id'] as String,
        buildingId: json['building_id'] as String,
        roomNumber: json['room_number'] as String,
      );
}
