import 'dart:io';

import 'package:path/path.dart' as p;

import 'embedded.g.dart';

/// A coding assistant `myvault init` can connect: it gets the tool server, so it
/// can read and change tasks, and the skills, so it knows how to do a daily
/// briefing and how to file the diary.
class Assistant {
  const Assistant({required this.id, required this.name, required this.command, required this.skillsDir});

  final String id;
  final String name;

  /// Its command-line program.
  final String command;

  /// Where it looks for skills, relative to the home folder.
  final String skillsDir;
}

const assistants = [
  Assistant(id: 'claude', name: 'Claude Code', command: 'claude', skillsDir: '.claude/skills'),
  Assistant(id: 'codex', name: 'Codex', command: 'codex', skillsDir: '.agents/skills'),
];

String get homeDir => Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '.';

/// Whether [command] can be run on this machine.
bool isInstalled(String command) {
  try {
    return Process.runSync(command, ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

/// The path an assistant should start the tool server with. The launcher on
/// the PATH if there is one, so it keeps working when the program is updated.
String todoCommand() {
  for (final name in ['myvault', 'todo']) {
    for (final dir in (Platform.environment['PATH'] ?? '').split(Platform.isWindows ? ';' : ':')) {
      if (dir.isEmpty) continue;
      final candidate = File(p.join(dir, Platform.isWindows ? '$name.exe' : name));
      if (candidate.existsSync()) return candidate.path;
    }
  }
  final self = Platform.resolvedExecutable;
  return {'myvault', 'todo'}.contains(p.basenameWithoutExtension(self)) ? self : 'myvault';
}

/// Writes every skill into [dir], one folder each, replacing an older copy.
/// Returns the names written.
List<String> installSkills(String dir) {
  for (final skill in skills.entries) {
    File(p.join(dir, skill.key, 'SKILL.md'))
      ..createSync(recursive: true)
      ..writeAsStringSync(skill.value);
  }
  return skills.keys.toList();
}

/// Registers the tool server with [assistant] for every project of this user,
/// and installs the skills where it looks for them. Returns lines saying what
/// happened; never throws.
List<String> connect(Assistant assistant, {required String todo, String? home}) {
  final lines = <String>[];
  ProcessResult run(List<String> args) => Process.runSync(assistant.command, args);
  try {
    // Asking first keeps a second run from failing on "already exists".
    final known = run(['mcp', 'get', 'myvault']).exitCode == 0;
    if (known) {
      lines.add('${assistant.name} already has the Vault tools.');
    } else {
      final added = run([
        'mcp',
        'add',
        if (assistant.id == 'claude') ...['--scope', 'user'],
        'myvault',
        '--',
        todo,
        'mcp',
      ]);
      lines.add(
        added.exitCode == 0
            ? '${assistant.name} can now read and change your tasks, diary and notes (tool server "myvault").'
            : '${assistant.name} would not take the tool server: ${('${added.stderr}'.trim().split('\n').last)}\n'
                  '  Add it yourself with: ${assistant.command} mcp add myvault -- $todo mcp',
      );
    }
  } on ProcessException {
    lines.add('${assistant.name} is not installed; skipped.');
    return lines;
  }
  final dir = p.join(home ?? homeDir, assistant.skillsDir);
  final names = installSkills(dir);
  lines.add('Skills for ${assistant.name}: ${names.join(', ')} (in $dir).');
  return lines;
}
