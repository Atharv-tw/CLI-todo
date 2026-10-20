import 'package:flutter/material.dart';

import 'theme.dart';

/// Shows a page from the vault: headings, bullets, quotes, tables, **bold**
/// and `code`. Links show as their text; `[[path|label]]` as the label.
class MarkdownView extends StatelessWidget {
  const MarkdownView(this.text, {super.key, this.maxBlocks});

  final String text;

  /// Show only this many blocks (headings, paragraphs, bullets), for a
  /// preview.
  final int? maxBlocks;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final blocks = <Widget>[];
    final lines = text.replaceAll('\r', '').split('\n');
    var i = 0;
    var inCode = false;
    final code = <String>[];
    while (i < lines.length) {
      final line = lines[i];
      if (line.trimLeft().startsWith('```')) {
        if (inCode) {
          blocks.add(_code(code.join('\n')));
          code.clear();
        }
        inCode = !inCode;
        i++;
        continue;
      }
      if (inCode) {
        code.add(line);
        i++;
        continue;
      }
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        i++;
        continue;
      }
      final heading = RegExp(r'^(#{1,4})\s+(.*)$').firstMatch(trimmed);
      if (heading != null) {
        final level = heading.group(1)!.length;
        final style = switch (level) {
          1 => t.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          2 => t.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          _ => t.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: AppColors.muted),
        };
        blocks.add(Padding(
          padding: EdgeInsets.only(top: blocks.isEmpty ? 0 : 14, bottom: 4),
          child: Text.rich(_inline(heading.group(2)!, style)),
        ));
        i++;
        continue;
      }
      if (trimmed.startsWith('|')) {
        final rows = <List<String>>[];
        while (i < lines.length && lines[i].trim().startsWith('|')) {
          final cells = lines[i].trim().split('|').map((c) => c.trim()).toList();
          final row = cells.sublist(1, cells.length - (cells.last.isEmpty ? 1 : 0));
          if (!row.every((c) => RegExp(r'^:?-{2,}:?$').hasMatch(c))) rows.add(row);
          i++;
        }
        blocks.add(_table(rows, t));
        continue;
      }
      final bullet = RegExp(r'^(\s*)([-*]|\d+\.)\s+(.*)$').firstMatch(line);
      if (bullet != null) {
        // A bullet takes the indented lines under it.
        var body = bullet.group(3)!;
        i++;
        while (i < lines.length &&
            lines[i].startsWith('  ') &&
            !RegExp(r'^\s*([-*]|\d+\.)\s').hasMatch(lines[i]) &&
            lines[i].trim().isNotEmpty) {
          body += ' ${lines[i].trim()}';
          i++;
        }
        final depth = (bullet.group(1)!.length / 2).floor();
        final mark = bullet.group(2)!;
        blocks.add(Padding(
          padding: EdgeInsets.only(left: 4 + depth * 16.0, top: 3, bottom: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: mark.endsWith('.') ? 22 : 14,
                child: Text(
                  mark.endsWith('.') ? mark : '•',
                  style: t.bodyMedium?.copyWith(color: AppColors.orange, fontWeight: FontWeight.w800),
                ),
              ),
              Expanded(child: Text.rich(_inline(body, t.bodyMedium?.copyWith(height: 1.4)))),
            ],
          ),
        ));
        continue;
      }
      if (trimmed.startsWith('>')) {
        blocks.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          decoration: const BoxDecoration(border: Border(left: BorderSide(color: AppColors.lavender, width: 3))),
          child: Text.rich(_inline(trimmed.replaceFirst(RegExp(r'^>\s?'), ''), t.bodyMedium)),
        ));
        i++;
        continue;
      }
      // A paragraph runs until a blank line or another kind of block.
      var para = trimmed;
      i++;
      while (i < lines.length &&
          lines[i].trim().isNotEmpty &&
          !RegExp(r'^(#{1,4}\s|\s*([-*]|\d+\.)\s|\||>|```)').hasMatch(lines[i].trimLeft())) {
        para += ' ${lines[i].trim()}';
        i++;
      }
      blocks.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text.rich(_inline(para, t.bodyMedium?.copyWith(height: 1.45))),
      ));
    }
    final shown = maxBlocks == null ? blocks : blocks.take(maxBlocks!).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: shown);
  }

  Widget _code(String text) => Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.raised, borderRadius: BorderRadius.circular(12)),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
        ),
      );

  Widget _table(List<List<String>> rows, TextTheme t) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (final (r, row) in rows.indexed)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              decoration: BoxDecoration(
                color: r == 0 ? AppColors.raised : null,
                border: const Border(bottom: BorderSide(color: AppColors.line)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (c, cell) in row.indexed)
                    Expanded(
                      flex: c == row.length - 1 ? 2 : 1,
                      child: Text.rich(
                        _inline(cell, t.bodySmall?.copyWith(fontWeight: r == 0 ? FontWeight.w700 : null)),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

final _span = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`|\[\[([^\]|]+)(?:\|([^\]]+))?\]\]|\[([^\]]+)\]\([^)]+\)');

/// Inline styling for one line of Markdown.
TextSpan _inline(String text, TextStyle? base) {
  final spans = <InlineSpan>[];
  var at = 0;
  for (final m in _span.allMatches(text)) {
    if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
    if (m.group(1) != null) {
      spans.add(TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w800)));
    } else if (m.group(2) != null) {
      spans.add(TextSpan(
        text: m.group(2),
        style: const TextStyle(fontFamily: 'monospace', backgroundColor: AppColors.raised),
      ));
    } else if (m.group(3) != null) {
      final label = m.group(4) ?? m.group(3)!.split('/').last;
      spans.add(TextSpan(text: label, style: const TextStyle(color: AppColors.lavender)));
    } else {
      spans.add(TextSpan(text: m.group(5), style: const TextStyle(color: AppColors.lavender)));
    }
    at = m.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return TextSpan(style: base, children: spans);
}
