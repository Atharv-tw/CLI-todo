// Checks the on-device speech engine end to end without a microphone: it
// downloads a model if this machine does not have it, then feeds a recording
// through the same worker the app uses and prints what was written.
//
//   flutter test tool/voice_check_test.dart \
//     --dart-define=WAV=/path/to/16k-mono.wav [--dart-define=MODEL=base] [--dart-define=LANGUAGE=en]
//
// It is not part of the test suite: it needs the network and a few minutes.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vault_app/speech_models.dart';
import 'package:vault_app/whisper_dictation.dart';
import 'package:vault_app/whisper_worker.dart';

const _wav = String.fromEnvironment('WAV');
const _model = String.fromEnvironment('MODEL', defaultValue: 'base');
const _language = String.fromEnvironment('LANGUAGE');

/// The samples of a 16-bit mono WAV file recorded at [speechSampleRate].
Uint8List _pcm(File file) {
  final bytes = file.readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  var at = 12;
  int? rate, channels, bits;
  while (at + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes, at, at + 4);
    final size = data.getUint32(at + 4, Endian.little);
    if (id == 'fmt ') {
      channels = data.getUint16(at + 10, Endian.little);
      rate = data.getUint32(at + 12, Endian.little);
      bits = data.getUint16(at + 22, Endian.little);
    } else if (id == 'data') {
      if (rate != speechSampleRate || channels != 1 || bits != 16) {
        fail('Needs 16 kHz, mono, 16-bit. This is $rate Hz, $channels channel(s), $bits-bit.');
      }
      return Uint8List.sublistView(bytes, at + 8, (at + 8 + size).clamp(0, bytes.length));
    }
    at += 8 + size + (size.isOdd ? 1 : 0);
  }
  fail('No audio found in ${file.path}');
}

void main() {
  test('a recording comes out as text', timeout: const Timeout(Duration(minutes: 20)), () async {
    expect(_wav, isNotEmpty, reason: 'Pass --dart-define=WAV=/path/to/file.wav');
    final model = speechModels.firstWhere((m) => m.id == _model);
    final library = SpeechLibrary(
      Directory(p.join(Platform.environment['HOME']!, '.local', 'share', 'dev.atharv.vault', 'speech')),
    );
    if (!library.has(model)) {
      stdout.writeln('Downloading ${model.name}, ${model.size}, to ${library.root.path}');
      var shown = -1;
      library.addListener(() {
        final tenth = (library.progress * 10).floor();
        if (tenth != shown) stdout.writeln('  ${(shown = tenth) * 10}%');
      });
      expect(await library.download(model), isTrue, reason: library.problem);
    }

    final replies = ReceivePort();
    final written = <String>[];
    final finished = Completer<void>();
    final ready = Completer<SendPort>();
    replies.listen((message) {
      switch (message) {
        case WorkerReady(:final inbox):
          ready.complete(inbox);
        case WorkerText(:final text):
          stdout.writeln('  > $text');
          written.add(text);
        case WorkerFinished():
          finished.complete();
        case WorkerFailed(:final message):
          finished.completeError(message);
        case WorkerState():
          break;
        default:
          if (!finished.isCompleted) finished.completeError('The worker stopped: $message');
      }
    });

    final clock = Stopwatch()..start();
    await Isolate.spawn(
      whisperWorker,
      WorkerSetup(
        replies: replies.sendPort,
        encoder: library.pathOf(model, 'encoder.onnx'),
        decoder: library.pathOf(model, 'decoder.onnx'),
        tokens: library.pathOf(model, 'tokens.txt'),
        detector: library.detectorPath,
        language: model.language ?? _language,
        threads: 4,
      ),
      onError: replies.sendPort,
      onExit: replies.sendPort,
    );
    final inbox = await Future.any([ready.future, finished.future.then((_) => throw 'no worker')]);
    stdout.writeln('Model loaded in ${clock.elapsedMilliseconds} ms');

    // Hand it over the way a microphone does: a tenth of a second at a time,
    // in chunks that do not line up with whole samples.
    final pcm = _pcm(File(_wav));
    int? carry;
    for (var at = 0; at < pcm.length; at += 3201) {
      final (samples, left) = pcm16ToSamples(Uint8List.sublistView(pcm, at, (at + 3201).clamp(0, pcm.length)), carry);
      carry = left;
      inbox.send(samples);
    }
    clock.reset();
    inbox.send(WorkerOrder.finish);
    await finished.future;
    final seconds = pcm.length / 2 / speechSampleRate;
    stdout.writeln('${seconds.toStringAsFixed(1)} s of audio written down in ${clock.elapsedMilliseconds} ms');
    inbox.send(WorkerOrder.close);
    replies.close();

    expect(written.join(' ').trim(), isNotEmpty);
  });
}
