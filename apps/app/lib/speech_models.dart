import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// One file of a speech model: where it comes from and what it is called here.
class SpeechFile {
  const SpeechFile(this.name, this.url, this.bytes);

  final String name;
  final String url;

  /// Size, for the list and the progress bar. A download is checked against
  /// what the server says it sent, not against this.
  final int bytes;
}

/// A Whisper model that runs on the device. Nothing is bundled with the app:
/// a model is downloaded once, when the user picks it.
class SpeechModel {
  const SpeechModel({
    required this.id,
    required this.name,
    required this.about,
    required this.source,
    required this.files,
    this.language,
  });

  final String id;
  final String name;

  /// Who it suits, in a line.
  final String about;

  /// Who publishes the files, shown before anything is downloaded.
  final String source;

  /// The language it always writes; null when the user can choose.
  final String? language;

  /// `encoder.onnx`, `decoder.onnx` and `tokens.txt`.
  final List<SpeechFile> files;

  int get bytes => files.fold(0, (sum, f) => sum + f.bytes);
  String get size => '${(bytes / 1000000).round()} MB';
}

/// Finds where people are speaking, so only speech is handed to Whisper.
/// Shared by every model.
const speechDetector = SpeechFile(
  'silero_vad.onnx',
  'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx',
  643854,
);

// Hugging Face URLs name a commit, so a file cannot change after this was written.
SpeechModel _whisper(
  String size,
  String commit, {
  required String name,
  required String about,
  required int encoder,
  required int decoder,
}) {
  final base = 'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-$size/resolve/$commit';
  return SpeechModel(
    id: size,
    name: name,
    about: about,
    source: 'OpenAI Whisper, converted by the sherpa-onnx project',
    files: [
      SpeechFile('encoder.onnx', '$base/$size-encoder.int8.onnx', encoder),
      SpeechFile('decoder.onnx', '$base/$size-decoder.int8.onnx', decoder),
      SpeechFile('tokens.txt', '$base/$size-tokens.txt', 816730),
    ],
  );
}

const _hinglish =
    'https://huggingface.co/parismitaglobalsolutions/indicconformer-sherpa-onnx/resolve/9721eb71eea141fae0982cfcdb9dd2e3d4953c4a/hi-hinglish-swift';

final speechModels = <SpeechModel>[
  _whisper(
    'base',
    'bb53ee204431c90d314c1cc08d28d23e5b7927cc',
    name: 'Whisper base',
    about: 'Any one language at a time; it mixes two badly. A good start on most phones.',
    encoder: 29120534,
    decoder: 130672026,
  ),
  const SpeechModel(
    id: 'hinglish',
    name: 'Hindi and English, mixed',
    about: 'Writes mixed Hindi and English in Roman letters, the way it is typed in chats.',
    source: "Oriserve's Whisper-Hindi2Hinglish, converted by Parismita Global Solutions",
    language: 'hi',
    files: [
      SpeechFile('encoder.onnx', '$_hinglish/encoder.int8.onnx', 29122029),
      SpeechFile('decoder.onnx', '$_hinglish/decoder.int8.onnx', 130781044),
      SpeechFile('tokens.txt', '$_hinglish/tokens.txt', 816730),
    ],
  ),
  _whisper(
    'small',
    '8f3c18b358db4d1f2fc1eae49d75cd20989e4309',
    name: 'Whisper small',
    about: 'Any one language at a time. More accurate, and slower to write.',
    encoder: 112442483,
    decoder: 262226114,
  ),
  _whisper(
    'tiny',
    '65176e2deb88badc814a94058666cadccc29b61c',
    name: 'Whisper tiny',
    about: 'Any one language at a time. Fastest and least accurate.',
    encoder: 12937772,
    decoder: 89855401,
  ),
];

/// The models in the order they are offered. The first one a device has is
/// used until another is picked, so where the device is set to India the
/// mixed Hindi-English model leads: Whisper's own models write Hindi in
/// whichever script they guess, a stretch at a time.
List<SpeechModel> speechModelsFor(String locale) {
  if (!RegExp(r'[_-]IN\b').hasMatch(locale)) return speechModels;
  return [...speechModels.where((m) => m.language == 'hi'), ...speechModels.where((m) => m.language != 'hi')];
}

/// Languages offered for the models that can write any. Whisper knows many
/// more; the empty code lets it work the language out from the speech.
const speechLanguages = <(String, String)>[
  ('', 'Work it out'),
  ('en', 'English'),
  ('hi', 'Hindi'),
  ('bn', 'Bengali'),
  ('mr', 'Marathi'),
  ('ta', 'Tamil'),
  ('te', 'Telugu'),
  ('gu', 'Gujarati'),
  ('kn', 'Kannada'),
  ('ml', 'Malayalam'),
  ('pa', 'Punjabi'),
  ('ur', 'Urdu'),
  ('es', 'Spanish'),
  ('fr', 'French'),
  ('de', 'German'),
  ('pt', 'Portuguese'),
  ('ar', 'Arabic'),
  ('ru', 'Russian'),
  ('id', 'Indonesian'),
  ('ja', 'Japanese'),
  ('ko', 'Korean'),
  ('zh', 'Chinese'),
];

class _Cancelled implements Exception {}

/// The speech models kept on this device, and the download under way.
class SpeechLibrary extends ChangeNotifier {
  SpeechLibrary(this.root, {this.detector = speechDetector});

  /// Folder the models live in, one sub-folder each.
  final Directory root;

  /// The speech detector fetched alongside any model.
  final SpeechFile detector;

  static SpeechLibrary? _shared;

  /// Set by tests in place of the app's own folder.
  @visibleForTesting
  static SpeechLibrary? override;

  /// The app's library, or null where the device gives no folder for it.
  static Future<SpeechLibrary?> open() async {
    if (override != null) return override;
    if (_shared != null) return _shared;
    try {
      // On a phone the models go in the app's folder on shared storage: still
      // private to the app and removed with it, but a model can also be
      // copied in over USB instead of downloaded.
      final home = (Platform.isAndroid ? await getExternalStorageDirectory() : null) ??
          await getApplicationSupportDirectory();
      return _shared = SpeechLibrary(Directory(p.join(home.path, 'speech')));
    } catch (_) {
      return null;
    }
  }

  SpeechModel? _downloading;
  int _received = 0;
  int _wanted = 1;
  bool _cancel = false;
  HttpClient? _client;
  DateTime _told = DateTime(0);

  /// Why the last download stopped, in plain words.
  String? problem;

  /// The model being fetched, if one is.
  SpeechModel? get downloading => _downloading;

  /// How far the download has got, from 0 to 1.
  double get progress => (_received / _wanted).clamp(0, 1).toDouble();

  String pathOf(SpeechModel model, String file) => p.join(root.path, model.id, file);
  String get detectorPath => p.join(root.path, detector.name);

  /// A file only takes its final name once it has arrived whole.
  bool has(SpeechModel model) =>
      File(detectorPath).existsSync() && model.files.every((f) => File(pathOf(model, f.name)).existsSync());

  /// The models this device has, the one to prefer first.
  List<SpeechModel> get ready => [for (final m in speechModelsFor(Platform.localeName)) if (has(m)) m];

  /// Fetches [model] and the speech detector. A download that stopped part
  /// way carries on from where it got to. True when the model is ready.
  Future<bool> download(SpeechModel model) async {
    if (_downloading != null) return false;
    final targets = [
      (detector, File(detectorPath)),
      for (final f in model.files) (f, File(pathOf(model, f.name))),
    ];
    _downloading = model;
    _cancel = false;
    problem = null;
    _received = 0;
    _wanted = targets.fold(0, (sum, t) => sum + t.$1.bytes);
    notifyListeners();

    final client = _client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
    try {
      for (final (file, to) in targets) {
        await _fetch(client, file, to);
      }
    } on _Cancelled {
      // The user's choice; what has arrived is kept for next time.
    } catch (e) {
      debugPrint('speech download: $e');
      problem = 'The download stopped. Check the connection and try again; it carries on from where it stopped.';
    } finally {
      client.close(force: true);
      _client = null;
      _downloading = null;
      notifyListeners();
    }
    return has(model);
  }

  Future<void> _fetch(HttpClient client, SpeechFile file, File to) async {
    if (to.existsSync()) {
      _received += file.bytes;
      return;
    }
    to.parent.createSync(recursive: true);
    final part = File('${to.path}.part');
    var have = part.existsSync() ? part.lengthSync() : 0;

    final request = await client.getUrl(Uri.parse(file.url));
    if (have > 0) request.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
    var response = await request.close();
    if (response.statusCode == HttpStatus.requestedRangeNotSatisfiable) {
      // What was kept is not a prefix of this file. Start it again.
      await response.drain<void>();
      part.deleteSync();
      have = 0;
      response = await (await client.getUrl(Uri.parse(file.url))).close();
    }
    if (response.statusCode == HttpStatus.ok) {
      have = 0; // the server sent the whole file, not the rest of it
    } else if (response.statusCode != HttpStatus.partialContent) {
      await response.drain<void>();
      throw HttpException('${response.statusCode} for ${file.name}');
    }

    _received += have;
    final expected = response.contentLength;
    var arrived = 0;
    final sink = part.openWrite(mode: have > 0 ? FileMode.append : FileMode.write);
    try {
      await for (final chunk in response) {
        if (_cancel) throw _Cancelled();
        sink.add(chunk);
        arrived += chunk.length;
        _received += chunk.length;
        final now = DateTime.now();
        if (now.difference(_told) > const Duration(milliseconds: 200)) {
          _told = now;
          notifyListeners();
        }
      }
    } finally {
      await sink.close();
    }
    if (expected >= 0 && arrived != expected) throw HttpException('${file.name} arrived incomplete');
    part.renameSync(to.path);
  }

  /// Stops the download under way, keeping what has arrived.
  void cancel() {
    if (_downloading == null) return;
    _cancel = true;
    _client?.close(force: true);
  }

  /// Frees the space [model] takes. The speech detector is small and stays.
  void delete(SpeechModel model) {
    final dir = Directory(p.join(root.path, model.id));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    notifyListeners();
  }
}
