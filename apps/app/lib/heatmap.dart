import 'package:flutter/material.dart';
import 'package:todo_core/todo_core.dart';

import 'theme.dart';

/// A GitHub-style activity calendar: weeks are columns, Monday to Sunday are
/// rows, and each day is a square whose colour deepens with how much of that
/// day was done. Shows as many weeks, ending with the current one, as fit.
class ActivityCalendar extends StatelessWidget {
  const ActivityCalendar({super.key, required this.value, this.selected, this.onTap});

  /// 0..1 for how much of the day was done.
  final double Function(String date) value;

  /// Day drawn with an outline, if any.
  final String? selected;
  final void Function(String date)? onTap;

  static const _cell = 15.0;
  static const _gap = 4.0;
  static const _labelWidth = 18.0;
  static const _empty = Color(0xFF2A2A30);

  /// Empty, then four deepening greens.
  static Color shade(double v) => v <= 0
      ? _empty
      : AppColors.green.withValues(alpha: v < 0.34 ? 0.3 : v < 0.67 ? 0.55 : v < 1 ? 0.8 : 1);

  /// How many weeks fit in [width].
  static int weeksFor(double width) => ((width - _labelWidth + _gap) / (_cell + _gap)).floor().clamp(4, 53);

  @override
  Widget build(BuildContext context) {
    final label = Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.muted, height: 1);
    return LayoutBuilder(builder: (context, box) {
      final weeks = weeksFor(box.maxWidth);
      final now = DateTime.now();
      final nowYmd = today(now);
      // Monday of the first column.
      final start = DateTime(now.year, now.month, now.day - (now.weekday - 1) - 7 * (weeks - 1));
      DateTime dayAt(int week, int weekday) => DateTime(start.year, start.month, start.day + week * 7 + weekday);

      Widget square(int week, int weekday) {
        final date = ymd(dayAt(week, weekday));
        if (date.compareTo(nowYmd) > 0) return const SizedBox.square(dimension: _cell);
        final box = Container(
          width: _cell,
          height: _cell,
          decoration: BoxDecoration(
            color: shade(value(date)),
            borderRadius: BorderRadius.circular(4),
            border: date == selected ? Border.all(color: AppColors.ink, width: 1.5) : null,
          ),
        );
        if (onTap == null) return box;
        return GestureDetector(
          key: ValueKey('day-$date'),
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap!(date),
          child: Semantics(label: prettyDate(date), button: true, child: box),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month names above the column where each month begins.
          SizedBox(
            height: 14,
            child: Stack(
              children: [
                for (var w = 0; w < weeks; w++)
                  if (w == 0 || dayAt(w, 0).month != dayAt(w - 1, 0).month)
                    Positioned(
                      left: _labelWidth + w * (_cell + _gap),
                      child: Text(monthShort[dayAt(w, 0).month - 1], style: label),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _labelWidth,
                child: Column(
                  children: [
                    for (var wd = 0; wd < 7; wd++)
                      Container(
                        height: _cell,
                        margin: EdgeInsets.only(bottom: wd == 6 ? 0 : _gap),
                        alignment: Alignment.centerLeft,
                        child: Text(wd.isEven ? weekdayShort[wd][0] : '', style: label),
                      ),
                  ],
                ),
              ),
              for (var w = 0; w < weeks; w++)
                Padding(
                  padding: EdgeInsets.only(right: w == weeks - 1 ? 0 : _gap),
                  child: Column(
                    children: [
                      for (var wd = 0; wd < 7; wd++)
                        Padding(padding: EdgeInsets.only(bottom: wd == 6 ? 0 : _gap), child: square(w, wd)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            spacing: _gap,
            children: [
              Text('Less', style: label),
              for (final v in const [0.0, 0.2, 0.5, 0.8, 1.0])
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(color: shade(v), borderRadius: BorderRadius.circular(3)),
                ),
              Text('More', style: label),
            ],
          ),
        ],
      );
    });
  }
}

/// A small number-over-label tile.
class StatTile extends StatelessWidget {
  const StatTile(this.value, this.label, {super.key});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: AppColors.raised, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          Text(label, style: text.labelSmall?.copyWith(color: AppColors.muted)),
        ],
      ),
    );
  }
}
