import 'dates.dart';

class TaskList {
  TaskList.fromRow(Map<String, Object?> r)
      : id = r['id'] as String,
        title = r['title'] as String;

  final String id;
  final String title;

  Map<String, Object?> toJson() => {'id': id, 'title': title};
}

class Task {
  Task.fromRow(Map<String, Object?> r)
      : id = r['id'] as String,
        listId = r['list_id'] as String?,
        list = r['list_title'] as String?,
        title = r['title'] as String,
        notes = r['notes'] as String?,
        tag = r['tag'] as String?,
        date = r['date'] as String?,
        startTime = r['start_time'] as String?,
        endTime = r['end_time'] as String?,
        doneAt = r['done_at'] as String?,
        calendarEventId = r['calendar_event_id'] as String?,
        dueDate = r['due_date'] as String?,
        estimateMin = r['estimate_min'] as int?,
        protect = r['protect'] as String?,
        sourceEntry = r['source_entry'] as String?,
        history = r['history'] as String?;

  final String id;
  final String? listId;
  final String? list;
  final String title;
  final String? notes;
  final String? tag;
  final String? date;
  final String? startTime;
  final String? endTime;
  final String? doneAt;
  final String? calendarEventId;

  /// When it must be done by. Separate from [date], the day it is planned
  /// for: re-planning moves [date] and never this.
  final String? dueDate;

  /// Minutes it is expected to take, for tasks without a time slot.
  final int? estimateMin;

  /// [protectDay], [protectTime] or null.
  final String? protect;

  /// The diary entry it was captured from.
  final String? sourceEntry;

  /// One line per change to its day, time or deadline, oldest first.
  final String? history;

  /// Must stay on its planned day, though it may move within the day.
  static const protectDay = 'day';

  /// Fixed in time: neither its day nor its time may move.
  static const protectTime = 'time';

  bool get done => doneAt != null;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'done': done,
        'date': date,
        'start_time': startTime,
        'end_time': endTime,
        'tag': tag,
        'list': list,
        'notes': notes,
        'due': dueDate,
        'estimate_min': estimateMin,
        'protect': protect,
        'source_entry': sourceEntry,
        'history': history?.split('\n') ?? const <String>[],
      };
}

class Habit {
  Habit.fromRow(Map<String, Object?> r)
      : id = r['id'] as String,
        title = r['title'] as String,
        time = r['time'] as String?,
        startDate = r['start_date'] as String?,
        endDate = r['end_date'] as String?;

  final String id;
  final String title;

  /// Time of day (`HH:MM`) the habit sits at in the day's timeline, if any.
  final String? time;
  final String? startDate;
  final String? endDate;

  /// A title like `5 meals / Lunch` makes the habit one step of the group
  /// `5 meals`: the steps remind separately through the day, and the group
  /// counts as done only once every step is.
  static const groupSeparator = ' / ';

  String? get group {
    final i = title.indexOf(groupSeparator);
    return i <= 0 ? null : title.substring(0, i);
  }

  /// The title without its group.
  String get step => group == null ? title : title.substring(group!.length + groupSeparator.length);

  Map<String, Object?> toJson() =>
      {'id': id, 'title': title, 'time': time, 'start_date': startDate, 'end_date': endDate};
}

class FocusSession {
  FocusSession.fromRow(Map<String, Object?> r)
      : id = r['id'] as String,
        taskId = r['task_id'] as String?,
        taskTitle = r['task_title'] as String?,
        kind = r['kind'] as String,
        startedAt = DateTime.parse(r['started_at'] as String),
        plannedMin = r['planned_min'] as int,
        endedAt = r['ended_at'] == null ? null : DateTime.parse(r['ended_at'] as String);

  final String id;
  final String? taskId;
  final String? taskTitle;

  /// `focus` or `break`.
  final String kind;
  final DateTime startedAt;
  final int plannedMin;
  final DateTime? endedAt;

  DateTime get plannedEnd => startedAt.add(Duration(minutes: plannedMin));

  Map<String, Object?> toJson() => {
        'id': id,
        'kind': kind,
        'task_id': taskId,
        'task': taskTitle,
        'started_at': utcStamp(startedAt),
        'planned_min': plannedMin,
        'ends_at': utcStamp(plannedEnd),
        'ended_at': endedAt == null ? null : utcStamp(endedAt!),
      };
}

/// Foreground time for one app over some period.
class AppUsage {
  AppUsage(this.app, this.name, this.seconds);

  final String app;
  final String name;
  final int seconds;

  Map<String, Object?> toJson() => {'app': app, 'name': name, 'seconds': seconds};
}

/// A foreground stretch of one app, as reported by a device.
class UsageSpan {
  UsageSpan(this.app, this.name, this.start, this.end);

  final String app;
  final String name;
  final DateTime start;
  final DateTime end;
}

/// A page of the vault as other devices see it: a morning or weekly page,
/// the goals, the projects (see `Store.putPage`).
class VaultPage {
  VaultPage.fromRow(Map<String, Object?> r)
      : id = r['id'] as String,
        kind = r['kind'] as String,
        key = r['key'] as String,
        title = r['title'] as String?,
        body = r['body'] as String,
        updatedAt = DateTime.parse(r['updated_at'] as String).toLocal();

  final String id;

  /// `morning`, `weekly`, `goals` or `projects`.
  final String kind;

  /// A date for a morning page, a week (2026-W43) for a weekly one, `all`
  /// otherwise.
  final String key;
  final String? title;

  /// Markdown, or JSON for `projects`.
  final String body;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => {'kind': kind, 'key': key, 'title': title, 'body': body};
}

/// One diary entry: anything the user wants to keep (an idea, a decision, how
/// the day went), or the assistant's note of what it changed in the plan.
class DiaryEntry {
  DiaryEntry.fromRow(Map<String, Object?> r)
      : id = r['id'] as String,
        date = r['date'] as String,
        author = r['author'] as String,
        body = r['body'] as String,
        taskId = r['task_id'] as String?,
        taskTitle = r['task_title'] as String?,
        habitId = r['habit_id'] as String?,
        habitTitle = r['habit_title'] as String?,
        createdAt = DateTime.parse(r['created_at'] as String).toLocal(),
        filedAt = r['filed_at'] == null ? null : DateTime.parse(r['filed_at'] as String).toLocal(),
        outcome = r['outcome'] as String?;

  static const me = 'me';
  static const assistant = 'claude';

  final String id;

  /// The day the entry is about, which is the day it was written unless said
  /// otherwise.
  final String date;

  /// [me] or [assistant].
  final String author;
  final String body;

  /// The task or habit the entry is about, if any, with its current title.
  final String? taskId;
  final String? taskTitle;
  final String? habitId;
  final String? habitTitle;

  /// When it was logged, in local time.
  final DateTime createdAt;

  /// When an assistant filed it into the vault; null until then.
  final DateTime? filedAt;

  /// What became of it, written by the assistant that processed it: the
  /// tasks captured, the projects updated, or that it was only an idea or
  /// context. Null until processed.
  final String? outcome;

  /// The title of whatever the entry is about.
  String? get about => taskTitle ?? habitTitle;

  Map<String, Object?> toJson() => {
        'id': id,
        'date': date,
        'author': author,
        'body': body,
        'created_at': utcStamp(createdAt),
        'time': hm(createdAt),
        'task_id': taskId,
        'task': taskTitle,
        'habit_id': habitId,
        'habit': habitTitle,
        'outcome': outcome,
        'filed_at': filedAt == null ? null : utcStamp(filedAt!),
      };
}
