/// Utilitários para títulos/destaques, limpeza, filtros e contagens.
class TitleUtils {
  TitleUtils._();

  static final _yearPattern = RegExp(r'\b(19|20)\d{2}\b');
  static final _dupYearPattern = RegExp(r'\b((?:19|20)\d{2})(?:\s+\1)+\b');
  static final _summarySingles = RegExp(r'^Títulos em simples:\s*\d+', caseSensitive: false);
  static final _summaryDoubles = RegExp(r'^Títulos em duplas:\s*\d+', caseSensitive: false);
  static final _summaryCareer = RegExp(r'^Títulos na carreira:\s*\d+', caseSensitive: false);
  static final _citePattern = RegExp(r'\{\{[^}]+\}\}', dotAll: true);
  static final _urlPattern = RegExp(r'https?://\S+');
  static final _extLinkPattern = RegExp(r'\[(?:https?://[^\]|]+\|)?([^\]]+)\]');
  static final _wikiBoldPattern = RegExp(r"'{2,5}([^']+)'{2,5}");
  static final _resultPattern = RegExp(
    r'^\s*(Campeão|Campeã|2° lugar|3° lugar|4° lugar|5-8° lugar)\s*(.*)$',
    caseSensitive: false,
  );

  static final _wttPattern = RegExp(
    r'\bwtt\b|grand smash|star contender|contender|cup finals|wtt finals|wtt champions|smash',
    caseSensitive: false,
  );
  /// Títulos domésticos brasileiros (CBTM / Brasileirão / ranking nacional).
  static final _nacionalPattern = RegExp(
    r'^nacional\s*:|'
    r'brasileir[aã]o|campeonato brasileiro|copa brasil\b|tmb platinum|'
    r'\bcbtm\b|absoluto a|ranking nacional|torneio nacional',
    caseSensitive: false,
  );
  /// Continentais das Américas (Pan, sul-americano, latino-americano…).
  static final _panAmPattern = RegExp(
    r'pan.?american|panameric|jogos pan|pan-americano|patc|sul.?americ|'
    r'latino.?american|latin american|copa das am|'
    r'\b(lima|santiago|havana|guaynabo|asunción|cartagena|san juan|'
    r'toronto|santo domingo|rock hill|san salvador)\b',
    caseSensitive: false,
  );
  static final _eventAsLocationPattern = RegExp(
    r'championship|cup|contender|smash|finals|olympi|americas|latin|'
    r'copa do mundo|copa das|pan.?americano|mundial',
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
    cleaned = cleaned.replaceAllMapped(_dupYearPattern, (m) => m.group(1)!);
    return cleaned
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'[ .,;]+$'), '');
  }

  /// Normaliza texto de título (ano duplicado, identidade de evento/local).
  static String canonicalizeTitle(String title) {
    var text = cleanTitle(title.trim());
    if (text.isEmpty) return '';

    text = text.replaceAllMapped(_dupYearPattern, (m) => m.group(1)!);
    // Títulos nacionais BR: preservar nome do evento (Brasileirão / TMB…).
    if (RegExp(r'^nacional\s*:', caseSensitive: false).hasMatch(text)) {
      return text.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    if (!text.contains(':')) return text;

    final parts = text.split(':');
    var event = parts.first.trim();
    final rest = parts.sublist(1).join(':');

    final lowerEvent = event.toLowerCase();
    if (RegExp(r'americas?\s+cup|copa das am', caseSensitive: false).hasMatch(event)) {
      event = 'Copa das Américas';
    } else if (lowerEvent.contains('pan-americano') ||
        lowerEvent.contains('pan american')) {
      event = 'Pan-Americano';
    } else if (lowerEvent.contains('grand smash') || lowerEvent.contains('europe smash')) {
      event = 'WTT Grand Smash';
    } else if (lowerEvent.contains('wtt finals') || lowerEvent.contains('cup finals')) {
      event = 'WTT Finals';
    } else if (lowerEvent.contains('wtt champions')) {
      event = 'WTT Champions';
    } else if (lowerEvent.contains('star contender')) {
      event = 'WTT Star Contender';
    } else if (RegExp(r'\bcontender\b', caseSensitive: false).hasMatch(lowerEvent)) {
      event = 'WTT Contender';
    } else if (lowerEvent.contains('copa do mundo') || lowerEvent.contains('world cup')) {
      event = 'Copa do Mundo';
    } else if (lowerEvent.contains('campeonato mundial')) {
      event = 'Campeonato Mundial';
    }

    final resultMatch = _resultPattern.firstMatch(rest.trim());
    if (resultMatch == null) return '$event:$rest';

    final resultPt = resultMatch.group(1)!;
    final after = resultMatch.group(2) ?? '';
    final paren = RegExp(r'\(([^)]*)\)').firstMatch(after);
    if (paren == null) return '$event: $resultPt';

    final inner = paren.group(1)!;
    final year = extractYear(inner)?.toString() ?? extractYear(text)?.toString() ?? '';
    var category = 'Simples';
    final lowerInner = inner.toLowerCase();
    if (lowerInner.contains('duplas mistas') || lowerInner.contains('mista')) {
      category = 'Duplas mistas';
    } else if (lowerInner.contains('duplas')) {
      category = 'Duplas';
    } else if (lowerInner.contains('equipe')) {
      category = 'Equipe';
    } else if (lowerInner.contains('simples')) {
      category = 'Simples';
    }

    var locPart = inner.contains('—') ? inner.split('—').first : inner;
    locPart = locPart.replaceAll(_yearPattern, '').trim();
    locPart = locPart.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (locPart.isNotEmpty && _eventAsLocationPattern.hasMatch(locPart)) {
      locPart = '';
    }

    if (locPart.isNotEmpty && year.isNotEmpty) {
      return '$event: $resultPt ($locPart $year — $category)';
    }
    if (year.isNotEmpty) {
      return '$event: $resultPt ($year — $category)';
    }
    if (locPart.isNotEmpty) {
      return '$event: $resultPt ($locPart — $category)';
    }
    return '$event: $resultPt';
  }

  static String _normalizeIdentityEvent(String event) {
    final lower = event.toLowerCase();
    if (lower.startsWith('nacional')) return 'nacional';
    if (lower.contains('campeonato mundial') || lower.contains('world table tennis')) {
      return 'campeonato mundial';
    }
    if (lower.contains('jogos pan') || lower.contains('pan american games')) {
      return 'jogos pan-americanos';
    }
    if (lower.contains('pan-americano') || lower.contains('pan american')) {
      return 'pan-americano';
    }
    if (lower.contains('copa das am') || lower.contains('americas cup')) {
      return 'copa das americas';
    }
    if (lower.contains('copa do mundo') || lower.contains('world cup')) {
      return 'copa do mundo';
    }
    if (lower.contains('olimp')) return 'olimpiadas';
    if (lower.contains('wtt grand smash') ||
        lower.contains('grand smash') ||
        lower.contains('europe smash')) {
      return 'wtt grand smash';
    }
    if (lower.contains('wtt finals') || lower.contains('cup finals')) {
      return 'wtt finals';
    }
    if (lower.contains('wtt star contender') || lower.contains('star contender')) {
      return 'wtt star contender';
    }
    if (lower.contains('wtt contender') ||
        RegExp(r'\bcontender\b').hasMatch(lower)) {
      return 'wtt contender';
    }
    if (lower.contains('wtt champions')) return 'wtt champions';
    return lower;
  }

  static String _normalizeIdentityLocation(String location) {
    var loc = location.toLowerCase().trim();
    loc = loc.replaceAll(RegExp(r'[^a-z0-9áàâãéêíóôõúç\s]'), ' ');
    loc = loc.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (loc.isEmpty || _eventAsLocationPattern.hasMatch(loc)) return '';
    if (loc == 'macao') return 'macau';
    if (loc == 'singapore') return 'singapura';
    return loc;
  }

  /// Chave de identidade: (evento, ano, local, categoria).
  static (String, String, String, String) titleIdentity(String title) {
    final text = canonicalizeTitle(title);
    final year = extractYear(text)?.toString() ?? '';
    final lower = text.toLowerCase();
    var category = 'simples';
    if (lower.contains('duplas mistas') || lower.contains('— mista')) {
      category = 'mista';
    } else if (lower.contains('duplas')) {
      category = 'duplas';
    } else if (lower.contains('equipe')) {
      category = 'equipe';
    }

    final rawEvent = text.contains(':') ? text.split(':').first.trim() : text;
    final event = _normalizeIdentityEvent(rawEvent);
    var location = '';
    final paren = RegExp(r'\(([^)]+)\)').firstMatch(text);
    if (paren != null) {
      final locPart = paren.group(1)!.split('—').first;
      location = _normalizeIdentityLocation(locPart);
    }
    return (event, year, location, category);
  }

  static int _titlePriority(String title) {
    final lower = title.toLowerCase();
    if (lower.contains('campeão') || lower.contains('campeã')) return 4;
    if (lower.contains('2° lugar') || lower.contains('prata')) return 3;
    if (lower.contains('3° lugar') || lower.contains('bronze')) return 2;
    if (lower.contains('4° lugar') || lower.contains('5-8')) return 1;
    return 0;
  }

  static (String, String, String, String) _compatibleIdentityKey(
    Map<(String, String, String, String), (int, String)> best,
    (String, String, String, String) key,
  ) {
    final (event, year, loc, cat) = key;
    if (loc.isNotEmpty) {
      final empty = (event, year, '', cat);
      if (best.containsKey(empty)) return empty;
    } else {
      for (final existing in best.keys) {
        if (existing.$1 == event &&
            existing.$2 == year &&
            existing.$3.isNotEmpty &&
            existing.$4 == cat) {
          return existing;
        }
      }
    }
    return key;
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
    if (_panAmPattern.hasMatch(text)) {
      return TitleCategory.panAm;
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
        .map(canonicalizeTitle)
        .where((title) => title.isNotEmpty)
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

  static List<String> _dedupeByIdentity(List<String> titles) {
    final best = <(String, String, String, String), (int, String)>{};
    final order = <(String, String, String, String)>[];

    for (final raw in titles) {
      final text = canonicalizeTitle(raw);
      if (text.isEmpty) continue;

      final key = _compatibleIdentityKey(best, titleIdentity(text));
      final priority = _titlePriority(text);
      final existing = best[key];
      if (existing == null) {
        order.add(key);
        best[key] = (priority, text);
      } else if (priority > existing.$1) {
        best[key] = (priority, text);
      } else if (priority == existing.$1 && text.length > existing.$2.length) {
        best[key] = (priority, text);
      }
    }

    final seen = <String>{};
    final merged = <String>[];
    for (final key in order) {
      final entry = best[key];
      if (entry == null) continue;
      final text = entry.$2;
      if (seen.contains(text)) continue;
      seen.add(text);
      merged.add(text);
    }
    return merged;
  }

  static List<String> buildDisplayTitles(
    List<String> titles, {
    int? fromYear,
    TitleCategory category = TitleCategory.all,
  }) {
    final cleaned = titles
        .map(canonicalizeTitle)
        .where((title) => title.isNotEmpty)
        .toList();
    final deduped = _dedupeByIdentity(cleaned);

    final hasFilter = fromYear != null || category != TitleCategory.all;
    if (!hasFilter) {
      final summaries = deduped.where(isSummaryLine).where(
            (title) => !title.startsWith('Último resultado:'),
          );
      final details = deduped.where(isDetailLine).toList();
      return [...summaries, ...details];
    }

    return filterTitles(
      deduped,
      fromYear: fromYear,
      category: category,
    );
  }

  static List<int> availableYears(List<String> titles) {
    final years = titles
        .map(canonicalizeTitle)
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
    return _dedupeByIdentity([...a, ...b]);
  }
}

enum TitleCategory {
  all,
  wtt,
  nacional,
  panAm,
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
