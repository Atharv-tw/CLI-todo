import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

import 'speech_models.dart';
import 'voice.dart';
import 'whisper_worker.dart';

/// Recorded bytes (16-bit, little-endian) as samples from -1 to 1. A chunk
/// can end half way through a sample; that byte is returned as the carry to
/// put in front of the next chunk.
(Float32List, int?) pcm16ToSamples(Uint8List bytes, [int? carry]) {
  final all = carry == null ? bytes : (Uint8List(bytes.length + 1)..[0] = carry..setAll(1, bytes));
  final count = all.length ~/ 2;
  final data = ByteData.sublistView(all);
  final samples = Float32List(count);
  for (var i = 0; i < count; i++) {
    samples[i] = data.getInt16(i * 2, Endian.little) / 32768;
  }
  return (samples, all.length.isOdd ? all.last : null);
}

/// Speech to text with a Whisper model on the device: no account, no
/// connection, and the recording never leaves it. The words arrive a stretch
/// at a time, each time the speaker pauses.
class WhisperDictation extends Dictation {
  WhisperDictation({required this.model, required this.library, this.language = ''});

  final SpeechModel model;
  final SpeechLibrary library;

  /// A Whisper language code for the models that can write any; empty lets
  /// the model work it out.
  final String language;

  @override
  String get setup => '${model.id}:${model.language ?? language}';

  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _audio;
  int? _carry;

  Isolate? _worker;
  ReceivePort? _replies;
  SendPort? _inbox;

  /// Audio recorded while the model was still loading.
  final _early = <Float32List>[];
  bool _finishWhenLoaded = false;

  bool _listening = false;
  bool _hearing = false;
  bool _writing = false;
  Completer<void>? _finished;
  String _text = '';

  /// The model takes a few hundred megabytes of memory while it is loaded;
  /// it is let go when the mic has been off for a while.
  Timer? _unload;

  @override
  bool get listening => _listening;

  @override
  bool get finishing => _finished != null;

  @override
  String get text => _text;

  @override
  String? get status {
    if (finishing) return 'Writing it down…';
    if (!_listening) return null;
    if (_inbox == null) return 'Getting ready. You can start talking.';
    if (_writing) return 'Writing it down. Keep going.';
    return _hearing ? 'Listening…' : 'Listening. The words appear when you pause.';
  }

  @override
  Future<void> start() async {
    if (_listening || finishing) return;
    _unload?.cancel();
    problem = null;
    _text = '';
    _carry = null;
    try {
      final recorder = _recorder ??= AudioRecorder();
      if (!await recorder.hasPermission()) {
        problem = 'Allow the microphone for this app to speak entries.';
        notifyListeners();
        return;
      }
      final audio = await recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: speechSampleRate,
        numChannels: 1,
        androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.voiceRecognition, manageBluetooth: false),
      ));
      _audio = audio.listen(_heard, onError: (Object e) => _fail('The microphone stopped.'));
    } catch (e) {
      debugPrint('microphone: $e');
      problem = Platform.isLinux
          ? 'Could not open the microphone. On Linux this needs parecord (the pulseaudio-utils package).'
          : 'Could not open the microphone.';
      notifyListeners();
      return;
    }
    _listening = true;
    notifyListeners();
    await _load();
  }

  Future<void> _load() async {
    if (_worker != null) return;
    final replies = _replies = ReceivePort();
    replies.listen(_reply);
    _worker = await Isolate.spawn(
      whisperWorker,
      WorkerSetup(
        replies: replies.sendPort,
        encoder: library.pathOf(model, 'encoder.onnx'),
        decoder: library.pathOf(model, 'decoder.onnx'),
        tokens: library.pathOf(model, 'tokens.txt'),
        detector: library.detectorPath,
        language: model.language ?? language,
        // Leave a core or two for the screen and the recorder.
        threads: (Platform.numberOfProcessors - 2).clamp(1, 4),
      ),
      onError: replies.sendPort,
      onExit: replies.sendPort,
      debugName: 'whisper',
    );
  }

  void _heard(Uint8List bytes) {
    final (samples, carry) = pcm16ToSamples(bytes, _carry);
    _carry = carry;
    if (samples.isEmpty) return;
    if (_inbox case final inbox?) {
      inbox.send(samples);
    } else {
      _early.add(samples);
    }
  }

  void _reply(Object? message) {
    switch (message) {
      case WorkerReady(:final inbox):
        _inbox = inbox;
        _early
          ..forEach(inbox.send)
          ..clear();
        if (_finishWhenLoaded) inbox.send(WorkerOrder.finish);
        _finishWhenLoaded = false;
      case WorkerText(:final text):
        _text = _text.isEmpty ? text : '$_text $text';
      case WorkerState(:final hearing, :final writing):
        _hearing = hearing;
        _writing = writing;
      case WorkerFinished():
        _finished?.complete();
        _finished = null;
        _unload = Timer(const Duration(minutes: 2), _quit);
      case WorkerFailed(:final message):
        debugPrint('whisper: $message');
        return _fail('This speech model would not load. Remove it in Voice settings and download it again.');
      // The isolate's own reports: a list for an error, null when it has gone.
      case List<Object?> error:
        debugPrint('whisper: ${error.first}');
        return _fail('Speech to text stopped unexpectedly.');
      case null:
        _worker = null;
        _inbox = null;
        if (finishing || _listening) return _fail('Speech to text stopped unexpectedly.');
        return;
    }
    notifyListeners();
  }

  void _fail(String why) {
    problem = why;
    _listening = false;
    _audio?.cancel();
    _audio = null;
    _recorder?.stop();
    _finished?.complete();
    _finished = null;
    _quit();
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    if (!_listening) return _finished?.future;
    _listening = false;
    final finished = _finished = Completer<void>();
    notifyListeners();
    await _recorder?.stop();
    await _audio?.cancel();
    _audio = null;
    if (_inbox case final inbox?) {
      inbox.send(WorkerOrder.finish);
    } else {
      _finishWhenLoaded = true;
    }
    return finished.future;
  }

  void _quit() {
    _unload?.cancel();
    _inbox?.send(WorkerOrder.close);
    _inbox = null;
    _early.clear();
    _finishWhenLoaded = false;
    _replies?.close();
    _replies = null;
    // Give it a moment to hand back the model's memory, then make sure.
    final worker = _worker;
    _worker = null;
    if (worker != null) Timer(const Duration(seconds: 2), worker.kill);
  }

  @override
  void dispose() {
    _audio?.cancel();
    _recorder?.dispose();
    _quit();
    super.dispose();
  }
}
