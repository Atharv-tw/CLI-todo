import 'dart:convert';

import 'package:http/http.dart' as http;

import 'store.dart';
import 'sync.dart';

class SyncException implements Exception {
  SyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Supabase over plain HTTP (PostgREST + GoTrue). Project URL, anon key and
/// the login session live in the local `meta` table.
class SupabaseRemote implements Remote {
  SupabaseRemote(this.store, {http.Client? client}) : _http = client ?? http.Client();

  final Store store;
  final http.Client _http;

  static const _pageSize = 1000;

  // App builds may bake the project in with --dart-define; otherwise it is
  // set once per device (`todo server URL KEY`) and kept in `meta`.
  static const _builtInUrl = String.fromEnvironment('TODO_SUPABASE_URL');
  static const _builtInKey = String.fromEnvironment('TODO_SUPABASE_KEY');

  String? get url => store.getMeta('supabase_url') ?? (_builtInUrl.isEmpty ? null : _builtInUrl);
  String? get anonKey => store.getMeta('supabase_anon_key') ?? (_builtInKey.isEmpty ? null : _builtInKey);
  bool get configured => url != null && anonKey != null;

  void _needConfig() {
    if (!configured) {
      throw SyncException('No sync server set. Run: todo server URL KEY (see the README)');
    }
  }

  String? get email => store.getMeta('supabase_email');
  bool get signedIn => store.getMeta('supabase_refresh_token') != null;

  void configure({required String url, required String anonKey}) {
    store.setMeta('supabase_url', url.trim().replaceFirst(RegExp(r'/+$'), ''));
    store.setMeta('supabase_anon_key', anonKey.trim());
  }

  Future<void> signIn(String email, String password) async {
    _needConfig();
    await _token('password', {'email': email, 'password': password});
    store.setMeta('supabase_email', email);
    SyncEngine.reset(store);
  }

  void signOut() {
    for (final k in ['access_token', 'refresh_token', 'expires_at', 'email']) {
      store.setMeta('supabase_$k', null);
    }
  }

  Future<void> _token(String grant, Map<String, String> body) async {
    final res = await _http.post(
      Uri.parse('$url/auth/v1/token?grant_type=$grant'),
      headers: {'apikey': anonKey!, 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      final detail = _errorText(res);
      if (grant == 'refresh_token') {
        signOut();
        throw SyncException('Signed out (the session expired). Run: todo login');
      }
      throw SyncException('Sign-in failed: $detail');
    }
    final data = jsonDecode(res.body) as Map<String, Object?>;
    final expires = DateTime.now().add(Duration(seconds: (data['expires_in'] as num).toInt()));
    store.setMeta('supabase_access_token', data['access_token'] as String);
    store.setMeta('supabase_refresh_token', data['refresh_token'] as String);
    store.setMeta('supabase_expires_at', expires.toUtc().toIso8601String());
  }

  String _errorText(http.Response res) {
    try {
      final data = jsonDecode(res.body) as Map<String, Object?>;
      return (data['msg'] ?? data['message'] ?? data['error_description'] ?? res.body).toString();
    } catch (_) {
      return 'HTTP ${res.statusCode}';
    }
  }

  Future<Map<String, String>> _headers({bool forceRefresh = false}) async {
    _needConfig();
    final refresh = store.getMeta('supabase_refresh_token');
    if (refresh == null) throw SyncException('Not signed in. Run: todo login');
    final expires = DateTime.tryParse(store.getMeta('supabase_expires_at') ?? '');
    if (forceRefresh ||
        expires == null ||
        expires.isBefore(DateTime.now().add(const Duration(minutes: 1)))) {
      await _token('refresh_token', {'refresh_token': refresh});
    }
    return {
      'apikey': anonKey!,
      'Authorization': 'Bearer ${store.getMeta('supabase_access_token')}',
      'Content-Type': 'application/json',
    };
  }

  /// Runs [request], retrying once with a fresh token on 401.
  Future<http.Response> _send(Future<http.Response> Function(Map<String, String> headers) request) async {
    var res = await request(await _headers());
    if (res.statusCode == 401) res = await request(await _headers(forceRefresh: true));
    if (res.statusCode >= 300) throw SyncException('Sync failed: ${_errorText(res)}');
    return res;
  }

  @override
  Future<void> push(String table, List<Map<String, Object?>> rows) async {
    for (var i = 0; i < rows.length; i += 500) {
      final chunk = rows.sublist(i, (i + 500).clamp(0, rows.length));
      await _send((headers) => _http.post(
            Uri.parse('$url/rest/v1/$table?on_conflict=id'),
            headers: {...headers, 'Prefer': 'resolution=merge-duplicates,return=minimal'},
            body: jsonEncode(chunk),
          ));
    }
  }

  @override
  Future<List<Map<String, Object?>>> pull(String table, String? since) async {
    final rows = <Map<String, Object?>>[];
    while (true) {
      final uri = Uri.parse('$url/rest/v1/$table').replace(queryParameters: {
        'select': '*',
        if (since != null) 'server_at': 'gt.$since',
        'order': 'server_at.asc,id.asc',
        'limit': '$_pageSize',
        'offset': '${rows.length}',
      });
      final res = await _send((headers) => _http.get(uri, headers: headers));
      final page = (jsonDecode(res.body) as List).cast<Map<String, Object?>>();
      rows.addAll(page);
      if (page.length < _pageSize) return rows;
    }
  }
}
