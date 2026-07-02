class Athlete {
  const Athlete({
    required this.id,
    required this.name,
    required this.gender,
    required this.ranking,
    this.rankingPoints,
    this.age,
    this.height,
    this.hand,
    this.championshipsWon = const [],
    this.photoUrl,
    this.updatedAt,
    this.hasNote = false,
  });

  final String id;
  final String name;
  final String gender;
  final int ranking;
  final int? rankingPoints;
  final int? age;
  final double? height;
  final String? hand;
  final List<String> championshipsWon;
  final String? photoUrl;
  final DateTime? updatedAt;
  final bool hasNote;

  factory Athlete.fromJson(Map<String, dynamic> json, {bool hasNote = false}) {
    final championships = json['championships_won'];
    return Athlete(
      id: json['id'] as String,
      name: json['name'] as String,
      gender: json['gender'] as String,
      ranking: json['ranking'] as int,
      rankingPoints: json['ranking_points'] as int?,
      age: json['age'] as int?,
      height: (json['height'] as num?)?.toDouble(),
      hand: json['hand'] as String?,
      championshipsWon: championships is List
          ? championships.map((item) => item.toString()).toList()
          : const [],
      photoUrl: json['photo_url'] as String?,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
      hasNote: hasNote,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'gender': gender,
      'ranking': ranking,
      'ranking_points': rankingPoints,
      'age': age,
      'height': height,
      'hand': hand,
      'championships_won': championshipsWon,
      'photo_url': photoUrl,
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  Athlete copyWith({bool? hasNote}) {
    return Athlete(
      id: id,
      name: name,
      gender: gender,
      ranking: ranking,
      rankingPoints: rankingPoints,
      age: age,
      height: height,
      hand: hand,
      championshipsWon: championshipsWon,
      photoUrl: photoUrl,
      updatedAt: updatedAt,
      hasNote: hasNote ?? this.hasNote,
    );
  }
}
