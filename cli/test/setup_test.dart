import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:vault_cli/embedded.g.dart';
import 'package:vault_cli/setup.dart';

import '../tool/embed_skills.dart' as embed;

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('setup'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('the skills and schema built into the command match the files in the repository', () {
    expect(
      File('lib/embedded.g.dart').readAsStringSync(),
      embed.embedded(),
      reason: 'Run: dart run tool/embed_skills.dart',
    );
    expect(skills.keys, containsAll(['daily-briefing', 'file-diary']));
    expect(schemaSql, contains('create table'));
  });

  test('every skill says when to use it', () {
    for (final skill in skills.entries) {
      expect(skill.value, startsWith('---\nname: ${skill.key}\ndescription: '), reason: skill.key);
    }
  });

  test('skills are written one folder each, and a newer copy replaces an older one', () {
    final old = File(p.join(dir.path, 'file-diary', 'SKILL.md'))
      ..createSync(recursive: true)
      ..writeAsStringSync('old');
    expect(installSkills(dir.path), skills.keys);
    expect(old.readAsStringSync(), skills['file-diary']);
    expect(File(p.join(dir.path, 'daily-briefing', 'SKILL.md')).readAsStringSync(), skills['daily-briefing']);
  });

  group('connecting an assistant', () {
    late File log;
    late Assistant stub;

    setUp(() {
      // A stand-in for the assistant's program: it records how it was called
      // and remembers a tool server once one is added.
      log = File(p.join(dir.path, 'calls.log'));
      final added = p.join(dir.path, 'added');
      final program = File(p.join(dir.path, 'assistant'))
        ..writeAsStringSync(
          '#!/bin/sh\n'
          'echo "\$*" >> "${log.path}"\n'
          'case "\$1 \$2" in\n'
          '  "mcp get") [ -f "$added" ] || exit 1;;\n'
          '  "mcp add") touch "$added";;\n'
          'esac\n',
        );
      Process.runSync('chmod', ['+x', program.path]);
      stub = Assistant(id: 'claude', name: 'Stub', command: program.path, skillsDir: 'skills');
    });

    test('registers the tool server for every project, and installs the skills', () {
      final lines = connect(stub, todo: '/opt/todo', home: dir.path);
      expect(log.readAsLinesSync(), ['mcp get myvault', 'mcp add --scope user myvault -- /opt/todo mcp']);
      expect(lines.first, contains('can now read and change your tasks'));
      expect(File(p.join(dir.path, 'skills', 'file-diary', 'SKILL.md')).existsSync(), isTrue);
    });

    test('a second run adds nothing twice', () {
      connect(stub, todo: '/opt/todo', home: dir.path);
      log.writeAsStringSync('');
      final lines = connect(stub, todo: '/opt/todo', home: dir.path);
      expect(log.readAsLinesSync(), ['mcp get myvault']);
      expect(lines.first, contains('already has'));
    });

    test('an assistant that is not installed is skipped, not an error', () {
      final missing = Assistant(id: 'codex', name: 'Missing', command: p.join(dir.path, 'nope'), skillsDir: 'skills');
      expect(isInstalled(missing.command), isFalse);
      expect(connect(missing, todo: '/opt/todo', home: dir.path), ['Missing is not installed; skipped.']);
      expect(Directory(p.join(dir.path, 'skills')).existsSync(), isFalse);
    });
  }, testOn: 'posix');
}
