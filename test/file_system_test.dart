import 'dart:typed_data';

import 'package:media_organizer/media_organizer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Proves the engine is IO-agnostic: a pure in-memory [MediaFileSystem] (no
/// `dart:io`) drives a full organize run. This is exactly how a caller would
/// inject their own backend (cloud source, tests, etc.).
class InMemoryFileSystem implements MediaFileSystem {
  final Map<String, Uint8List> files = {};
  final Map<String, DateTime> mtimes = {};

  @override
  Future<List<String>> listFiles(String dir, {bool recursive = true}) async {
    final prefix = dir.endsWith('/') ? dir : '$dir/';
    return files.keys.where((k) {
      if (!k.startsWith(prefix)) return false;
      final rest = k.substring(prefix.length);
      return recursive || !rest.contains('/');
    }).toList();
  }

  @override
  Future<bool> exists(String path) async =>
      files.containsKey(path) || files.keys.any((k) => k.startsWith('$path/'));

  @override
  Future<int> length(String path) async => files[path]!.length;

  @override
  Future<DateTime?> lastModified(String path) async => mtimes[path];

  @override
  Stream<List<int>> openRead(String path) => Stream.value(files[path]!);

  @override
  Future<Uint8List> readAsBytes(String path) async => files[path]!;

  @override
  Future<void> ensureDir(String path) async {}

  @override
  Future<void> copy(String from, String to) async {
    files[to] = files[from]!;
  }

  @override
  Future<void> delete(String path) async => files.remove(path);
}

class _FixedProbe implements MediaProbe {
  _FixedProbe(this.time);
  final DateTime time;
  @override
  Future<MediaMetadata> probe(String path, MediaFileSystem fs) async =>
      MediaMetadata(captureTime: time);
}

void main() {
  test('organizes entirely in memory (IO fully injected)', () async {
    final fs = InMemoryFileSystem();
    fs.files['/in/a.jpg'] = Uint8List.fromList([1, 2, 3]);
    fs.files['/in/dup.jpg'] = Uint8List.fromList([1, 2, 3]); // duplicate
    fs.files['/in/b.mp4'] = Uint8List.fromList([9, 9, 9, 9]);

    final report = await MediaOrganizer(
      fileSystem: fs,
      probe: _FixedProbe(DateTime(2026, 6, 15, 9, 5, 3)),
    ).run(input: '/in', output: '/out');

    expect(report.organized.length, 2);
    expect(report.duplicates.length, 1);
    // Output files now live in the in-memory FS — no dart:io involved.
    final outNames =
        fs.files.keys
            .where((k) => k.startsWith('/out/'))
            .map(p.basename)
            .toList()
          ..sort();
    expect(outNames.length, 2);
    expect(outNames.every((n) => MediaFilename.parse(n) != null), isTrue);
  });
}
