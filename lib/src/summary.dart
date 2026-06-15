import 'package:path/path.dart' as p;

import 'file_system.dart';
import 'media_filename.dart';
import 'media_organizer_base.dart';

/// Photo + video counts for one month.
class MonthBucket {
  const MonthBucket(this.photos, this.videos);
  final int photos;
  final int videos;
  int get total => photos + videos;
  MonthBucket _add(MediaKind kind) => MonthBucket(
    photos + (kind == MediaKind.photo ? 1 : 0),
    videos + (kind == MediaKind.video ? 1 : 0),
  );
}

/// A by-month summary of normalized media files.
class LibrarySummary {
  LibrarySummary(this.byMonth, this.photos, this.videos);

  /// `YYYY.MM` → counts, in ascending month order.
  final Map<String, MonthBucket> byMonth;
  final int photos;
  final int videos;
  int get total => photos + videos;

  @override
  String toString() {
    final b = StringBuffer('Total: $total ($photos photos, $videos videos)\n');
    for (final e in byMonth.entries) {
      b.writeln(
        '  ${e.key}  ${e.value.photos.toString().padLeft(4)} photos'
        '  ${e.value.videos.toString().padLeft(4)} videos',
      );
    }
    return b.toString().trimRight();
  }
}

/// Summarizes a list of NORMALIZED filenames by month (ignores names that don't
/// match the scheme). Pure — no IO — so it's easy to test.
LibrarySummary summarizeNames(Iterable<String> filenames) {
  final months = <String, MonthBucket>{};
  var photos = 0;
  var videos = 0;
  for (final filename in filenames) {
    final name = MediaFilename.parse(p.basename(filename));
    if (name == null) continue;
    final kind = mediaKindForExtension(name.extension);
    if (kind == MediaKind.other) continue;
    if (kind == MediaKind.photo) {
      photos++;
    } else {
      videos++;
    }
    final t = name.captureTime;
    final key = '${t.year}.${t.month.toString().padLeft(2, '0')}';
    months[key] = (months[key] ?? const MonthBucket(0, 0))._add(kind);
  }
  final sorted = <String, MonthBucket>{
    for (final k in months.keys.toList()..sort()) k: months[k]!,
  };
  return LibrarySummary(sorted, photos, videos);
}

/// Summarizes a folder of normalized media files by month.
Future<LibrarySummary> summarizeFolder(
  String dir, {
  bool recursive = true,
  MediaFileSystem fileSystem = const LocalFileSystem(),
}) async {
  final files = await fileSystem.listFiles(dir, recursive: recursive);
  return summarizeNames(files.map(p.basename));
}
