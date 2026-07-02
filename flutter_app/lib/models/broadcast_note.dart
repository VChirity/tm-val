class BroadcastNote {
  const BroadcastNote({
    required this.id,
    required this.content,
    this.updatedAt,
  });

  final String id;
  final String content;
  final DateTime? updatedAt;

  factory BroadcastNote.fromJson(Map<String, dynamic> json) {
    return BroadcastNote(
      id: json['id'] as String,
      content: json['content'] as String? ?? '',
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }
}
