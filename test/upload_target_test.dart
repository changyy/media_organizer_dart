import 'dart:typed_data';

import 'package:media_organizer/media_organizer.dart';
import 'package:test/test.dart';

/// An in-memory [UploadTarget] — the skeleton a real Google Drive / S3 / SFTP
/// target follows: enumerate existing content keys, then store bytes by name.
/// No cloud SDK, fully testable.
class FakeUploadTarget implements UploadTarget {
  FakeUploadTarget({Set<String>? alreadyThere}) : _present = {...?alreadyThere};

  final Set<String> _present;
  final Map<String, Uint8List> stored = {}; // name -> bytes
  int uploadCalls = 0;

  @override
  Future<Set<String>> existingContentKeys() async => {..._present};

  @override
  Future<void> upload({
    required String localPath,
    required String name,
    required String contentKey,
    required MediaFileSystem fs,
  }) async {
    uploadCalls++;
    stored[name] = await fs.readAsBytes(localPath);
    _present.add(contentKey);
  }
}

/// Minimal in-memory FS holding the "organized" output files.
class _MemFs implements MediaFileSystem {
  final Map<String, Uint8List> files = {};
  @override
  Future<Uint8List> readAsBytes(String path) async => files[path]!;
  @override
  Future<int> length(String path) async => files[path]!.length;
  @override
  Stream<List<int>> openRead(String path) => Stream.value(files[path]!);
  @override
  Future<bool> exists(String path) async => files.containsKey(path);
  @override
  Future<DateTime?> lastModified(String path) async => null;
  @override
  Future<List<String>> listFiles(String dir, {bool recursive = true}) async =>
      files.keys.toList();
  @override
  Future<void> ensureDir(String path) async {}
  @override
  Future<void> copy(String from, String to) async => files[to] = files[from]!;
  @override
  Future<void> delete(String path) async => files.remove(path);
}

OrganizedItem _item(_MemFs fs, String name, List<int> bytes) {
  final path = '/out/$name';
  fs.files[path] = Uint8List.fromList(bytes);
  return OrganizedItem(
    source: '/in/$name',
    target: path,
    name: MediaFilename.parse(name)!,
  );
}

void main() {
  test('uploads organized files and reads bytes through the FS', () async {
    final fs = _MemFs();
    final items = [
      _item(fs, '20260615T090503_100_aaaaaaaa.jpg', [1, 2, 3]),
      _item(fs, '20260615T090504_200_bbbbbbbb.mp4', [4, 5, 6, 7]),
    ];
    final target = FakeUploadTarget();

    final report = await MediaUploader(
      target: target,
      fileSystem: fs,
    ).run(items);

    expect(report.uploaded.length, 2);
    expect(report.skipped, isEmpty);
    expect(target.stored.length, 2);
    expect(target.stored['20260615T090503_100_aaaaaaaa.jpg'], [1, 2, 3]);
  });

  test(
    'skips content keys already present at the target (idempotent)',
    () async {
      final fs = _MemFs();
      final items = [
        _item(fs, '20260615T090503_100_aaaaaaaa.jpg', [1, 2, 3]),
      ];
      // contentKey is "<md5-8>:<size>" → "aaaaaaaa:100".
      final target = FakeUploadTarget(alreadyThere: {'aaaaaaaa:100'});

      final report = await MediaUploader(
        target: target,
        fileSystem: fs,
      ).run(items);

      expect(report.skipped.length, 1);
      expect(report.uploaded, isEmpty);
      expect(target.uploadCalls, 0);
    },
  );

  test('same content key within one run uploads only once', () async {
    final fs = _MemFs();
    final items = [
      _item(fs, '20260615T090503_100_aaaaaaaa.jpg', [1, 2, 3]),
      // Different capture time / name, identical content key.
      _item(fs, '20260101T000000_100_aaaaaaaa.jpg', [1, 2, 3]),
    ];
    final target = FakeUploadTarget();

    final report = await MediaUploader(
      target: target,
      fileSystem: fs,
    ).run(items);

    expect(report.uploaded.length, 1);
    expect(report.skipped.length, 1);
    expect(target.uploadCalls, 1);
  });

  test('a failing upload is recorded, the rest continue', () async {
    final fs = _MemFs();
    final items = [
      _item(fs, '20260615T090503_100_aaaaaaaa.jpg', [1, 2, 3]),
      _item(fs, '20260615T090504_200_bbbbbbbb.mp4', [4, 5, 6, 7]),
    ];
    final target = _FlakyTarget(failOn: '20260615T090503_100_aaaaaaaa.jpg');

    final report = await MediaUploader(
      target: target,
      fileSystem: fs,
    ).run(items);

    expect(report.failed.length, 1);
    expect(report.uploaded.length, 1);
  });
}

class _FlakyTarget implements UploadTarget {
  _FlakyTarget({required this.failOn});
  final String failOn;
  @override
  Future<Set<String>> existingContentKeys() async => {};
  @override
  Future<void> upload({
    required String localPath,
    required String name,
    required String contentKey,
    required MediaFileSystem fs,
  }) async {
    if (name == failOn) throw Exception('boom');
  }
}
