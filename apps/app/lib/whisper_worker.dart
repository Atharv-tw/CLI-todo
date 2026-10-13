import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Samples a second the worker expects: mono, in the range -1 to 1.
const speechSampleRate = 16000;

/// What the worker needs to load a model. Sent once, when it is spawned.
class WorkerSetup {
  const WorkerSetup({
    required this.replies,
    required this.encoder,
    required this.decoder,
    required this.tokens,
    required this.detector,
    required this.language,
    required this.threads,
  });

  final SendPort replies;
  final String encoder;
  final String decoder;
  final String tokens;
  final String detector;

  /// A Whisper language code, or empty to work it out from the speech.
  final String language;
  final int threads;
}

/// Sent to the worker besides audio (a [Float32List]).
enum WorkerOrder {
  /// The speaker has stopped: write down what is left.
  finish,
  close,
}

sealed class WorkerReply {
  const WorkerReply();
}

/// The model has loaded; audio goes to [inbox].
class WorkerReady extends WorkerReply {
  const WorkerReady(this.inbox);
  final SendPort inbox;
}

class WorkerFailed extends WorkerReply {
  const WorkerFailed(this.message);
  final String message;
}

/// A stretch of speech, written down.
class WorkerText extends WorkerReply {
  const WorkerText(this.text);
  final String text;
}

/// Whether someone is speaking, and whether speech is being written down.
class WorkerState extends WorkerReply {
  const WorkerState({required this.hearing, required this.writing});
  final bool hearing;
  final bool writing;
}

/// Everything handed over before [WorkerOrder.finish] has been written down.
class WorkerFinished extends WorkerReply {
  const WorkerFinished();
}

// Whisper marks sounds that are not speech like this; they are not the diary's business.
final _aside = RegExp(r'\[[^\]]*\]|\([^)]*\)|♪+');

/// What Whisper wrote for one stretch of speech, without its asides.
String tidySpeech(String raw) => raw.replaceAll(_aside, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Runs in its own isolate, because writing down a sentence takes a second or
/// more and would freeze the screen. Audio comes in as it is recorded; a
/// speech detector cuts it where the speaker pauses, and each stretch is
/// given to Whisper, which cannot follow along word by word.
void whisperWorker(WorkerSetup setup) {
  final out = setup.replies;
  late final sherpa.OfflineRecognizer recognizer;
  late final sherpa.VoiceActivityDetector detector;
  try {
    sherpa.initBindings();
    recognizer = sherpa.OfflineRecognizer(sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        whisper: sherpa.OfflineWhisperModelConfig(
          encoder: setup.encoder,
          decoder: setup.decoder,
          language: setup.language,
          task: 'transcribe',
          // Silence added after each stretch so Whisper sees where it ends:
          // three seconds, where the default is ten and makes it far slower.
          tailPaddings: 300,
        ),
        tokens: setup.tokens,
        numThreads: setup.threads,
        modelType: 'whisper',
        debug: false,
      ),
    ));
    detector = sherpa.VoiceActivityDetector(
      config: sherpa.VadModelConfig(
        sileroVad: sherpa.SileroVadModelConfig(
          model: setup.detector,
          // A pause this long ends a stretch. Whisper takes at most thirty
          // seconds at a time, so a long one is cut before that.
          minSilenceDuration: 0.6,
          minSpeechDuration: 0.25,
          maxSpeechDuration: 25,
        ),
        sampleRate: speechSampleRate,
        debug: false,
      ),
      bufferSizeInSeconds: 60,
    );
  } catch (e) {
    out.send(WorkerFailed('$e'));
    return;
  }

  final window = detector.config.sileroVad.windowSize;
  var pending = Float32List(0);
  var hearing = false;

  void writeDown() {
    if (detector.isEmpty()) return;
    out.send(WorkerState(hearing: hearing, writing: true));
    while (!detector.isEmpty()) {
      final samples = detector.front().samples;
      detector.pop();
      final stream = recognizer.createStream();
      stream.acceptWaveform(samples: samples, sampleRate: speechSampleRate);
      recognizer.decode(stream);
      final text = tidySpeech(recognizer.getResult(stream).text);
      stream.free();
      if (text.isNotEmpty) out.send(WorkerText(text));
    }
    out.send(WorkerState(hearing: hearing, writing: false));
  }

  void hear(Float32List samples) {
    // The detector takes fixed windows; what does not fill one waits.
    final all = Float32List(pending.length + samples.length)
      ..setAll(0, pending)
      ..setAll(pending.length, samples);
    var at = 0;
    for (; at + window <= all.length; at += window) {
      detector.acceptWaveform(Float32List.sublistView(all, at, at + window));
      final now = detector.isDetected();
      if (now != hearing) {
        hearing = now;
        out.send(WorkerState(hearing: hearing, writing: false));
      }
      writeDown();
    }
    pending = Float32List.sublistView(all, at);
  }

  final inbox = ReceivePort();
  inbox.listen((message) {
    switch (message) {
      case Float32List samples:
        hear(samples);
      case WorkerOrder.finish:
        detector.flush();
        hearing = false;
        writeDown();
        detector.reset();
        pending = Float32List(0);
        out.send(const WorkerFinished());
      case WorkerOrder.close:
        inbox.close();
        detector.free();
        recognizer.free();
    }
  });
  out.send(WorkerReady(inbox.sendPort));
}
