import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:todo_core/todo_core.dart';

import 'background.dart';
import 'outputs.dart';

/// Holds the store and tells the UI when anything changed, whether from this
/// app, from sync, or (on the laptop) from the CLI or top-bar widget.
class AppState extends ChangeNotifier with WidgetsBindingObserver {
  AppState(this.store) : remote = SupabaseRemote(store);

  final Store store;
  final SupabaseRemote remote;

  bool syncing = false;
  String? syncError;
  DateTime? lastSync;

  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _periodic, _afterEdit, _afterOutside;

  void start({String? watchDir}) {
    if (watchDir != null) {
      _watch = Directory(watchDir).watch().listen((_) {
        _afterOutside ??= Timer(const Duration(milliseconds: 250), () {
          _afterOutside = null;
          notifyListeners();
        });
      });
    }
    _periodic = Timer.periodic(const Duration(minutes: 2), (_) => sync());
    WidgetsBinding.instance.addObserver(this);
    refreshOutputs(store);
    sync();
  }

  /// Widgets may have changed the database while the app was in the background.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    notifyListeners();
    sync();
  }

  /// Whether a sync would do anything: signed in, or (phone) a calendar chosen.
  bool get _syncs => remote.signedIn || store.getMeta('calendar_id') != null;

  /// Runs a store write, refreshes the UI and queues a sync.
  T change<T>(T Function(Store store) write) {
    final result = write(store);
    notifyListeners();
    refreshOutputs(store);
    if (_syncs) {
      _afterEdit?.cancel();
      _afterEdit = Timer(const Duration(seconds: 3), sync);
    }
    return result;
  }

  Future<void> sync() async {
    if (syncing || !_syncs) return;
    syncing = true;
    notifyListeners();
    try {
      await fullSync(store);
      syncError = null;
      lastSync = DateTime.now();
    } on SyncException catch (e) {
      syncError = e.message;
    } catch (_) {
      syncError = 'Offline. Changes are saved here and will sync later.';
    } finally {
      syncing = false;
      notifyListeners();
      refreshOutputs(store);
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    await remote.signIn(email, password);
    notifyListeners();
    await sync();
  }

  void signOut() {
    remote.signOut();
    syncError = null;
    lastSync = null;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watch?.cancel();
    _periodic?.cancel();
    _afterEdit?.cancel();
    _afterOutside?.cancel();
    super.dispose();
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
