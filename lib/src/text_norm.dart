/// Text normalization + tag splitting used by search and library grouping.
library;

/// Folds common Latin diacritics to their base letter, lowercases, and
/// collapses whitespace — so "Beyoncé" matches "beyonce" and "Zażółć" is
/// findable from a plain keyboard.
String normText(String s) {
  final lower = s.toLowerCase();
  final out = StringBuffer();
  for (final code in lower.runes) {
    final ch = String.fromCharCode(code);
    out.write(_fold[ch] ?? ch);
  }
  return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// True when every whitespace-separated term of [normQuery] occurs in [blob].
/// Both must already be [normText]-normalized.
bool blobMatches(String blob, String normQuery) {
  if (normQuery.isEmpty) return true;
  for (final term in normQuery.split(' ')) {
    if (term.isNotEmpty && !blob.contains(term)) return false;
  }
  return true;
}

const Map<String, String> _fold = {
  'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a',
  'ă': 'a', 'ą': 'a',
  'ç': 'c', 'ć': 'c', 'č': 'c', 'ĉ': 'c', 'ċ': 'c',
  'ď': 'd', 'đ': 'd', 'ð': 'd',
  'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ĕ': 'e', 'ė': 'e',
  'ę': 'e', 'ě': 'e',
  'ĝ': 'g', 'ğ': 'g', 'ġ': 'g', 'ģ': 'g',
  'ĥ': 'h', 'ħ': 'h',
  'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', 'ĭ': 'i', 'į': 'i',
  'ı': 'i',
  'ĵ': 'j',
  'ķ': 'k',
  'ĺ': 'l', 'ļ': 'l', 'ľ': 'l', 'ł': 'l',
  'ñ': 'n', 'ń': 'n', 'ņ': 'n', 'ň': 'n',
  'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o',
  'ŏ': 'o', 'ő': 'o',
  'ŕ': 'r', 'ŗ': 'r', 'ř': 'r',
  'ś': 's', 'ş': 's', 'š': 's', 'ŝ': 's', 'ș': 's', 'ß': 'ss',
  'ţ': 't', 'ť': 't', 'ț': 't', 'ŧ': 't', 'þ': 'th',
  'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ŭ': 'u', 'ů': 'u',
  'ű': 'u', 'ų': 'u',
  'ŵ': 'w',
  'ý': 'y', 'ÿ': 'y', 'ŷ': 'y',
  'ź': 'z', 'ż': 'z', 'ž': 'z',
  'æ': 'ae', 'œ': 'oe',
};

/// Splits multi-value artist/genre tags on configurable separators, with a
/// never-split blacklist for names that legitimately contain a separator
/// (e.g. "AC/DC"). Comparison against the blacklist is normalization-aware.
class TagSplitter {
  final List<String> separators;
  final Set<String> _blacklistNorm;

  TagSplitter({required this.separators, required Set<String> blacklist})
      : _blacklistNorm = blacklist.map(normText).toSet();

  List<String> split(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return const [];
    if (_blacklistNorm.contains(normText(value))) return [value];

    var parts = <String>[value];
    for (final sep in separators) {
      if (sep.isEmpty) continue;
      final next = <String>[];
      for (final p in parts) {
        // A blacklisted whole value never gets split further.
        if (_blacklistNorm.contains(normText(p))) {
          next.add(p);
          continue;
        }
        next.addAll(p.split(sep));
      }
      parts = next;
    }
    final out = <String>[];
    final seen = <String>{};
    for (final p in parts) {
      final t = p.trim();
      if (t.isEmpty) continue;
      if (seen.add(normText(t))) out.add(t);
    }
    return out.isEmpty ? [value] : out;
  }
}
