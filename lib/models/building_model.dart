class BuildingModel {
  final String id;
  final String name;
  const BuildingModel({required this.id, required this.name});

  factory BuildingModel.fromJson(Map<String, dynamic> json) =>
      BuildingModel(id: json['id'] as String, name: json['name'] as String);
}
