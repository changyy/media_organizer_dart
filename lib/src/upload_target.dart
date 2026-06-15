import 'package:path/path.dart' as p;

import 'file_system.dart';
import 'media_organizer_base.dart';

/// A destination that organized files can be pushed to — Google Drive, S3, an
/// SFTP server, etc. (A NAS needs no implementation: mount it and organize
/// straight into the mount with `output: /mnt/nas/Photos`.)
///
/// Kept deliberately tiny and dependency-free so the core package never pulls in
/// a cloud SDK: implement this in your app or a side package. Bytes are read
/// through a [MediaFileSystem], so an implementation stays IO-agnostic and is
/// easy to fake in tests.
abstract class UploadTarget {
  /// Content keys ([MediaName.contentKey], i.e. `<md5-8>:<size>`) already
  /// present at the destination, so re-runs skip re-uploading them. Return an
  /// empty set if the target can't enumerate — then nothing is pre-skipped.
  ///
  /// The same content key powers local dedup *and* remote dedup: identical bytes
  /// ⇒ identical key, no extra bookkeeping.
  Future<Set<String>> existingContentKeys();

  /// Uploads one file, stored under [name] (the normalized filename). Read the
  /// bytes from [localPath] via [fs]. Throw to mark this file failed; the run
  /// continues with the rest.
  Future<void> upload({
    required String localPath,
    required String name,
    required String contentKey,
    required MediaFileSystem fs,
  });
}

/// Outcome of an upload run.
class UploadReport {
  final List<String> uploaded = []; // names pushed this run
  final List<String> skipped = []; // names already present at the target
  final List<(String name, String error)> failed = [];

  int get total => uploaded.length + skipped.length + failed.length;

  @override
  String toString() =>
      'UploadReport(uploaded=${uploaded.length}, '
      'skipped=${skipped.length}, failed=${failed.length})';
}

/// Drives an [UploadTarget] over the result of a [MediaOrganizer] run: pushes
/// each organized file, skipping any whose content key already exists remotely.
/// Idempotent — re-running uploads only what's new.
class MediaUploader {
  MediaUploader({required this.target, MediaFileSystem? fileSystem})
    : fs = fileSystem ?? const LocalFileSystem();

  final UploadTarget target;
  final MediaFileSystem fs;

  /// Uploads each item in [items] (typically `report.organized`).
  Future<UploadReport> run(Iterable<OrganizedItem> items) async {
    final report = UploadReport();
    // Snapshot remote keys once; grow it as we go so duplicates within this run
    // (same bytes, different source) upload only once.
    final present = await target.existingContentKeys();

    for (final item in items) {
      final name = p.basename(item.target);
      final key = item.name.contentKey;
      if (present.contains(key)) {
        report.skipped.add(name);
        continue;
      }
      try {
        await target.upload(
          localPath: item.target,
          name: name,
          contentKey: key,
          fs: fs,
        );
        present.add(key);
        report.uploaded.add(name);
      } catch (e) {
        report.failed.add((name, e.toString()));
      }
    }
    return report;
  }
}
