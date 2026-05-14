import 'package:intl/intl.dart';

// intl's 'ar' locale gives Arabic grouping (٬) but keeps Latin 0-9. We want
// the Eastern Arabic-Indic digits to match the React source's `toLocaleString
// ('ar-EG')` output, so we substitute on top.
final _grouping = NumberFormat.decimalPattern('ar');
const _arabicIndic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

/// Format an int with Arabic-Indic digits and Arabic thousands separator,
/// e.g. 12345 → "١٢٬٣٤٥".
String formatArabic(int value) {
  final grouped = _grouping.format(value);
  return arabizeDigits(grouped);
}

/// Substitute every Western 0-9 digit in [s] with its Arabic-Indic
/// equivalent. Everything else is passed through. Useful for already-formatted
/// strings like a countdown "12:34:56".
String arabizeDigits(String s) {
  final out = StringBuffer();
  for (final code in s.codeUnits) {
    if (code >= 0x30 && code <= 0x39) {
      out.write(_arabicIndic[code - 0x30]);
    } else {
      out.writeCharCode(code);
    }
  }
  return out.toString();
}
