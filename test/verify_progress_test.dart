import 'dart:typed_data';

import 'package:media_organizer/media_organizer.dart';
import 'package:test/test.dart';

/// In-memory FS; [corruptCopies] makes [copy] write wrong bytes so verify trips.
class _MemFs implements MediaFileSystem {
  _MemFs({this.corruptCopies = false});
  final bool corruptCopies;
  final Map<String, Uint8List> files = {};

  @override
  Future<List<String>> listFiles(String dir, {bool recursive = true}) async {
    final prefix = dir.endsWith('/') ? dir : '$dir/';
    return files.keys.where((k) => k.startsWith(prefix)).toList();
  }

  @override
  Future<bool> exists(String path) async =>
      files.containsKey(path) || files.keys.any((k) => k.startsWith('$path/'));
  @override
  Future<int> length(String path) async => files[path]!.length;
  @override
  Future<DateTime?> lastModified(String path) async => DateTime(2026, 1, 1);
  @override
  Stream<List<int>> openRead(String path) => Stream.value(files[path]!);
  @override
  Future<Uint8List> readAsBytes(String path) async => files[path]!;
  @override
  Future<void> ensureDir(String path) async {}
  @override
  Future<void> copy(String from, String to) async {
    final bytes = files[from]!;
    files[to] = corruptCopies
        ? Uint8List.fromList([...bytes, 0xFF]) // flip the content
        : bytes;
  }

  @override
  Future<void> delete(String path) async => files.remove(path);
}

class _FixedProbe implements MediaProbe {
  @override
  Future<MediaMetadata> probe(String path, MediaFileSystem fs) async =>
      MediaMetadata(captureTime: DateTime(2026, 6, 15, 9));
}

void main() {
  test(
    'verify aborts the item and preserves the source on a bad copy',
    () async {
      final fs = _MemFs(corruptCopies: true);
      fs.files['/in/a.jpg'] = Uint8List.fromList([1, 2, 3]);

      final report = await MediaOrganizer(
        fileSystem: fs,
        probe: _FixedProbe(),
      ).run(input: '/in', output: '/out', move: true); // move ⇒ verify on

      expect(report.organized, isEmpty);
      expect(report.failed.length, 1);
      expect(report.failed.single.$2, contains('verification failed'));
      expect(fs.files.containsKey('/in/a.jpg'), isTrue); // source NOT deleted
    },
  );

  test('verify passes on a clean copy', () async {
    final fs = _MemFs();
    fs.files['/in/a.jpg'] = Uint8List.fromList([1, 2, 3]);
    final report = await MediaOrganizer(
      fileSystem: fs,
      probe: _FixedProbe(),
    ).run(input: '/in', output: '/out', verify: true);
    expect(report.organized.length, 1);
    expect(report.failed, isEmpty);
  });

  test('onProgress fires per file; cancelled() stops the run early', () async {
    final fs = _MemFs();
    fs.files['/in/a.jpg'] = Uint8List.fromList([1]);
    fs.files['/in/b.jpg'] = Uint8List.fromList([2]);
    fs.files['/in/c.jpg'] = Uint8List.fromList([3]);

    final seen = <int>[];
    final report = await MediaOrganizer(fileSystem: fs, probe: _FixedProbe())
        .run(
          input: '/in',
          output: '/out',
          onProgress: (pr) {
            seen.add(pr.index);
            expect(pr.total, 3);
          },
          cancelled: () => seen.isNotEmpty, // stop after the first file
        );

    expect(seen, [1]);
    expect(report.organized.length, 1);
  });
}
