class Athlete {
  const Athlete({
    required this.id,
    required this.name,
    required this.gender,
    this.ranking,
    this.ittfId,
    this.rankingPoints,
    this.age,
    this.height,
    this.hand,
    this.championshipsWon = const [],
    this.photoUrl,
    this.countryCode,
    this.listedInHome = true,
    this.profileHydrated = true,
    this.updatedAt,
    this.hasNote = false,
  });

  final String id;
  final String name;
  final String gender;
  final int? ranking;
  final String? ittfId;
  final int? rankingPoints;
  final int? age;
  final double? height;
  final String? hand;
  final List<String> championshipsWon;
  final String? photoUrl;
  final String? countryCode;
  final bool listedInHome;
  final bool profileHydrated;
  final DateTime? updatedAt;
  final bool hasNote;

  factory Athlete.fromJson(Map<String, dynamic> json, {bool hasNote = false}) {
    final championships = json['championships_won'];
    return Athlete(
      id: json['id'] as String,
      name: json['name'] as String,
      gender: json['gender'] as String,
      ranking: (json['ranking'] as num?)?.toInt(),
      ittfId: json['ittf_id']?.toString(),
      rankingPoints: (json['ranking_points'] as num?)?.toInt(),
      age: (json['age'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toDouble(),
      hand: json['hand'] as String?,
      championshipsWon: championships is List
          ? championships.map((item) => item.toString()).toList()
          : const [],
      photoUrl: json['photo_url'] as String?,
      countryCode: json['country_code'] as String?,
      listedInHome: json['listed_in_home'] as bool? ?? true,
      profileHydrated: json['profile_hydrated'] as bool? ?? true,
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
      'ittf_id': ittfId,
      'ranking': ranking,
      'ranking_points': rankingPoints,
      'age': age,
      'height': height,
      'hand': hand,
      'championships_won': championshipsWon,
      'photo_url': photoUrl,
      'country_code': countryCode,
      'listed_in_home': listedInHome,
      'profile_hydrated': profileHydrated,
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  Athlete copyWith({bool? hasNote}) {
    return Athlete(
      id: id,
      name: name,
      gender: gender,
      ranking: ranking,
      ittfId: ittfId,
      rankingPoints: rankingPoints,
      age: age,
      height: height,
      hand: hand,
      championshipsWon: championshipsWon,
      photoUrl: photoUrl,
      countryCode: countryCode,
      listedInHome: listedInHome,
      profileHydrated: profileHydrated,
      updatedAt: updatedAt,
      hasNote: hasNote ?? this.hasNote,
    );
  }
}
