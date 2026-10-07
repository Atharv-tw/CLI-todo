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
        calendarEventId = r['calendar_event_id'] as String?;

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
