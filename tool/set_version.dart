// Stamps a new version into BOTH pubspec.yaml and lib/src/version.dart so they
// never drift, then runs `dart format .`, `dart analyze`, and `dart test`.
// Run from the package root:
//
//   dart run tool/set_version.dart            # generate 1.YYYYMMDD.1HHmmss (now)
//   dart run tool/set_version.dart 1.20260615.1093000   # explicit version
//   dart run tool/set_version.dart --skip-checks        # just bump, no checks
//
// Scheme: 1.YYYYMMDD.1HHmmss — the leading `1` on the patch keeps it free of
// leading zeros (semver forbids those).
import 'dart:io';

String _pad(int v, [int w = 2]) => v.toString().padLeft(w, '0');

String generateVersion(DateTime t) {
  final date = '${_pad(t.year, 4)}${_pad(t.month)}${_pad(t.day)}';
  final time = '${_pad(t.hour)}${_pad(t.minute)}${_pad(t.second)}';
  return '1.$date.1$time';
}

/// Runs `dart <args>` inheriting stdio; exits the process if it fails.
Future<void> _dart(List<String> dartArgs) async {
  stdout.writeln('\n\$ dart ${dartArgs.join(' ')}');
  final proc = await Process.start(
    Platform.resolvedExecutable,
    dartArgs,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await proc.exitCode;
  if (code != 0) {
    stderr.writeln('✗ dart ${dartArgs.join(' ')} failed (exit $code)');
    exit(code);
  }
}

Future<void> main(List<String> args) async {
  final skipChecks = args.contains('--skip-checks');
  final positional = args.where((a) => !a.startsWith('-')).toList();
  final version = positional.isNotEmpty
      ? positional.first
      : generateVersion(DateTime.now());

  // A pub-compatible 3-number version (extra build/pre-release tags allowed).
  if (!RegExp(r'^\d+\.\d+\.\d+([-+].+)?$').hasMatch(version)) {
    stderr.writeln('Invalid version "$version" (want N.N.N).');
    exit(64);
  }

  final pubspec = File('pubspec.yaml');
  final versionFile = File('lib/src/version.dart');
  if (!pubspec.existsSync() || !versionFile.existsSync()) {
    stderr.writeln('Run from the package root (pubspec.yaml not found here).');
    exit(66);
  }

  final newPubspec = pubspec.readAsStringSync().replaceFirst(
    RegExp(r'^version:.*$', multiLine: true),
    'version: $version',
  );
  pubspec.writeAsStringSync(newPubspec);

  final newVersionFile = versionFile.readAsStringSync().replaceFirst(
    RegExp("const String mediaOrganizerVersion = '.*';"),
    "const String mediaOrganizerVersion = '$version';",
  );
  versionFile.writeAsStringSync(newVersionFile);

  // Keep the top CHANGELOG heading in step, so `pub publish` doesn't warn that
  // the changelog omits the current version. Rewrites the first `## ...` line.
  final changelog = File('CHANGELOG.md');
  if (changelog.existsSync()) {
    final text = changelog.readAsStringSync();
    final updated = text.replaceFirst(
      RegExp(r'^## .*$', multiLine: true),
      '## $version',
    );
    if (updated != text) changelog.writeAsStringSync(updated);
  }

  stdout.writeln(
    'Set version to $version '
    '(pubspec.yaml + lib/src/version.dart + CHANGELOG.md)',
  );

  if (skipChecks) return;
  await _dart(['format', '.']);
  await _dart(['analyze']);
  await _dart(['test']);
  stdout.writeln('\n✓ $version — format, analyze, and test all passed.');
}
