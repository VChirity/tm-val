class AthleteNote {
  const AthleteNote({
    required this.id,
    required this.athleteId,
    required this.content,
    this.updatedAt,
  });

  final String id;
  final String athleteId;
  final String content;
  final DateTime? updatedAt;

  factory AthleteNote.fromJson(Map<String, dynamic> json) {
    return AthleteNote(
      id: json['id'] as String,
      athleteId: json['athlete_id'] as String,
      content: json['content'] as String? ?? '',
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'athlete_id': athleteId,
      'content': content,
      'updated_at': updatedAt?.toIso8601String(),
    };
  }
}
