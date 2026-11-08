import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Dialect (Jordanian) words that must not appear in user-visible copy.
const _markers = [
  'ما قدرنا',
  'جرّب',
  'جرب',
  'مش',
  'لسا',
  'لسه',
  'شو',
  'لمين',
  'هيك',
  'بدك',
  'بدي',
  'انضاف',
  'انضافت',
  'هسا',
  'هلأ',
  'كمان',
  'منيح',
  'عشان',
  'زي',
  'اشي',
  'شي',
  'صار',
  'نرجّع',
  'وحدة',
];

void main() {
  test('UI copy under lib/ is Standard Arabic (no dialect markers)', () {
    final markers = _markers.join('|');
    // A marker counts only as a whole word: the chars around it are not
    // Arabic letters.
    final marker = RegExp(
      '(^|[^\\u0621-\\u064A])($markers)(?=\$|[^\\u0621-\\u064A])',
    );
    final literal = RegExp(r"'((?:[^'\\]|\\.)*)'");

    final hits = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    for (final file in files) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        for (final m in literal.allMatches(line)) {
          final text = m.group(1)!;
          final found = marker.firstMatch(text);
          if (found != null) {
            hits.add('${file.path}:${i + 1}: [${found.group(2)}] $text');
          }
        }
      }
    }

    expect(hits, isEmpty, reason: hits.join('\n'));
  });
}
