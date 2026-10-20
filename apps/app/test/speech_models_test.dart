import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vault_app/speech_models.dart';
import 'package:vault_app/whisper_dictation.dart';
import 'package:vault_app/whisper_worker.dart';

Uint8List _bytes(int length, int seed) => Uint8List.fromList([for (var i = 0; i < length; i++) (i * 7 + seed) % 251]);

void main() {
  late HttpServer server;
  late Directory dir;
  late SpeechLibrary library;
  late SpeechModel model;

  final files = {
    'encoder': _bytes(70000, 1),
    'decoder': _bytes(150000, 2),
    'tokens': _bytes(900, 3),
    'detector': _bytes(5000, 4),
  };

  /// Requests seen, as `path` or `path from N` when only the rest was asked for.
  final asked = <String>[];

  setUp(() async {
    asked.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final response = request.response;
      final name = request.uri.pathSegments.last;
      final range = request.headers.value(HttpHeaders.rangeHeader);
      asked.add(range == null ? request.uri.path : '${request.uri.path} from ${range.substring(6, range.length - 1)}');
      if (request.uri.path.startsWith('/moved/')) {
        // Model hosts answer with a redirect to where the file really is.
        response.statusCode = HttpStatus.found;
        response.headers.set(HttpHeaders.locationHeader, '/files/$name');
      } else if (files[name] case final body?) {
        final from = range == null ? 0 : int.parse(range.substring(6, range.length - 1));
        if (from > body.length) {
          response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        } else {
          response.statusCode = from == 0 ? HttpStatus.ok : HttpStatus.partialContent;
          response.contentLength = body.length - from;
          response.add(Uint8List.sublistView(body, from));
        }
      } else {
        response.statusCode = HttpStatus.notFound;
      }
      await response.close();
    });
    final base = 'http://127.0.0.1:${server.port}';
    dir = Directory.systemTemp.createTempSync('speech');
    library = SpeechLibrary(dir, detector: SpeechFile('detector.onnx', '$base/files/detector', 5000));
    model = SpeechModel(
      id: 'test',
      name: 'Test',
      about: '',
      source: '',
      files: [
        SpeechFile('encoder.onnx', '$base/moved/encoder', 70000),
        SpeechFile('decoder.onnx', '$base/files/decoder', 150000),
        SpeechFile('tokens.txt', '$base/files/tokens', 900),
      ],
    );
  });

  tearDown(() async {
    await server.close(force: true);
    dir.deleteSync(recursive: true);
  });

  test('a model downloads whole, through a redirect, and is then ready', () async {
    expect(library.has(model), isFalse);
    expect(await library.download(model), isTrue);
    expect(library.has(model), isTrue);
    expect(library.problem, isNull);
    expect(library.downloading, isNull);
    expect(File(library.pathOf(model, 'encoder.onnx')).readAsBytesSync(), files['encoder']);
    expect(File(library.pathOf(model, 'decoder.onnx')).readAsBytesSync(), files['decoder']);
    expect(File(library.detectorPath).readAsBytesSync(), files['detector']);
    expect(dir.listSync(recursive: true).where((f) => f.path.endsWith('.part')), isEmpty);

    // Asking again fetches nothing.
    asked.clear();
    expect(await library.download(model), isTrue);
    expect(asked, isEmpty);

    library.delete(model);
    expect(library.has(model), isFalse);
    expect(File(library.detectorPath).existsSync(), isTrue);
  });

  test('a download that stopped carries on from where it got to', () async {
    final decoder = File(library.pathOf(model, 'decoder.onnx'));
    decoder.parent.createSync(recursive: true);
    File('${decoder.path}.part').writeAsBytesSync(Uint8List.sublistView(files['decoder']!, 0, 60000));

    expect(await library.download(model), isTrue);
    expect(asked, contains('/files/decoder from 60000'));
    expect(decoder.readAsBytesSync(), files['decoder']);
  });

  test('kept bytes that cannot belong to the file are thrown away', () async {
    final tokens = File(library.pathOf(model, 'tokens.txt'));
    tokens.parent.createSync(recursive: true);
    File('${tokens.path}.part').writeAsBytesSync(_bytes(5000, 9));

    expect(await library.download(model), isTrue);
    expect(tokens.readAsBytesSync(), files['tokens']);
  });

  test('a file the host does not have leaves the model not ready, with a reason', () async {
    final broken = SpeechModel(
      id: 'broken',
      name: 'Broken',
      about: '',
      source: '',
      files: [...model.files.take(2), SpeechFile('tokens.txt', 'http://127.0.0.1:${server.port}/files/gone', 900)],
    );
    expect(await library.download(broken), isFalse);
    expect(library.has(broken), isFalse);
    expect(library.problem, contains('download stopped'));
    expect(library.downloading, isNull);
  });

  test('every model in the list has the three files the worker opens', () {
    for (final m in speechModels) {
      expect(m.files.map((f) => f.name), ['encoder.onnx', 'decoder.onnx', 'tokens.txt'], reason: m.id);
      expect(m.files.every((f) => f.url.startsWith('https://')), isTrue, reason: m.id);
    }
    expect(speechModels.map((m) => m.id).toSet().length, speechModels.length);
  });

  test('recorded bytes become samples, even when a chunk splits one', () {
    // 0x0001 = 1, 0x8000 = -32768, 0x7fff = 32767, as little-endian pairs.
    final pcm = Uint8List.fromList([0x01, 0x00, 0x00, 0x80, 0xff, 0x7f]);
    final (first, carry) = pcm16ToSamples(Uint8List.sublistView(pcm, 0, 3));
    expect(first, [1 / 32768]);
    expect(carry, 0x00);
    final (rest, left) = pcm16ToSamples(Uint8List.sublistView(pcm, 3), carry);
    expect(rest, [-1.0, 32767 / 32768]);
    expect(left, isNull);
  });

  test('sounds Whisper notes in brackets are left out of the text', () {
    expect(tidySpeech(' Woke up late  today. '), 'Woke up late today.');
    expect(tidySpeech('[BLANK_AUDIO]'), '');
    expect(tidySpeech('(keyboard clicking) Then I started DSA [music]'), 'Then I started DSA');
  });
}
