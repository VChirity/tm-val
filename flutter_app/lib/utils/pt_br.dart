/// Traduções e formatação em português do Brasil.
class PtBr {
  PtBr._();

  static String genderLabel(String gender) =>
      gender == 'male' ? 'Masculino' : 'Feminino';

  static String handLabel(String? hand) {
    if (hand == null || hand.trim().isEmpty) {
      return 'Não informada';
    }

    final normalized = hand.toLowerCase();
    if (normalized.contains('right') || normalized == 'r') {
      return 'Destro';
    }
    if (normalized.contains('left') || normalized == 'l') {
      return 'Canhoto';
    }
    if (normalized.contains('both') || normalized.contains('amb')) {
      return 'Ambidestro';
    }
    return hand;
  }

  static String formatRankingPoints(int? points) {
    if (points == null) {
      return 'Pontuação não informada';
    }
    final formatted = _formatNumber(points);
    return '$formatted pts';
  }

  static String formatAge(int? age) {
    if (age == null) {
      return 'Não informada';
    }
    return '$age anos';
  }

  static String translateHighlight(String title) {
    var text = title.trim();

    const replacements = <String, String>{
      'Singles titles:': 'Títulos em simples:',
      'Doubles titles:': 'Títulos em duplas:',
      'Career titles:': 'Títulos na carreira:',
      ' singles:': ' simples:',
      ' doubles:': ' duplas:',
      ' mixed:': ' mista:',
    };

    for (final entry in replacements.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }

    return text;
  }

  static String _formatNumber(int value) {
    final raw = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final pos = raw.length - i;
      buffer.write(raw[i]);
      if (pos > 1 && pos % 3 == 1) {
        buffer.write('.');
      }
    }
    return buffer.toString();
  }
}
