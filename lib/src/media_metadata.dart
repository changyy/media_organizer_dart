import 'package:exif/exif.dart';

import 'file_system.dart';

/// Capture metadata extracted from a media file.
class MediaMetadata {
  const MediaMetadata({this.captureTime, this.latitude, this.longitude});
  final DateTime? captureTime;
  final double? latitude;
  final double? longitude;

  bool get hasLocation => latitude != null && longitude != null;
}

/// Extracts capture time + GPS from a media file. Inject your own (e.g. one that
/// reads video `moov` metadata) — the default reads image EXIF. Reads through
/// the [MediaFileSystem] so it stays IO-agnostic.
abstract class MediaProbe {
  Future<MediaMetadata> probe(String path, MediaFileSystem fs);
}

/// Turns GPS coordinates into a place label for the filename. Default: none
/// (no network calls). Provide one backed by a geocoder if you want places.
abstract class LocationResolver {
  Future<String?> resolve(double latitude, double longitude);
}

/// Optional transcode step before output (e.g. ffmpeg on desktop, native on
/// mobile). Returns the path to read the output bytes from — possibly a new
/// transcoded file, or [inputPath] unchanged. The default
/// [PassthroughTranscoder] returns the input, keeping the core platform-free.
abstract class MediaTranscoder {
  Future<String> transcode(String inputPath, MediaFileSystem fs);
}

class PassthroughTranscoder implements MediaTranscoder {
  const PassthroughTranscoder();
  @override
  Future<String> transcode(String inputPath, MediaFileSystem fs) async =>
      inputPath;
}

/// Image EXIF probe: capture time + GPS. When [mtimeFallback] is true (default)
/// and EXIF has no date, it falls back to the file's last-modified time.
class ExifMediaProbe implements MediaProbe {
  const ExifMediaProbe({this.mtimeFallback = true});

  /// Use the file's modified time when EXIF carries no capture date.
  final bool mtimeFallback;

  @override
  Future<MediaMetadata> probe(String path, MediaFileSystem fs) async {
    DateTime? captureTime;
    double? lat;
    double? lng;
    try {
      final tags = await readExifFromBytes(await fs.readAsBytes(path));
      captureTime = _exifDate(tags);
      final gps = _exifGps(tags);
      lat = gps?.$1;
      lng = gps?.$2;
    } catch (_) {
      // Not an image / unreadable EXIF — fall through to mtime.
    }
    if (captureTime == null && mtimeFallback) {
      captureTime = await fs.lastModified(path);
    }
    return MediaMetadata(
      captureTime: captureTime,
      latitude: lat,
      longitude: lng,
    );
  }

  DateTime? _exifDate(Map<String, IfdTag> tags) {
    final raw =
        tags['EXIF DateTimeOriginal']?.printable ??
        tags['Image DateTime']?.printable;
    if (raw == null) return null;
    // EXIF format: "YYYY:MM:DD HH:MM:SS"
    final m = RegExp(
      r'^(\d{4}):(\d{2}):(\d{2})\s+(\d{2}):(\d{2}):(\d{2})',
    ).firstMatch(raw.trim());
    if (m == null) return null;
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    );
  }

  (double, double)? _exifGps(Map<String, IfdTag> tags) {
    final lat = _dms(tags['GPS GPSLatitude'], tags['GPS GPSLatitudeRef']);
    final lng = _dms(tags['GPS GPSLongitude'], tags['GPS GPSLongitudeRef']);
    if (lat == null || lng == null) return null;
    return (lat, lng);
  }

  double? _dms(IfdTag? value, IfdTag? ref) {
    if (value == null) return null;
    final vals = value.values.toList();
    if (vals.length < 3) return null;
    double ratio(dynamic r) {
      if (r is Ratio) {
        return r.denominator == 0 ? 0 : r.numerator / r.denominator;
      }
      return (r as num).toDouble();
    }

    final deg = ratio(vals[0]) + ratio(vals[1]) / 60 + ratio(vals[2]) / 3600;
    final r = ref?.printable.trim().toUpperCase() ?? '';
    return (r == 'S' || r == 'W') ? -deg : deg;
  }
}
