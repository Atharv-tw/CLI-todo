import 'dart:io';

import 'package:flutter/services.dart';
import 'package:todo_core/todo_core.dart';

const _channel = MethodChannel('todo/usage');

/// Whether this device reports its own screen time (the phone does; the
/// laptop is read by the GNOME extension instead).
bool get collectsUsage => Platform.isAndroid;

Future<bool> hasUsageAccess() async => await _channel.invokeMethod<bool>('hasAccess') ?? false;

Future<void> openUsageSettings() => _channel.invokeMethod('openSettings');

/// Reads the phone's foreground history since this was last run (at most the
/// last 7 days, which is all Android keeps) and stores it. Safe to repeat.
Future<void> collectPhoneUsage(Store store) async {
  if (!collectsUsage || !await hasUsageAccess()) return;
  if (store.getMeta('device_name') == null) {
    store.setDeviceName(await _channel.invokeMethod<String>('deviceName') ?? 'phone');
  }
  final now = DateTime.now();
  final earliest = DateTime(now.year, now.month, now.day - 6);
  final last = DateTime.tryParse(store.getMeta('usage_collected') ?? '');
  var since = last == null ? earliest : DateTime(last.year, last.month, last.day);
  if (since.isBefore(earliest)) since = earliest;

  // Read from a little earlier so an app already open at midnight is seen;
  // the store drops whatever falls before [since].
  final raw = await _channel.invokeListMethod<Map>('spans', {
        'from': since.subtract(const Duration(hours: 6)).millisecondsSinceEpoch,
        'to': now.millisecondsSinceEpoch,
      }) ??
      [];
  store.replaceUsage(since, [
    for (final s in raw)
      UsageSpan(
        s['app'] as String,
        s['name'] as String,
        DateTime.fromMillisecondsSinceEpoch(s['start'] as int),
        DateTime.fromMillisecondsSinceEpoch(s['end'] as int),
      ),
  ]);
  store.setMeta('usage_collected', now.toIso8601String());
}
