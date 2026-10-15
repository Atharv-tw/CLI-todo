import 'dates.dart';
import 'models.dart';
import 'store.dart';

/// Minutes after midnight of `HH:MM`.
int clockMinutes(String hhmm) => int.parse(hhmm.substring(0, 2)) * 60 + int.parse(hhmm.substring(3, 5));

/// `HH:MM` for minutes after midnight; past midnight wraps (25:30 is 01:30).
String clockText(int minutes) {
  final m = minutes % (24 * 60);
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

/// How long a task is expected to take: its time slot, else its estimate,
/// else half an hour.
int taskMinutes(Task t) {
  if (t.startTime != null && t.endTime != null) return clockMinutes(t.endTime!) - clockMinutes(t.startTime!);
  return t.estimateMin ?? 30;
}

int? _median(List<int> xs) {
  if (xs.isEmpty) return null;
  final s = [...xs]..sort();
  return s[s.length ~/ 2];
}

/// What one day actually looked like, from what was recorded on it.
class DayRecord {
  DayRecord({
    required this.date,
    required this.wake,
    required this.bed,
    required this.planned,
    required this.done,
    required this.plannedMin,
    required this.doneMin,
    required this.protectedPlanned,
    required this.protectedDone,
    required this.focusMin,
  });

  final String date;

  /// First sign of being awake after a night's sleep (screen use, a diary
  /// entry or a tick after three quiet hours), in minutes after midnight;
  /// null if nothing was recorded.
  final int? wake;

  /// Last sign of being awake before the night's sleep, in minutes after
  /// midnight of [date] (so 01:30 the next day is 1530).
  final int? bed;
  final int planned;
  final int done;
  final int plannedMin;
  final int doneMin;
  final int protectedPlanned;
  final int protectedDone;
  final int focusMin;

  Map<String, Object?> toJson() => {
        'date': date,
        'wake': wake == null ? null : clockText(wake!),
        'bed': bed == null ? null : clockText(bed!),
        'bed_after_midnight': bed != null && bed! >= 24 * 60,
        'planned': planned,
        'done': done,
        'planned_min': plannedMin,
        'done_min': doneMin,
        'protected_planned': protectedPlanned,
        'protected_done': protectedDone,
        'focus_min': focusMin,
      };
}

/// Facts about recent days, computed rather than guessed, for planning.
class Stats {
  Stats({required this.days, required this.backlog, required this.overdue, required this.dueSoon, required this.unprocessed});

  /// Oldest first.
  final List<DayRecord> days;
  final int backlog;
  final int overdue;
  final List<Task> dueSoon;
  final int unprocessed;

  List<DayRecord> get _recorded => [for (final d in days) if (d.planned > 0 || d.wake != null) d];

  /// Typical wake time over the last [n] days that recorded one.
  int? wakeOver(int n) => _median([for (final d in days.reversed.where((d) => d.wake != null).take(n)) d.wake!]);
  int? bedOver(int n) => _median([for (final d in days.reversed.where((d) => d.bed != null).take(n)) d.bed!]);

  double? get completion {
    final p = _recorded.fold(0, (s, d) => s + d.planned);
    return p == 0 ? null : _recorded.fold(0, (s, d) => s + d.done) / p;
  }

  double? get protectedCompletion {
    final p = days.fold(0, (s, d) => s + d.protectedPlanned);
    return p == 0 ? null : days.fold(0, (s, d) => s + d.protectedDone) / p;
  }

  int? get doneMinPerDay => _recorded.isEmpty ? null : _recorded.fold(0, (s, d) => s + d.doneMin) ~/ _recorded.length;

  Map<String, Object?> toJson() => {
        'days': [for (final d in days) d.toJson()],
        'typical': {
          'wake_last_3_days': wakeOver(3) == null ? null : clockText(wakeOver(3)!),
          'wake_last_7_days': wakeOver(7) == null ? null : clockText(wakeOver(7)!),
          'bed_last_3_days': bedOver(3) == null ? null : clockText(bedOver(3)!),
          'completion': completion == null ? null : (completion! * 100).round(),
          'protected_completion': protectedCompletion == null ? null : (protectedCompletion! * 100).round(),
          'done_min_per_day': doneMinPerDay,
        },
        'backlog': backlog,
        'overdue': overdue,
        'due_soon': [for (final t in dueSoon) {'id': t.id, 'title': t.title, 'due': t.dueDate, 'date': t.date}],
        'unprocessed_entries': unprocessed,
      };
}

/// One thing wrong with a plan.
class PlanIssue {
  PlanIssue(this.code, this.message, [this.taskId]);
  final String code;
  final String message;
  final String? taskId;

  Map<String, Object?> toJson() => {'code': code, 'message': message, 'task': ?taskId};
}

/// The verdict on a day's plan. Errors must be fixed (or, if a trade-off is
/// unavoidable, explained); warnings must be mentioned.
class PlanCheck {
  PlanCheck({
    required this.date,
    required this.start,
    required this.end,
    required this.capacity,
    required this.plannedMin,
    required this.errors,
    required this.warnings,
  });

  final String date;
  final int start;
  final int end;
  final double capacity;
  final int plannedMin;
  final List<PlanIssue> errors;
  final List<PlanIssue> warnings;

  bool get ok => errors.isEmpty;
  int get budgetMin => ((end - start).clamp(0, 24 * 60) * capacity).floor();

  Map<String, Object?> toJson() => {
        'date': date,
        'ok': ok,
        'day_starts': clockText(start),
        'day_ends': clockText(end),
        'budget_min': budgetMin,
        'planned_min': plannedMin,
        'capacity': capacity,
        'errors': [for (final e in errors) e.toJson()],
        'warnings': [for (final w in warnings) w.toJson()],
      };
}

/// The most new commitments a plan may put into one day.
const maxNewPerDay = 5;

extension Planning on Store {
  /// Facts about the [days] days up to and including [until] (today).
  Stats stats({int days = 14, String? until}) {
    final last = until ?? today();
    final first = addDays(last, -(days - 1));

    // Signs of being awake, oldest first: screen use (each busy hour counts
    // at its start and end), diary entries and ticks.
    final marks = <DateTime>[];
    for (final r in db.select(
      'SELECT date, hour, SUM(seconds) AS s FROM screen_usage WHERE deleted_at IS NULL AND date BETWEEN ? AND ? '
      'GROUP BY date, hour HAVING s >= 300',
      [addDays(first, -1), addDays(last, 1)],
    )) {
      final at = parseYmd(r['date'] as String).add(Duration(hours: r['hour'] as int));
      marks..add(at)..add(at.add(const Duration(minutes: 59)));
    }
    for (final e in diary(from: addDays(first, -1), to: addDays(last, 1), author: DiaryEntry.me)) {
      marks.add(e.createdAt);
    }
    for (final r in db.select(
      'SELECT done_at FROM tasks WHERE deleted_at IS NULL AND done_at IS NOT NULL AND date BETWEEN ? AND ?',
      [addDays(first, -2), addDays(last, 1)],
    )) {
      marks.add(DateTime.parse(r['done_at'] as String).toLocal());
    }
    marks.sort();

    // Sleep is the first quiet stretch of three hours or more. Waking is the
    // first sign of life after one; staying up until 05:00 is not waking at 05:00.
    const sleep = Duration(hours: 3);
    int? wakeOn(String d) {
      final from = parseYmd(d).add(const Duration(hours: 4)), to = parseYmd(addDays(d, 1));
      for (var i = 0; i < marks.length; i++) {
        final t = marks[i];
        if (t.isBefore(from) || !t.isBefore(to)) continue;
        if (i == 0 || t.difference(marks[i - 1]) >= sleep) return t.difference(parseYmd(d)).inMinutes;
      }
      return null;
    }

    int? bedOn(String d) {
      final from = parseYmd(d).add(const Duration(hours: 18)), to = parseYmd(addDays(d, 1)).add(const Duration(hours: 12));
      for (var i = 0; i < marks.length; i++) {
        final t = marks[i];
        if (t.isBefore(from) || !t.isBefore(to)) continue;
        if (i == marks.length - 1 || marks[i + 1].difference(t) >= sleep) return t.difference(parseYmd(d)).inMinutes;
      }
      return null;
    }

    final records = <DayRecord>[];
    for (var d = first; d.compareTo(last) <= 0; d = addDays(d, 1)) {
      final day = tasks(from: d, to: d);
      records.add(DayRecord(
        date: d,
        wake: wakeOn(d),
        bed: bedOn(d),
        planned: day.length,
        done: day.where((t) => t.done).length,
        plannedMin: day.fold(0, (s, t) => s + taskMinutes(t)),
        doneMin: day.where((t) => t.done).fold(0, (s, t) => s + taskMinutes(t)),
        protectedPlanned: day.where((t) => t.protect != null).length,
        protectedDone: day.where((t) => t.protect != null && t.done).length,
        focusMin: focusedMinutes(d),
      ));
    }

    final open = tasks(undated: true, includeDone: false);
    return Stats(
      days: records,
      backlog: open.where((t) => t.date == null).length,
      overdue: open.where((t) => t.date != null && t.date!.compareTo(last) < 0).length,
      dueSoon: [
        for (final t in open)
          if (t.dueDate != null && t.dueDate!.compareTo(addDays(last, 14)) <= 0) t,
      ]..sort((a, b) => a.dueDate!.compareTo(b.dueDate!)),
      unprocessed: unprocessedDiary().length,
    );
  }

  /// Checks the plan for [date] against what has to hold whatever the
  /// planner decided: nothing left in the past, no deadline broken, every
  /// diary entry accounted for, and the day no fuller than [capacity] of the
  /// time actually available. The day starts an hour after [wake] (by
  /// default the typical wake time of the last three days) and ends at [end].
  PlanCheck checkPlan(String date, {String? wake, String? end, double capacity = 0.75, DateTime? now}) {
    final clock = now ?? DateTime.now();
    final errors = <PlanIssue>[], warnings = <PlanIssue>[];

    final typical = stats(days: 7, until: today(clock)).wakeOver(3);
    var start = (wake != null ? clockMinutes(wake) : typical ?? 6 * 60 + 30) + 60;
    // Planning the rest of today: what is past is gone.
    if (date == today(clock)) start = start > clock.hour * 60 + clock.minute ? start : clock.hour * 60 + clock.minute;
    final finish = clockMinutes(end ?? getMeta('plan_end') ?? '22:30');

    final open = tasks(undated: true, includeDone: false);
    String name(Task t) => '"${t.title}"';

    for (final t in open) {
      if (t.date != null && t.date!.compareTo(date) < 0) {
        errors.add(PlanIssue('overdue', '${name(t)} is still planned for ${prettyDate(t.date!)}. Move it, finish it or drop it.', t.id));
      }
      if (t.dueDate != null && t.dueDate!.compareTo(date) < 0) {
        errors.add(PlanIssue('deadline_passed', 'The deadline of ${name(t)} (${prettyDate(t.dueDate!)}) has passed and it is not done. Decide what happens to it.', t.id));
      } else if (t.dueDate != null && t.date != null && t.date!.compareTo(t.dueDate!) > 0) {
        errors.add(PlanIssue('after_deadline', '${name(t)} is planned for ${prettyDate(t.date!)}, after its deadline of ${prettyDate(t.dueDate!)}.', t.id));
      } else if (t.dueDate != null && t.date == null && t.dueDate!.compareTo(addDays(date, 3)) <= 0) {
        warnings.add(PlanIssue('due_soon', '${name(t)} is due ${prettyDate(t.dueDate!)} and has no day planned.', t.id));
      }
    }

    final day = open.where((t) => t.date == date).toList();
    final timed = day.where((t) => t.startTime != null).toList()
      ..sort((a, b) => a.startTime!.compareTo(b.startTime!));
    for (final t in timed) {
      final s = clockMinutes(t.startTime!), e = t.endTime == null ? s + taskMinutes(t) : clockMinutes(t.endTime!);
      final fixed = t.protect == Task.protectTime;
      if (s < start) {
        (fixed ? warnings : errors).add(PlanIssue(
          fixed ? 'fixed_before_start' : 'before_start',
          '${name(t)} starts at ${t.startTime}, but the day is expected to start around ${clockText(start)}.'
              '${fixed ? ' It is fixed in time, so say how that will work.' : ''}',
          t.id,
        ));
      }
      if (e > finish) {
        (fixed ? warnings : errors).add(PlanIssue(
          fixed ? 'fixed_after_end' : 'after_end',
          '${name(t)} ends at ${clockText(e)}, after the day ends at ${clockText(finish)}.',
          t.id,
        ));
      }
    }
    for (var i = 0; i + 1 < timed.length; i++) {
      final a = timed[i], b = timed[i + 1];
      final aEnd = a.endTime == null ? clockMinutes(a.startTime!) + taskMinutes(a) : clockMinutes(a.endTime!);
      if (clockMinutes(b.startTime!) < aEnd) {
        errors.add(PlanIssue('overlap', '${name(a)} and ${name(b)} overlap.', b.id));
      }
    }

    final planned = day.fold(0, (s, t) => s + taskMinutes(t));
    final result = PlanCheck(
      date: date,
      start: start,
      end: finish,
      capacity: capacity,
      plannedMin: planned,
      errors: errors,
      warnings: warnings,
    );
    if (planned > result.budgetMin) {
      errors.add(PlanIssue(
        'overloaded',
        '${prettyDate(date)} holds $planned min of tasks; ${(capacity * 100).round()}% of the time from '
            '${clockText(start)} to ${clockText(finish)} is ${result.budgetMin} min. Move the least important to another day.',
      ));
    }

    final since = utcStamp(clock.subtract(const Duration(hours: 36)));
    final fresh = [
      for (final t in day)
        if (t.sourceEntry != null &&
            db.select('SELECT 1 FROM tasks WHERE id = ? AND created_at > ?', [t.id, since]).isNotEmpty)
          t,
    ];
    if (fresh.length > maxNewPerDay) {
      errors.add(PlanIssue(
        'too_many_new',
        '${fresh.length} newly captured commitments are planned for ${prettyDate(date)}; at most $maxNewPerDay may be. '
            'Leave the rest in the backlog (no day), with their deadlines.',
      ));
    }

    for (final e in unprocessedDiary()) {
      errors.add(PlanIssue(
        'unprocessed_entry',
        'The diary entry of ${prettyDate(e.date)} ${hm(e.createdAt)} (${e.id.substring(0, 6)}) has no recorded outcome.',
      ));
    }

    final todayStamp = ymd(clock);
    for (final t in tasks(undated: true)) {
      if (t.protect == null || t.history == null) continue;
      for (final line in t.history!.split('\n')) {
        if (line.startsWith(todayStamp) && line.contains(' day ')) {
          warnings.add(PlanIssue('protected_moved', '${name(t)} is protected and was moved today: ${line.substring(17)}', t.id));
        }
      }
    }
    return result;
  }
}
