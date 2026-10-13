import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Whether this device can turn speech into text: with a Whisper model kept
/// on the device, or on a phone with Android's own recogniser.
bool get voiceSupported => Platform.isAndroid || Platform.isLinux;

// Build with --dart-define=VOICE_TRACE=true to log what the recogniser sends
// (kinds and lengths only, never the words) when chasing a problem.
const _tracing = bool.fromEnvironment('VOICE_TRACE');

void _trace(String event) {
  if (_tracing) debugPrint('dictation: $event');
}

/// Puts what is spoken into a box the user may also be typing in.
///
/// A speech engine reports everything said so far, and its newest words can
/// still change, so while the box holds what was last put there the spoken
/// part is simply replaced. Once the user changes the box by hand, their text
/// is kept exactly as it is, and only what is said from then on is added
/// after it. Nothing they deleted comes back.
class SpokenDraft {
  /// The text speech is added after.
  String _before = '';

  /// Speech already in the box, or edited away, which is not added again.
  String _skip = '';

  /// Everything said, as of the last [merge].
  String _said = '';

  /// What the box held after the last [merge]; anything else is an edit.
  String _shown = '';

  /// Starts a stretch of dictation in a box that holds [box].
  void begin(String box) {
    _before = _shown = box;
    _skip = _said = '';
  }

  /// What the box should hold, given what it holds now and everything
  /// [said] so far; null when it should be left alone.
  String? merge(String box, String said) {
    if (box != _shown) {
      _before = box;
      _skip = _said;
    }
    _said = said;
    final fresh = _after(_skip, said);
    final gap = _before.isEmpty || fresh.isEmpty || RegExp(r'\s$').hasMatch(_before) ? '' : ' ';
    _shown = '$_before$gap$fresh';
    return _shown == box ? null : _shown;
  }

  /// The words of [said] that follow the ones it shares with [skip]. By
  /// words, because an engine may still be finishing the last one.
  static String _after(String skip, String said) {
    if (skip.isEmpty) return said;
    final old = skip.trim().split(RegExp(r'\s+')), now = said.trim().split(RegExp(r'\s+'));
    var same = 0;
    while (same < old.length && same < now.length && old[same] == now[same]) {
      same++;
    }
    return now.skip(same).join(' ');
  }
}

/// Speech to text for as long as the user wants to keep talking.
abstract class Dictation extends ChangeNotifier {
  /// Why listening could not start or stopped early, in plain words.
  String? problem;

  /// Which engine, model and language this is, to tell when the user has
  /// changed them.
  String get setup;

  bool get listening;

  /// The mic is off, and the last words are still being written down.
  bool get finishing => false;

  /// What is going on, for a line under the box; null when there is nothing to say.
  String? get status => null;

  /// Everything recognised since [start], including the words still coming.
  String get text;

  Future<void> start();

  /// Stops listening. Completes once [text] holds everything that was said.
  Future<void> stop();
}

/// Android's own recogniser. It needs no download, and for some languages a
/// connection.
///
/// It works in rounds: it listens, and when the speaker pauses it hands back
/// that round's words and stops. This starts the next round as soon as the
/// last has finished and keeps everything said so far, until [stop] is called
/// or several rounds pass in silence. Some phones refuse the next round.
class SystemDictation extends Dictation {
  SystemDictation({this.localeId});

  // The plugin keeps the listeners from its first `initialize`, so they are
  // static and hand events to whichever dictation is running.
  static final _speech = SpeechToText();
  static SystemDictation? _active;

  /// Language to listen for, such as `en_IN` or `hi_IN`; null is the phone's.
  final String? localeId;

  bool _wanted = false;

  /// What earlier rounds produced.
  String _kept = '';

  /// The round under way. Google's recogniser splits a long round into
  /// pieces: it settles one piece ([_settled] grows), then starts reporting
  /// the next from scratch ([_live] is replaced as it is refined). Other
  /// recognisers report the whole round every time. [_join] copes with both,
  /// and a round is folded into [_kept] only when the next one begins, so
  /// nothing is lost whether or not it is ever marked final.
  String _settled = '';
  String _live = '';
  bool _heardThisRound = false;
  int _silentRounds = 0;
  int _faults = 0;
  Timer? _next;

  @override
  String get setup => 'system:$localeId';

  @override
  bool get listening => _wanted;

  @override
  String? get status => _wanted ? 'Listening…' : null;

  @override
  String get text => [_kept, _join(_settled, _live)].where((s) => s.isNotEmpty).join(' ');

  static String _plain(String s) => s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ').trim();

  /// [more] added to [soFar], unless one already contains the other: a
  /// recogniser that repeats the whole round each time must not double it.
  @visibleForTesting
  static String joinForTest(String soFar, String more) => _join(soFar, more);

  static String _join(String soFar, String more) {
    if (soFar.isEmpty) return more;
    if (more.isEmpty) return soFar;
    final a = _plain(soFar), b = _plain(more);
    if (b.startsWith(a)) return more;
    if (a.endsWith(b)) return soFar;
    return '$soFar $more';
  }

  @override
  Future<void> start() async {
    problem = null;
    _kept = _settled = _live = '';
    _silentRounds = _faults = 0;
    final ready = await _speech.initialize(onStatus: _status, onError: _error);
    if (!ready) {
      problem = 'Speech recognition is not available. Check that the app may use the microphone.';
      notifyListeners();
      return;
    }
    _active = this;
    _wanted = true;
    notifyListeners();
    await _beginRound();
  }

  Future<void> _beginRound() async {
    if (!_wanted || _active != this) return;
    // The recogniser has not let go of the last round yet: look again shortly.
    if (_speech.isListening) return _later(const Duration(milliseconds: 250));
    _kept = text;
    _settled = _live = '';
    _heardThisRound = false;
    await _speech.listen(
      onResult: (result) {
        final words = result.recognizedWords;
        _trace('${result.resultTypeValue.name} ${words.length} chars');
        if (_active != this || !_wanted || words.isEmpty) return;
        if (result.resultTypeValue == ResultType.partial) {
          _live = words;
        } else {
          // A piece, or the round, is settled.
          _settled = _join(_settled, words);
          _live = '';
        }
        _heardThisRound = true;
        _silentRounds = _faults = 0;
        notifyListeners();
      },
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
        localeId: localeId,
        listenFor: const Duration(minutes: 5),
      ),
    );
  }

  void _later(Duration delay) {
    _next?.cancel();
    _next = Timer(delay, _beginRound);
  }

  static void _status(String status) {
    _trace('status $status');
    final d = _active;
    // A round is over. Carry on while the user still wants to talk, but stop
    // after a few rounds in which nothing was said.
    if (d == null || status != SpeechToText.doneStatus || !d._wanted) return;
    if (!d._heardThisRound && ++d._silentRounds >= 3) {
      d.stop();
    } else {
      d._later(const Duration(milliseconds: 150));
    }
  }

  static void _error(SpeechRecognitionError error) {
    _trace('error ${error.errorMsg}');
    final d = _active;
    if (d == null || !d._wanted) return;
    switch (error.errorMsg) {
      // Hearing nothing is not a fault; the round simply ends.
      case 'error_no_match' || 'error_speech_timeout':
        return;
      // The recogniser was not ready for the next round. Give it a moment and
      // try again; only give up if it keeps happening.
      case 'error_client' || 'error_busy' || 'error_server_disconnected' || 'error_too_many_requests':
        if (++d._faults <= 4) return d._later(const Duration(milliseconds: 600));
        d.problem = 'Speech recognition keeps stopping. Try again in a moment.';
      case 'error_permission':
        d.problem = 'Allow the microphone for this app to speak entries.';
      case 'error_network' || 'error_network_timeout' || 'error_server':
        d.problem = 'Speech recognition needs a connection for this language.';
      case 'error_language_not_supported' || 'error_language_unavailable':
        d.problem = 'This phone cannot recognise that language. Pick another with the button at the top.';
      default:
        d.problem = 'Speech recognition stopped (${error.errorMsg}).';
    }
    d.stop();
  }

  @override
  Future<void> stop() async {
    if (!_wanted) return;
    _wanted = false;
    _next?.cancel();
    notifyListeners();
    // Only ask a recogniser that is actually listening; otherwise Android
    // reports a client error.
    if (_speech.isListening) await _speech.stop();
  }

  /// Languages the phone can recognise, as (id, name), for the picker.
  static Future<List<(String, String)>> languages() async {
    if (!await _speech.initialize(onStatus: _status, onError: _error)) return const [];
    final all = [for (final l in await _speech.locales()) (l.localeId, l.name)];
    all.sort((a, b) => a.$2.compareTo(b.$2));
    return all;
  }

  @override
  void dispose() {
    _next?.cancel();
    if (_active == this) {
      _active = null;
      if (_wanted && _speech.isListening) _speech.stop();
    }
    super.dispose();
  }
}
