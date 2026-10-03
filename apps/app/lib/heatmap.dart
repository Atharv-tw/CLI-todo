import 'package:flutter/material.dart';
import 'package:todo_core/todo_core.dart';

import 'theme.dart';

/// One month as a GitHub-style grid: weeks are columns, Monday to Sunday rows.
class MonthHeatmap extends StatelessWidget {
  const MonthHeatmap({
    super.key,
    required this.month,
    required this.value,
    this.onTap,
    this.keyPrefix,
  });

  /// Any day in the month to show.
  final DateTime month;

  /// 0..1 for how full a day is, or null when the day does not apply
  /// (for example before a habit started).
  final double? Function(String date) value;
  final void Function(String date)? onTap;

  /// Gives each tappable day the key `<prefix>-<date>`.
  final String? keyPrefix;

  static const cell = 20.0;
  static const gap = 4.0;
  static const _labelWidth = 16.0;

  static Color shade(double v) => v <= 0
      ? const Color(0xFF34343A)
      : AppColors.green.withValues(alpha: v < 0.34 ? 0.3 : v < 0.67 ? 0.55 : v < 1 ? 0.8 : 1);

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final offset = first.weekday - 1;
    final weeks = ((offset + daysInMonth) / 7).ceil();
    final now = today();

    Widget day(int week, int weekday) {
      final n = week * 7 + weekday - offset + 1;
      if (n < 1 || n > daysInMonth) return const SizedBox.square(dimension: cell);
      final date = ymd(DateTime(month.year, month.month, n));
      final future = date.compareTo(now) > 0;
      final v = value(date);
      final box = Container(
        width: cell,
        height: cell,
        decoration: BoxDecoration(
          color: v == null
              ? Colors.transparent
              : future
                  ? AppColors.raised.withValues(alpha: 0.35)
                  : shade(v),
          borderRadius: BorderRadius.circular(6),
          border: date == now && v != null
              ? Border.all(color: AppColors.ink, width: 1.5)
              : v == null
                  ? Border.all(color: AppColors.line)
                  : null,
        ),
      );
      if (onTap == null || future || v == null) return box;
      return GestureDetector(
        key: keyPrefix == null ? null : ValueKey('$keyPrefix-$date'),
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap!(date),
        child: Semantics(label: prettyDate(date), button: true, child: box),
      );
    }

    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.muted, height: 1);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            for (var wd = 0; wd < 7; wd++)
              Container(
                width: _labelWidth,
                height: cell,
                margin: EdgeInsets.only(bottom: wd == 6 ? 0 : gap),
                alignment: Alignment.centerLeft,
                child: Text(weekdayShort[wd][0], style: labelStyle),
              ),
          ],
        ),
        for (var w = 0; w < weeks; w++)
          Padding(
            padding: const EdgeInsets.only(left: gap),
            child: Column(
              children: [
                for (var wd = 0; wd < 7; wd++)
                  Padding(padding: EdgeInsets.only(bottom: wd == 6 ? 0 : gap), child: day(w, wd)),
              ],
            ),
          ),
      ],
    );
  }
}

/// A small number-over-label tile, as on the habit cards.
class StatTile extends StatelessWidget {
  const StatTile(this.value, this.label, {super.key});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
