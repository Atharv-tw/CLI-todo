import 'package:device_calendar_plus/device_calendar_plus.dart';
import 'package:todo_core/todo_core.dart';

/// Two-way link between timed tasks and events in one device calendar.
///
/// Only events this app created are ever read or changed. For each linked
/// task the last state both sides agreed on is remembered; whichever side
/// differs from it has changed (the task wins if both did).
class CalendarSync {
  CalendarSync(this.store);

  final Store store;
  final _cal = DeviceCalendar.instance;

  static const _done = '✓ ';
  static const _defaultLength = Duration(minutes: 30);

  String? get calendarId => store.getMeta('calendar_id');
  set calendarId(String? id) => store.setMeta('calendar_id', id);

  /// Calendars events can be written to; prompts for permission if needed.
  Future<List<Calendar>> writableCalendars() async {
    if (await _cal.requestPermissions() != CalendarPermissionStatus.granted) return [];
    return (await _cal.listCalendars()).where((c) => !c.readOnly).toList();
  }

  static String _hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static DateTime _at(String date, String time) {
    final d = parseYmd(date);
    final parts = time.split(':').map(int.parse).toList();
    return DateTime(d.year, d.month, d.day, parts[0], parts[1]);
  }

  static String _sig(String title, String date, String start, String? end, bool done) =>
      [title, date, start, end ?? '', done ? '1' : '0'].join('\u001f');

  /// Returns how many tasks were changed locally (and so need pushing).
  Future<int> run() async {
    final calId = calendarId;
    if (calId == null) return 0;
    if (await _cal.hasPermissions() != CalendarPermissionStatus.granted) return 0;

    final rows = store.db.select(
      'SELECT * FROM tasks WHERE '
      '(calendar_event_id IS NOT NULL AND (deleted_at IS NOT NULL OR date IS NULL OR date >= ?1)) '
      'OR (deleted_at IS NULL AND date >= ?2 AND start_time IS NOT NULL)',
      [addDays(today(), -14), addDays(today(), -1)],
    );
    var changed = 0;

    for (final row in rows) {
      final id = row['id'] as String;
      final title = row['title'] as String;
      final date = row['date'] as String?;
      final start = row['start_time'] as String?;
      final end = row['end_time'] as String?;
      final done = row['done_at'] != null;
      final eventId = row['calendar_event_id'] as String?;
      final sigKey = 'cal:$id';
      final agreed = store.getMeta(sigKey);

      void link(String? newEventId, String? sig) {
        if (newEventId != eventId) {
          store.updateTask(id, {'calendar_event_id': newEventId});
          changed++;
        }
        store.setMeta(sigKey, sig);
      }

      final wanted = row['deleted_at'] == null && date != null && start != null;
      if (!wanted) {
        if (eventId != null) {
          try {
            await _cal.deleteEvent(instanceId: eventId);
          } on DeviceCalendarException {
            // Already gone.
          }
          link(null, null);
        }
        continue;
      }

      final sig = _sig(title, date, start, end, done);
      final shownTitle = done ? '$_done$title' : title;
      final startAt = _at(date, start);
      var endAt = end == null ? startAt.add(_defaultLength) : _at(date, end);
      if (!endAt.isAfter(startAt)) endAt = startAt.add(_defaultLength);

      Future<void> create() async {
        final newId = await _cal.createEvent(
          calendarId: calId,
          title: shownTitle,
          startDate: startAt,
          endDate: endAt,
        );
        link(newId, sig);
      }

      if (eventId == null) {
        await create();
        continue;
      }

      final event = await _cal.getEvent(eventId);
      if (event == null) {
        if (sig == agreed) {
          // Deleted in the calendar: keep the task, drop its time slot.
          store.updateTask(id, {'start_time': null, 'end_time': null, 'calendar_event_id': null});
          store.setMeta(sigKey, null);
          changed++;
        } else {
          await create();
        }
        continue;
      }

      if (sig != agreed) {
        await _cal.updateEvent(
          instanceId: event.instanceId,
          title: shownTitle,
          startDate: startAt,
          endDate: endAt,
        );
        store.setMeta(sigKey, sig);
        continue;
      }

      // The task is as agreed; see whether the event was moved or renamed.
      if (event.isAllDay) continue;
      final evTitle = event.title.startsWith(_done) ? event.title.substring(_done.length) : event.title;
      final evDate = ymd(event.startDate);
      final evStart = _hm(event.startDate);
      final length = event.endDate.difference(event.startDate);
      final evEnd = end == null && length == _defaultLength
          ? null
          : ymd(event.endDate) == evDate
              ? _hm(event.endDate)
              : '23:59';
      final evSig = _sig(evTitle, evDate, evStart, evEnd, done);
      if (evSig != sig) {
        store.updateTask(id, {
          'title': evTitle,
          'date': evDate,
          'start_time': evStart,
          'end_time': evEnd,
        });
        store.setMeta(sigKey, evSig);
        changed++;
      }
    }
    return changed;
  }
}
