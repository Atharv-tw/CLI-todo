import 'package:flutter/material.dart';
import 'package:todo_core/todo_core.dart';

import 'state.dart';
import 'task_widgets.dart';
import 'theme.dart';

/// Whether a timed item's slot on [date] covers the present moment.
bool isNow(String date, String? start, String? end, {required bool done}) {
  if (done || start == null) return false;
  final now = DateTime.now();
  return date == today(now) && !now.isBefore(atTime(date, start)) && now.isBefore(slotEnd(date, start, end));
}

/// One task or habit on the day's rail: a dot, the title, and its time or a
/// "Now" pill. Tap ticks it; long-press edits it.
class TimelineRow extends StatelessWidget {
  const TimelineRow({
    super.key,
    required this.item,
    required this.date,
    required this.first,
    required this.last,
    this.task,
  });

  /// An entry of `Store.snapshot()['items']`.
  final Map<String, Object?> item;
  final String date;
  final bool first;
  final bool last;

  /// The full task when [item] is one, for its tag and edit sheet.
  final Task? task;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final text = Theme.of(context).textTheme;
    final id = item['id'] as String;
    final done = item['done'] == true;
    final time = item['time'] as String?;
    final isHabit = item['kind'] == 'habit';
    final current = !isHabit && isNow(date, time, item['end_time'] as String?, done: done);
    final details = [
      if (isHabit) 'Habit',
      ?task?.tag,
      ?task?.list,
    ].join(' · ');

    void toggle() => app.change(
          (s) => isHabit ? s.setHabitCheck(id, date, !done) : s.setDone(id, !done),
        );

    Future<void> edit() async {
      if (!isHabit) return showTaskSheet(context, task: task);
      final parts = (time ?? '09:00').split(':').map(int.parse).toList();
      final picked = await showTimePicker(
        context: context,
        helpText: 'Time of day for "${item['title']}"',
        initialTime: TimeOfDay(hour: parts[0], minute: parts[1]),
      );
      if (picked != null) app.change((s) => s.setHabitTime(id, hm(DateTime(2000, 1, 1, picked.hour, picked.minute))));
    }

    return InkWell(
      key: ValueKey('timeline-$id'),
      borderRadius: BorderRadius.circular(16),
      onTap: toggle,
      onLongPress: edit,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 36,
              child: CustomPaint(painter: _RailPainter(first: first, last: last, done: done, current: current)),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['title'] as String,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: done ? AppColors.muted : null,
                        decoration: done ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    if (details.isNotEmpty)
                      Text(details, style: text.bodySmall?.copyWith(color: AppColors.muted)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Center(
              child: current
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: const ShapeDecoration(color: AppColors.green, shape: StadiumBorder()),
                      child: Text(
                        'Now',
                        style: text.labelLarge?.copyWith(color: AppColors.onLight, fontWeight: FontWeight.w700),
                      ),
                    )
                  : Text(
                      time == null ? '' : (task?.endTime == null ? time : '$time–${task!.endTime}'),
                      style: text.bodySmall?.copyWith(
                        color: AppColors.muted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}

class _RailPainter extends CustomPainter {
  _RailPainter({required this.first, required this.last, required this.done, required this.current});

  final bool first, last, done, current;

  static const _dotY = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final line = Paint()
      ..color = AppColors.muted.withValues(alpha: 0.6)
      ..strokeWidth = 1.5;
    void dashes(double from, double to) {
      for (var y = from; y < to; y += 7) {
        canvas.drawLine(Offset(x, y), Offset(x, (y + 3.5).clamp(from, to)), line);
      }
    }

    if (!first) dashes(0, _dotY - 11);
    if (!last) dashes(_dotY + 11, size.height);

    final centre = Offset(x, _dotY);
    if (current) {
      canvas.drawCircle(centre, 9, Paint()..color = AppColors.orange);
      canvas.drawCircle(centre, 3.5, Paint()..color = Colors.white);
    } else if (done) {
      canvas.drawCircle(centre, 8, Paint()..color = AppColors.green);
      final tick = Path()
        ..moveTo(x - 3.5, _dotY)
        ..lineTo(x - 1, _dotY + 2.8)
        ..lineTo(x + 3.8, _dotY - 2.8);
      canvas.drawPath(
        tick,
        Paint()
          ..color = AppColors.onLight
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    } else {
      canvas.drawCircle(
        centre,
        7,
        Paint()
          ..color = AppColors.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(_RailPainter old) =>
      old.first != first || old.last != last || old.done != done || old.current != current;
}
