// Reads a `flutter test --file-reporter json:<path>` NDJSON stream and writes
// out the scenarios that did NOT pass, so the iteration runner can re-run only
// those (see scripts/itest.sh --failed).
//
//   dart run scripts/parse_test_failures.dart <in.json> <names.txt> <regex.out>
//
// <names.txt>  human-readable, one failed test name per line (empty if none).
// <regex.out>  a single `(escaped|alternation)` regex of the failed names,
//              suitable for `flutter test --name "<regex>"`. Empty if none.
//
// Pure dart:io/convert — no Flutter, so it runs fast outside the emulator.
import 'dart:convert';
import 'dart:io';

/// Escape the RegExp metacharacters in [s] so a literal test name can be used
/// inside a `--name` alternation. (dart:core has no RegExp.escape.)
String escapeRegExp(String s) =>
    s.replaceAllMapped(RegExp(r'[.*+?^${}()|[\]\\]'), (m) => '\\${m[0]}');

void main(List<String> args) {
  if (args.length < 3) {
    stderr.writeln(
      'usage: parse_test_failures.dart <in.json> <names.txt> <regex.out>',
    );
    exit(2);
  }
  final inPath = args[0];
  final namesOut = File(args[1]);
  final regexOut = File(args[2]);

  final inFile = File(inPath);
  if (!inFile.existsSync()) {
    // No reporter output (e.g. the run crashed before tests started): treat as
    // "nothing recorded" rather than failing the parser.
    namesOut.writeAsStringSync('');
    regexOut.writeAsStringSync('');
    return;
  }

  // id -> test name, gathered from testStart events.
  final names = <int, String>{};
  // ids whose testDone reported a non-success result.
  final failedIds = <int>{};

  for (final line in inFile.readAsLinesSync()) {
    if (line.isEmpty) continue;
    Object? decoded;
    try {
      decoded = jsonDecode(line);
    } catch (_) {
      continue; // non-JSON noise (flutter sometimes prefixes the stream)
    }
    if (decoded is! Map) continue;
    switch (decoded['type']) {
      case 'testStart':
        final test = decoded['test'];
        if (test is Map && test['id'] is int) {
          final name = (test['name'] as String?) ?? '';
          // Skip the synthetic "loading <suite>.dart" bookkeeping tests.
          if (!name.startsWith('loading ')) {
            names[test['id'] as int] = name;
          }
        }
        break;
      case 'testDone':
        final id = decoded['testID'];
        final result = decoded['result'];
        final hidden = decoded['hidden'] == true;
        if (id is int && !hidden && result != 'success') {
          failedIds.add(id);
        }
        break;
    }
  }

  final failedNames = <String>[];
  for (final id in failedIds) {
    final name = names[id];
    if (name != null && name.isNotEmpty) failedNames.add(name);
  }
  failedNames.sort();

  namesOut.writeAsStringSync(
    failedNames.isEmpty ? '' : '${failedNames.join('\n')}\n',
  );
  regexOut.writeAsStringSync(
    failedNames.isEmpty
        ? ''
        : '(${failedNames.map(escapeRegExp).join('|')})',
  );

  stderr.writeln(
    failedNames.isEmpty
        ? 'parse_test_failures: 0 failed scenarios'
        : 'parse_test_failures: ${failedNames.length} failed scenario(s):\n  - ${failedNames.join('\n  - ')}',
  );
}
