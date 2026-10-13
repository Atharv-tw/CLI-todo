import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Whether this device can turn speech into text. The phone uses Android's
/// own recogniser; Linux has none, so there is no mic button there.
bool get voiceSupported => Platform.isAndroid;

/// Speech to text for as long as the user wants to keep talking.
///
/// Android's recogniser stops by itself at each pause. This restarts it and
/// joins the pieces, until [stop] is called or nothing has been said for a
/// couple of rounds.
class Dictation extends ChangeNotifier {
  // The plugin keeps the listeners from its first `initialize`, so they are
  // static and hand events to whichever dictation is running.
  static final _speech = SpeechToText();
  static Dictation? _active;

  /// Language to listen for, such as `en_IN` or `hi_IN`; null is the phone's.
  String? localeId;

  bool _wanted = false;
  String _said = '';
  String _hearing = '';
  int _silentRounds = 0;

  /// Why listening could not start or stopped early, in plain words.
  String? problem;

  bool get listening => _wanted;

  /// Everything recognised since [start], including the words still coming.
  String get text => [_said, _hearing].where((s) => s.isNotEmpty).join(' ');

  Future<void> start() async {
    problem = null;
    _said = _hearing = '';
    _silentRounds = 0;
    final ready = await _speech.initialize(onStatus: _status, onError: _error);
    if (!ready) {
      problem = 'Speech recognition is not available. Check that the app may use the microphone.';
      notifyListeners();
      return;
    }
    _active = this;
    _wanted = true;
    notifyListeners();
    await _listen();
  }

  Future<void> _listen() => _speech.listen(
        onResult: (result) {
          if (_active != this) return;
          if (result.finalResult) {
            _said = [_said, result.recognizedWords].where((s) => s.isNotEmpty).join(' ');
            _hearing = '';
          } else {
            _hearing = result.recognizedWords;
          }
          if (result.recognizedWords.isNotEmpty) _silentRounds = 0;
          notifyListeners();
        },
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          partialResults: true,
          autoPunctuation: true,
          localeId: localeId,
          listenFor: const Duration(minutes: 2),
          pauseFor: const Duration(seconds: 6),
        ),
      );

  static void _status(String status) {
    final d = _active;
    // The recogniser ended a round. Carry on while the user still wants to
    // talk, but give up after two rounds of silence.
    if (d == null || status != SpeechToText.doneStatus || !d._wanted) return;
    if (++d._silentRounds > 2) {
      d.stop();
    } else {
      d._listen();
    }
  }

  static void _error(SpeechRecognitionError error) {
    final d = _active;
    if (d == null) return;
    // Hearing nothing is not a fault; the status handler deals with it.
    if (error.errorMsg == 'error_no_match' || error.errorMsg == 'error_speech_timeout') return;
    d.problem = switch (error.errorMsg) {
      'error_permission' || 'error_insufficient_permissions' => 'Allow the microphone for this app to speak entries.',
      'error_network' || 'error_network_timeout' || 'error_server' =>
        'Speech recognition needs a connection for this language.',
      'error_language_not_supported' || 'error_language_unavailable' =>
        'This phone cannot recognise that language. Pick another in the Diary menu.',
      _ => 'Could not hear that (${error.errorMsg}).',
    };
    d.stop();
  }

  Future<void> stop() async {
    if (!_wanted) return;
    _wanted = false;
    // Keep the words that were still arriving.
    _said = text;
    _hearing = '';
    notifyListeners();
    await _speech.stop();
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
    if (_active == this) {
      _active = null;
      if (_wanted) _speech.stop();
    }
    super.dispose();
  }
}
