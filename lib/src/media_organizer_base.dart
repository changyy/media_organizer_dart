import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'file_system.dart';
import 'media_filename.dart';
import 'media_metadata.dart';
import 'mp4_media_probe.dart';

/// Image extensions recognized by default.
const Set<String> kImageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'heic',
  'heif',
  'gif',
  'webp',
  'tiff',
  'tif',
  'bmp',
  'dng',
};

/// Video extensions recognized by default.
const Set<String> kVideoExtensions = {
  'mp4',
  'mov',
  'm4v',
  'avi',
  'mkv',
  'webm',
  '3gp',
  'hevc',
};

/// Media file extensions the organizer picks up by default (images + videos).
const Set<String> kDefaultMediaExtensions = {
  ...kImageExtensions,
  ...kVideoExtensions,
};

/// Whether an extension is a photo, video, or neither.
enum MediaKind { photo, video, other }

MediaKind mediaKindForExtension(String ext) {
  final e = ext.replaceAll('.', '').toLowerCase();
  if (kImageExtensions.contains(e)) return MediaKind.photo;
  if (kVideoExtensions.contains(e)) return MediaKind.video;
  return MediaKind.other;
}

/// Default [MediaProbe]: routes by media kind — image EXIF for photos, MP4
/// `moov` parsing for videos — then falls back to the file's modified time when
/// neither yields a capture date. This is what [MediaOrganizer] uses by default.
class CompositeMediaProbe implements MediaProbe {
  const CompositeMediaProbe({
    this.imageProbe = const ExifMediaProbe(mtimeFallback: false),
    this.videoProbe = const Mp4MediaProbe(),
    this.mtimeFallback = true,
  });

  final MediaProbe imageProbe;
  final MediaProbe videoProbe;
  final bool mtimeFallback;

  @override
  Future<MediaMetadata> probe(String path, MediaFileSystem fs) async {
    final ext = p.extension(path).replaceAll('.', '').toLowerCase();
    final kind = mediaKindForExtension(ext);
    final m = kind == MediaKind.video
        ? await videoProbe.probe(path, fs)
        : await imageProbe.probe(path, fs);
    if (m.captureTime == null && mtimeFallback) {
      return MediaMetadata(
        captureTime: await fs.lastModified(path),
        latitude: m.latitude,
        longitude: m.longitude,
      );
    }
    return m;
  }
}

/// Progress for one file during an organize run (1-based [index] of [total]).
class OrganizeProgress {
  const OrganizeProgress({
    required this.index,
    required this.total,
    required this.path,
  });
  final int index;
  final int total;
  final String path;
}

/// One successfully-organized file.
class OrganizedItem {
  const OrganizedItem({
    required this.source,
    required this.target,
    required this.name,
  });
  final String source;
  final String target;
  final MediaName name;
}

/// Result of an organize run.
class OrganizeReport {
  final List<OrganizedItem> organized = [];
  final List<String> duplicates = []; // source paths skipped as duplicates
  final List<(String path, String error)> failed = [];

  int get total => organized.length + duplicates.length + failed.length;

  @override
  String toString() =>
      'OrganizeReport(organized=${organized.length}, '
      'duplicates=${duplicates.length}, failed=${failed.length})';
}

/// Scans a folder of photos/videos and normalizes each into
/// `<datetime>[_<place>]_<size>_<md5-8>.<ext>` in the output folder, skipping
/// content-duplicates. Probe, location resolver and transcoder are injectable;
/// the defaults keep it pure and cross-platform (no transcode, no geocoding).
class MediaOrganizer {
  MediaOrganizer({
    MediaProbe? probe,
    this.locationResolver,
    MediaTranscoder? transcoder,
    MediaFileSystem? fileSystem,
    Set<String>? mediaExtensions,
  }) : probe = probe ?? const CompositeMediaProbe(),
       transcoder = transcoder ?? const PassthroughTranscoder(),
       fs = fileSystem ?? const LocalFileSystem(),
       mediaExtensions = mediaExtensions ?? kDefaultMediaExtensions;

  final MediaProbe probe;
  final LocationResolver? locationResolver;
  final MediaTranscoder transcoder;
  final MediaFileSystem fs;
  final Set<String> mediaExtensions;

  /// Organizes [input] into [output].
  ///
  /// [move] deletes the source after a verified copy. [verify] (forced on when
  /// [move] is set) re-hashes the written file and aborts that item if it
  /// doesn't match — so a corrupt copy never causes an original to be deleted.
  /// [onProgress] is called once per file (before it's processed); [cancelled],
  /// if it returns true, stops the run cleanly and returns what's done so far.
  Future<OrganizeReport> run({
    required String input,
    required String output,
    bool recursive = true,
    bool move = false,
    bool dryRun = false,
    bool verify = false,
    void Function(OrganizeProgress)? onProgress,
    bool Function()? cancelled,
  }) async {
    final report = OrganizeReport();
    final seen = <String>{};
    final mustVerify = verify || move;

    // Seed dedup with content keys already present in the output folder, so
    // re-running is idempotent and cross-run duplicates are skipped.
    if (await fs.exists(output)) {
      for (final path in await fs.listFiles(output, recursive: false)) {
        final n = MediaFilename.parse(p.basename(path));
        if (n != null) seen.add(n.contentKey);
      }
    }

    final files =
        (await fs.listFiles(
            input,
            recursive: recursive,
          )).where((path) => mediaExtensions.contains(_ext(path))).toList()
          ..sort(); // deterministic order

    for (var i = 0; i < files.length; i++) {
      if (cancelled?.call() ?? false) break;
      final path = files[i];
      onProgress?.call(
        OrganizeProgress(index: i + 1, total: files.length, path: path),
      );
      try {
        final size = await fs.length(path);
        final digest = await md5.bind(fs.openRead(path)).first;
        final md5Hex = digest.toString();
        final key = '${md5Hex.substring(0, 8)}:$size';
        if (seen.contains(key)) {
          report.duplicates.add(path);
          continue;
        }

        final meta = await probe.probe(path, fs);
        final captureTime =
            meta.captureTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        String? place;
        if (locationResolver != null && meta.hasLocation) {
          place = await locationResolver!.resolve(
            meta.latitude!,
            meta.longitude!,
          );
        }
        final name = MediaFilename.build(
          captureTime: captureTime,
          sizeBytes: size,
          md5Hex: md5Hex,
          extension: _ext(path),
          place: place,
        );
        final targetPath = p.join(output, name);

        if (!dryRun) {
          await fs.ensureDir(output);
          if (await fs.exists(targetPath)) {
            seen.add(key);
            report.duplicates.add(path);
            continue;
          }
          final produced = await transcoder.transcode(path, fs);
          await fs.copy(produced, targetPath);

          // Verify the written copy before we trust it (and before deleting any
          // source on move). Compare the produced bytes' hash to the target's —
          // for a transcode the produced temp differs from the original, so we
          // hash what was actually meant to be written.
          if (mustVerify) {
            final want = produced == path
                ? md5Hex
                : (await md5.bind(fs.openRead(produced)).first).toString();
            final got = (await md5.bind(fs.openRead(targetPath)).first)
                .toString();
            if (want != got) {
              await fs.delete(targetPath); // remove the bad copy
              if (produced != path) await fs.delete(produced);
              throw Exception('copy verification failed: checksum mismatch');
            }
          }

          // A transcoder that produced a new temp file → always clean it up.
          if (produced != path) await fs.delete(produced);
          if (move) await fs.delete(path);
        }

        seen.add(key);
        report.organized.add(
          OrganizedItem(
            source: path,
            target: targetPath,
            name: MediaFilename.parse(name)!,
          ),
        );
      } catch (e) {
        report.failed.add((path, e.toString()));
      }
    }
    return report;
  }

  String _ext(String path) =>
      p.extension(path).replaceAll('.', '').toLowerCase();
}
