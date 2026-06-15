import 'dart:io';
import 'dart:typed_data';

/// The filesystem operations the organizer needs, abstracted so callers can
/// inject their own backend (the default [LocalFileSystem] uses `dart:io`; a
/// test or an alternate source — in-memory, cloud — can implement this without
/// pulling in `dart:io`). Paths are plain strings; use `package:path` to
/// manipulate them.
abstract class MediaFileSystem {
  /// All file paths under [dir] (files only). Empty if [dir] is absent.
  Future<List<String>> listFiles(String dir, {bool recursive = true});

  /// True if a file or directory exists at [path].
  Future<bool> exists(String path);

  Future<int> length(String path);

  /// Last-modified time, or null if unavailable.
  Future<DateTime?> lastModified(String path);

  /// Streamed read (used to hash without loading the whole file).
  Stream<List<int>> openRead(String path);

  Future<Uint8List> readAsBytes(String path);

  /// Ensures the directory at [path] exists (creating parents).
  Future<void> ensureDir(String path);

  Future<void> copy(String from, String to);

  Future<void> delete(String path);
}

/// Optional capability: read an arbitrary byte range without pulling the whole
/// file. A [MediaFileSystem] that also implements this lets probes (e.g. the MP4
/// `moov` reader) seek directly to a box instead of streaming past gigabytes of
/// media data. Callers should feature-detect with `fs is RandomAccessReader` and
/// fall back to [MediaFileSystem.readAsBytes] otherwise.
abstract class RandomAccessReader {
  /// Bytes `[start, start+length)`; the result may be shorter near EOF.
  Future<Uint8List> readRange(String path, int start, int length);
}

/// Default [MediaFileSystem] backed by `dart:io` — works on desktop and mobile.
class LocalFileSystem implements MediaFileSystem, RandomAccessReader {
  const LocalFileSystem();

  @override
  Future<Uint8List> readRange(String path, int start, int length) async {
    final raf = await File(path).open();
    try {
      await raf.setPosition(start);
      return await raf.read(length);
    } finally {
      await raf.close();
    }
  }

  @override
  Future<List<String>> listFiles(String dir, {bool recursive = true}) async {
    final d = Directory(dir);
    if (!await d.exists()) return const [];
    final out = <String>[];
    await for (final e in d.list(recursive: recursive, followLinks: false)) {
      if (e is File) out.add(e.path);
    }
    return out;
  }

  @override
  Future<bool> exists(String path) async =>
      await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound;

  @override
  Future<int> length(String path) => File(path).length();

  @override
  Future<DateTime?> lastModified(String path) async {
    try {
      return (await File(path).stat()).modified;
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<List<int>> openRead(String path) => File(path).openRead();

  @override
  Future<Uint8List> readAsBytes(String path) => File(path).readAsBytes();

  @override
  Future<void> ensureDir(String path) async {
    await Directory(path).create(recursive: true);
  }

  @override
  Future<void> copy(String from, String to) async {
    await File(from).copy(to);
  }

  @override
  Future<void> delete(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}
