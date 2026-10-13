import 'dart:io';

import 'package:flutter/material.dart';
import 'package:todo_core/todo_core.dart';

import 'speech_models.dart';
import 'state.dart';
import 'theme.dart';
import 'voice.dart';
import 'whisper_dictation.dart';

// Kept in this device's own settings: a model lives on one device.
const _engineKey = 'voice_engine';
const _languageKey = 'voice_language';
const _localeKey = 'voice_locale';

/// The engine choice that means Android's recogniser, not a model's id.
const _system = 'system';

/// The engine in use: [_system], a downloaded model's id, or null when
/// nothing has been set up.
String? _engineFor(Store store, SpeechLibrary? library) {
  final choice = store.getMeta(_engineKey);
  if (choice == _system && Platform.isAndroid) return _system;
  final ready = library?.ready ?? const <SpeechModel>[];
  if (ready.isEmpty) return null;
  return ready.any((m) => m.id == choice) ? choice : ready.first.id;
}

/// The dictation the user has set up, or null when there is none yet.
Future<Dictation?> dictationFor(Store store) async {
  final library = await SpeechLibrary.open();
  final engine = _engineFor(store, library);
  if (engine == null) return null;
  if (engine == _system) return SystemDictation(localeId: store.getMeta(_localeKey));
  return WhisperDictation(
    model: speechModels.firstWhere((m) => m.id == engine),
    library: library!,
    language: store.getMeta(_languageKey) ?? '',
  );
}

/// Opens the sheet where the way speech becomes text is chosen.
Future<void> showVoiceSettings(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => AppScope(state: AppScope.of(context), child: const VoiceSettings()),
    );

/// Which speech engine to use: a Whisper model kept on this device, picked
/// and downloaded here, or on a phone Android's own recogniser.
class VoiceSettings extends StatefulWidget {
  const VoiceSettings({super.key});

  @override
  State<VoiceSettings> createState() => _VoiceSettingsState();
}

class _VoiceSettingsState extends State<VoiceSettings> {
  SpeechLibrary? _library;
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    SpeechLibrary.open().then((library) {
      if (!mounted) return;
      library?.addListener(_changed);
      setState(() {
        _library = library;
        _opened = true;
      });
    });
  }

  @override
  void dispose() {
    _library?.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(() {});

  void _set(String key, String? value) => setState(() => AppScope.of(context).store.setMeta(key, value));

  Future<void> _download(SpeechModel model) async {
    final store = AppScope.of(context).store;
    if (await _library!.download(model)) store.setMeta(_engineKey, model.id);
    if (mounted) setState(() {});
  }

  Future<void> _pickLocale() async {
    final store = AppScope.of(context).store;
    final languages = await SystemDictation.languages();
    if (!mounted) return;
    final current = store.getMeta(_localeKey) ?? '';
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Language to listen for'),
        children: [
          if (languages.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text('Speech recognition is not available on this phone.'),
            ),
          for (final (id, name) in [('', "The phone's language"), ...languages])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, id),
              child: Text(name, style: current == id ? const TextStyle(fontWeight: FontWeight.w800) : null),
            ),
        ],
      ),
    );
    if (picked != null) _set(_localeKey, picked.isEmpty ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context).store;
    final text = Theme.of(context).textTheme;
    final library = _library;
    final engine = _engineFor(store, library);
    final muted = text.bodySmall?.copyWith(color: AppColors.muted);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.86),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewPaddingOf(context).bottom),
        children: [
          Text('Voice', style: text.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Speech is written down on this device by a model you download once. '
            'Nothing you say is sent anywhere. The words appear each time you pause.',
            style: muted,
          ),
          const SizedBox(height: 12),
          if (_opened && library == null)
            Text('This device gives the app nowhere to keep a speech model.', style: muted)
          else if (library != null) ...[
            for (final model in speechModelsFor(Platform.localeName))
              _ModelTile(
                model: model,
                ready: library.has(model),
                selected: engine == model.id,
                progress: library.downloading == model ? library.progress : null,
                busy: library.downloading != null,
                onSelect: () => _set(_engineKey, model.id),
                onDownload: () => _download(model),
                onCancel: library.cancel,
                onRemove: () => library.delete(model),
                // A model that writes any language is told which, when it is the one in use.
                language: engine == model.id && model.language == null ? store.getMeta(_languageKey) ?? '' : null,
                onLanguage: (code) => _set(_languageKey, code.isEmpty ? null : code),
              ),
            if (library.problem != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: Text(library.problem!, style: text.bodySmall?.copyWith(color: AppColors.red)),
              ),
          ],
          if (Platform.isAndroid) ...[
            const Divider(height: 28),
            _Choice(
              selected: engine == _system,
              onTap: () => _set(_engineKey, _system),
              title: "Android's own recogniser",
              about: 'No download. Needs a connection for some languages, and on some phones it stops at every pause.',
              trailing: TextButton(onPressed: _pickLocale, child: const Text('Language')),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.model,
    required this.ready,
    required this.selected,
    required this.progress,
    required this.busy,
    required this.onSelect,
    required this.onDownload,
    required this.onCancel,
    required this.onRemove,
    required this.language,
    required this.onLanguage,
  });

  final SpeechModel model;
  final bool ready;
  final bool selected;

  /// How far its download has got; null when it is not being downloaded.
  final double? progress;

  /// Another download is under way, so this one has to wait.
  final bool busy;
  final VoidCallback onSelect;
  final VoidCallback onDownload;
  final VoidCallback onCancel;
  final VoidCallback onRemove;

  /// The language it is set to write, shown with a way to change it; null
  /// when that does not apply.
  final String? language;
  final ValueChanged<String> onLanguage;

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Choice(
          key: ValueKey('voice-model-${model.id}'),
          selected: selected,
          onTap: ready ? onSelect : null,
          title: model.name,
          about: '${model.about} ${model.source}.',
          trailing: progress != null
              ? TextButton(onPressed: onCancel, child: const Text('Cancel'))
              : ready
                  ? IconButton(
                      tooltip: 'Remove from this device',
                      icon: const Icon(Icons.delete_outline_rounded, color: AppColors.muted),
                      onPressed: onRemove,
                    )
                  : FilledButton.tonalIcon(
                      key: ValueKey('voice-get-${model.id}'),
                      onPressed: busy ? null : onDownload,
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: Text(model.size),
                    ),
        ),
        if (progress != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(36, 0, 0, 10),
            child: Row(
              spacing: 12,
              children: [
                Expanded(child: LinearProgressIndicator(value: progress, borderRadius: BorderRadius.circular(4))),
                Text('${(progress * 100).floor()}%', style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
          ),
        if (language != null)
          Padding(
            padding: const EdgeInsets.only(left: 36, bottom: 6),
            child: Row(
              children: [
                Expanded(child: Text('Language you speak', style: Theme.of(context).textTheme.bodyMedium)),
                DropdownButton<String>(
                  key: const ValueKey('voice-language'),
                  value: language,
                  underline: const SizedBox.shrink(),
                  borderRadius: BorderRadius.circular(16),
                  items: [
                    for (final (code, name) in speechLanguages) DropdownMenuItem(value: code, child: Text(name)),
                  ],
                  onChanged: (code) => onLanguage(code ?? ''),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// One engine in the list: a mark for the one in use, what it is, and an
/// action on the right.
class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.selected,
    required this.onTap,
    required this.title,
    required this.about,
    required this.trailing,
  });

  final bool selected;
  final VoidCallback? onTap;
  final String title;
  final String about;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 12),
              child: Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                size: 24,
                color: selected ? AppColors.orange : (onTap == null ? AppColors.line : AppColors.muted),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(title, style: text.titleSmall),
                  Text(about, style: text.bodySmall?.copyWith(color: AppColors.muted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }
}
