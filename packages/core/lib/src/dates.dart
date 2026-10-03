const weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const monthShort = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// UTC timestamp with a fixed six fractional digits, so stored stamps compare
/// correctly as plain strings (last-write-wins relies on that).
String utcStamp(DateTime t) {
  final u = t.toUtc();
  final micros = (u.millisecond * 1000 + u.microsecond).toString().padLeft(6, '0');
  return '${u.year}-${_two(u.month)}-${_two(u.day)}T${_two(u.hour)}:${_two(u.minute)}:${_two(u.second)}.${micros}Z';
}

/// Local calendar date as `YYYY-MM-DD`.
String ymd(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

String today([DateTime? now]) => ymd(now ?? DateTime.now());

DateTime parseYmd(String s) {
  final parts = s.split('-').map(int.parse).toList();
  return DateTime(parts[0], parts[1], parts[2]);
}

String addDays(String date, int days) {
  final d = parseYmd(date);
  return ymd(DateTime(d.year, d.month, d.day + days));
}

/// `Sat 3 Oct`
String prettyDate(String date) {
  final d = parseYmd(date);
  return '${weekdayShort[d.weekday - 1]} ${d.day} ${monthShort[d.month - 1]}';
}

/// Accepts `today`, `tomorrow`, `yesterday`, `+3`, a weekday name (the next
/// one, today excluded) or `YYYY-MM-DD`.
String parseDate(String input, {DateTime? now}) {
  final s = input.trim().toLowerCase();
  final base = today(now);
  if (s == 'today') return base;
  if (s == 'tomorrow') return addDays(base, 1);
  if (s == 'yesterday') return addDays(base, -1);
  if (RegExp(r'^[+-]\d+$').hasMatch(s)) return addDays(base, int.parse(s));
  if (s.length >= 3) {
    final wd = weekdayShort.indexWhere((w) => w.toLowerCase() == s.substring(0, 3));
    if (wd >= 0 && 'monday tuesday wednesday thursday friday saturday sunday'
        .split(' ')
        .any((full) => full.startsWith(s))) {
      final cur = parseYmd(base).weekday - 1;
      final ahead = (wd - cur + 7) % 7;
      return addDays(base, ahead == 0 ? 7 : ahead);
    }
  }
  final m = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(s);
  if (m != null) {
    final d = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    if (d.month == int.parse(m[2]!) && d.day == int.parse(m[3]!)) return ymd(d);
  }
  throw FormatException('Not a date: "$input" (try today, tomorrow, fri, +3 or 2026-10-12)');
}

/// Local time of day as `HH:MM`.
String hm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// A local date and `HH:MM` as a DateTime.
DateTime atTime(String date, String time) {
  final d = parseYmd(date);
  final parts = time.split(':').map(int.parse).toList();
  return DateTime(d.year, d.month, d.day, parts[0], parts[1]);
}

/// When a timed item ends; one without an end is taken to last 30 minutes.
DateTime slotEnd(String date, String start, String? end) {
  final startAt = atTime(date, start);
  final endAt = end == null ? null : atTime(date, end);
  return endAt != null && endAt.isAfter(startAt) ? endAt : startAt.add(const Duration(minutes: 30));
}

String _parseClock(String s) {
  final m = RegExp(r'^(\d{1,2})(?::(\d{2}))?$').firstMatch(s.trim());
  if (m != null) {
    final h = int.parse(m[1]!), min = int.parse(m[2] ?? '0');
    if (h < 24 && min < 60) return '${_two(h)}:${_two(min)}';
  }
  throw FormatException('Not a time: "$s" (use 17:30 or 17:30-18:15)');
}

/// `17:30` or `17:30-18:15` (hyphen or en dash) as (start, end).
(String, String?) parseTimeRange(String input) {
  final parts = input.split(RegExp('[-–]'));
  if (parts.length > 2) throw FormatException('Not a time range: "$input"');
  return (_parseClock(parts[0]), parts.length == 2 ? _parseClock(parts[1]) : null);
}
