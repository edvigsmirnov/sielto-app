/// Substitutions within Latin-1 Supplement and Latin Extended-A.
const String _plain = 'acdeghijklnorstuwyzACDEGHIJKLNORSTUWYZ';
const String _accented = 'áçðéğĥíĵķłñóřšťúŵýžÁÇÐÉĞĤÍĴĶŁÑÓŘŠŤÚŴÝŽ';

final Map<String, String> _accents = Map<String, String>.fromIterables(
  _plain.split(''),
  _accented.split(''),
);

final RegExp _letter = RegExp('[A-Za-z]');

/// Accents letters, pads by [expansion] and brackets the result. Text inside
/// `{}` is kept.
String pseudolocalize(String source, {double expansion = 0.35}) {
  assert(_plain.length == _accented.length, 'substitution table is unpaired');

  final StringBuffer out = StringBuffer('[');
  int depth = 0;
  int letters = 0;

  for (final String ch in source.split('')) {
    if (ch == '{') {
      depth++;
      out.write(ch);
    } else if (ch == '}') {
      if (depth > 0) depth--;
      out.write(ch);
    } else if (depth > 0) {
      out.write(ch);
    } else {
      if (_letter.hasMatch(ch)) letters++;
      out.write(_accents[ch] ?? ch);
    }
  }

  final int pad = (letters * expansion).round();
  if (pad > 0) {
    out.write(' ');
    out.write('·' * pad);
  }
  out.write(']');
  return out.toString();
}
