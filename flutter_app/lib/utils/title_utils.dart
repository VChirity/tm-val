/// Utilitários para títulos/destaques, limpeza, filtros e contagens.
class TitleUtils {
  TitleUtils._();

  static final _yearPattern = RegExp(r'\b(19|20)\d{2}\b');
  static final _summarySingles = RegExp(r'^Títulos em simples:\s*\d+', caseSensitive: false);
  static final _summaryDoubles = RegExp(r'^Títulos em duplas:\s*\d+', caseSensitive: false);
  static final _summaryCareer = RegExp(r'^Títulos na carreira:\s*\d+', caseSensitive: false);
  static final _citePattern = RegExp(r'\{\{[^}]+\}\}', dotAll: true);
  static final _urlPattern = RegExp(r'https?://\S+');
  static final _extLinkPattern = RegExp(r'\[(?:https?://[^\]|]+\|)?([^\]]+)\]');
  static final _wikiBoldPattern = RegExp(r"'{2,5}([^']+)'{2,5}");

  static final _wttPattern = RegExp(
    r'\bwtt\b|grand smash|star contender|contender|cup finals|wtt finals|wtt champions|smash',
    caseSensitive: false,
  );
  static final _nacionalPattern = RegExp(
    r'pan.?american|panameric|jogos pan|pan-americano|patc|sul.?americ|'
    r'\b(lima|santiago|havana|guaynabo|asunción|cartagena|san juan|'
    r'toronto|santo domingo|rock hill|san salvador|buenos aires)\b',
    caseSensitive: false,
  );

  static String translateHighlight(String text) {
    const replacements = [
      ('World Table Tennis Championships', 'Campeonato Mundial'),
      ('World Championships', 'Campeonato Mundial'),
      ('Table Tennis World Cup', 'Copa do Mundo'),
      ('Pan American Table Tennis Championships', 'Pan-Americano'),
      ('Pan American Games', 'Jogos Pan-Americanos'),
      ('Olympic Games', 'Olimpíadas'),
      ('Singles titles:', 'Títulos em simples:'),
      ('Doubles titles:', 'Títulos em duplas:'),
      ('Career titles:', 'Títulos na carreira:'),
      (' singles:', ' simples:'),
      (' doubles:', ' duplas:'),
      (' mixed:', ' mista:'),
      ('Mixed doubles', 'Duplas mistas'),
      ('Winner', 'Campeão'),
      ('Champion', 'Campeão'),
      ('Gold', 'Ouro'),
      ('Silver', 'Prata'),
      ('Bronze', 'Bronze'),
      ('Runner-up', '2° lugar'),
      ('Semifinals', '4° lugar'),
      ('Quarterfinals', '5-8° lugar'),
      ('Group stage', ''),
      ('Singapore', 'Singapura'),
    ];

    var translated = text.trim();
    for (final entry in replacements) {
      translated = translated.replaceAll(entry.$1, entry.$2);
    }
    return translated.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String cleanTitle(String text) {
    var cleaned = translateHighlight(text);
    cleaned = cleaned.replaceAll(_citePattern, '');
    cleaned = cleaned.replaceAll(_urlPattern, '');
    cleaned = cleaned.replaceAllMapped(
      _extLinkPattern,
      (match) => match.group(1)?.trim() ?? '',
    );
    cleaned = cleaned.replaceAllMapped(
      _wikiBoldPattern,
      (match) => match.group(1) ?? '',
    );
    cleaned = cleaned.replaceAll('[', '').replaceAll(']', '');
    return cleaned
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'[ .,;]+$'), '');
  }

  static int? extractYear(String title) {
    final match = _yearPattern.firstMatch(title);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(0)!);
  }

  static bool isSummaryLine(String title) {
    final text = cleanTitle(title);
    return _summarySingles.hasMatch(text) ||
        _summaryDoubles.hasMatch(text) ||
        _summaryCareer.hasMatch(text) ||
        text.startsWith('Último resultado:');
  }

  static bool isDetailLine(String title) => !isSummaryLine(title);

  static TitleCategory detectCategory(String title) {
    final text = cleanTitle(title).toLowerCase();
    if (_wttPattern.hasMatch(text)) {
      return TitleCategory.wtt;
    }
    if (_nacionalPattern.hasMatch(text)) {
      return TitleCategory.nacional;
    }
    return TitleCategory.outros;
  }

  static bool matchesCategory(String title, TitleCategory category) {
    if (category == TitleCategory.all) {
      return true;
    }
    return detectCategory(title) == category;
  }

  static List<String> filterFromYear(List<String> titles, int? fromYear) {
    if (fromYear == null) {
      return titles;
    }
    return titles.where((title) {
      final year = extractYear(title);
      if (year == null) {
        return false;
      }
      return year >= fromYear;
    }).toList();
  }

  static List<String> filterTitles(
    List<String> titles, {
    int? fromYear,
    TitleCategory category = TitleCategory.all,
  }) {
    return titles
        .map(cleanTitle)
        .where(isDetailLine)
        .where((title) => matchesCategory(title, category))
        .where((title) {
          if (fromYear == null) {
            return true;
          }
          final year = extractYear(title);
          return year != null && year >= fromYear;
        })
        .toList();
  }

  static bool isSinglesLine(String title) {
    final text = cleanTitle(title).toLowerCase();
    if (text.contains('duplas') || text.contains('equipe') || text.contains('mista')) {
      return false;
    }
    return text.contains('(simples)') ||
        text.contains(' simples:') ||
        (text.contains('campeão') && !text.contains('duplas'));
  }

  static bool isDoublesLine(String title) {
    final text = cleanTitle(title).toLowerCase();
    if (text.contains('mista')) {
      return false;
    }
    return text.contains('(duplas)') || text.contains(' duplas:');
  }

  static bool isWinLine(String title) {
    if (isSummaryLine(title)) {
      return false;
    }
    final text = cleanTitle(title).toLowerCase();
    return text.contains('campeão') ||
        text.contains('campeã') ||
        text.contains(' ouro') ||
        text.startsWith('ouro') ||
        text.contains(': ouro');
  }

  static TitleCounts countTitles(List<String> titles) {
    var singles = 0;
    var doubles = 0;
    var career = 0;

    for (final title in titles) {
      if (!isWinLine(title)) {
        continue;
      }
      career++;
      if (isSinglesLine(title)) {
        singles++;
      } else if (isDoublesLine(title)) {
        doubles++;
      }
    }

    return TitleCounts(
      singles: singles,
      doubles: doubles,
      career: career,
    );
  }

  static List<String> buildDisplayTitles(
    List<String> titles, {
    int? fromYear,
    TitleCategory category = TitleCategory.all,
  }) {
    final cleaned = titles.map(cleanTitle).where((title) => title.isNotEmpty).toList();
    final filteredDetails = filterTitles(
      cleaned,
      fromYear: fromYear,
      category: category,
    );

    final hasFilter = fromYear != null || category != TitleCategory.all;
    if (!hasFilter) {
      final summaries = cleaned.where(isSummaryLine).where(
            (title) => !title.startsWith('Último resultado:'),
          );
      final details = cleaned.where(isDetailLine).toList();
      return [...summaries, ...details];
    }

    return filteredDetails;
  }

  static List<int> availableYears(List<String> titles) {
    final years = titles
        .map(cleanTitle)
        .where(isDetailLine)
        .map(extractYear)
        .whereType<int>()
        .toSet()
        .toList()
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
      final text = cleanTitle(item);
      if (text.isEmpty || seen.contains(text)) {
        continue;
      }
      seen.add(text);
      merged.add(text);
    }
    return merged;
  }
}

enum TitleCategory {
  all,
  wtt,
  nacional,
  outros,
}

class TitleCounts {
  const TitleCounts({
    required this.singles,
    required this.doubles,
    required this.career,
  });

  final int singles;
  final int doubles;
  final int career;
}
