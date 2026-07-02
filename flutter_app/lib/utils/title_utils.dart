/// Utilitários para títulos/destaques e filtro por ano.
class TitleUtils {
  TitleUtils._();

  static final _yearPattern = RegExp(r'\b(19|20)\d{2}\b');

  static String translateHighlight(String text) {
    const replacements = {
      'Singles titles:': 'Títulos em simples:',
      'Doubles titles:': 'Títulos em duplas:',
      'Career titles:': 'Títulos na carreira:',
      ' singles:': ' simples:',
      ' doubles:': ' duplas:',
      ' mixed:': ' mista:',
      'Winner': 'Campeão',
      'Champion': 'Campeão',
      'Gold': 'Ouro',
      'Silver': 'Prata',
      'Bronze': 'Bronze',
    };

    var translated = text.trim();
    for (final entry in replacements.entries) {
      translated = translated.replaceAll(entry.key, entry.value);
    }
    return translated;
  }

  static int? extractYear(String title) {
    final match = _yearPattern.firstMatch(title);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(0)!);
  }

  static List<String> filterFromYear(List<String> titles, int? fromYear) {
    if (fromYear == null) {
      return titles;
    }
    return titles.where((title) {
      final year = extractYear(title);
      if (year == null) {
        return true;
      }
      return year >= fromYear;
    }).toList();
  }

  static List<int> availableYears(List<String> titles) {
    final years = titles.map(extractYear).whereType<int>().toSet().toList()
      ..sort();
    return years;
  }

  static List<String> splitTournamentList(String value) {
    return value
        .split(RegExp(r',|\t|\n'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
  }

  static List<String> mergeUnique(List<String> a, List<String> b) {
    final seen = <String>{};
    final merged = <String>[];
    for (final item in [...a, ...b]) {
      final text = translateHighlight(item);
      if (text.isEmpty || seen.contains(text)) {
        continue;
      }
      seen.add(text);
      merged.add(text);
    }
    return merged;
  }
}
