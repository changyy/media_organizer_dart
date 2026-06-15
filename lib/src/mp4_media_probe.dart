import 'dart:typed_data';

import 'file_system.dart';
import 'media_metadata.dart';

/// Reads capture time (and, when present, GPS) from MP4 / MOV / M4V videos by
/// parsing the ISO-BMFF box tree — no ffmpeg, no native code.
///
/// It locates the `moov` box (seeking past `mdat` rather than reading it, when
/// the [MediaFileSystem] is a [RandomAccessReader]) and reads, in order of
/// preference:
///   1. an Apple `com.apple.quicktime.creationdate` / `©day` ISO-8601 string in
///      `udta` — timezone-aware, so the most reliable;
///   2. the `mvhd` creation time (seconds since 1904-01-01 UTC).
/// GPS comes from an ISO-6709 location string (`com.apple.quicktime.location`)
/// when present.
///
/// Returns an empty [MediaMetadata] (null capture time) for non-MP4 / unparsable
/// input — compose it behind [CompositeMediaProbe] for the mtime fallback.
class Mp4MediaProbe implements MediaProbe {
  const Mp4MediaProbe({this.maxMoovBytes = 16 * 1024 * 1024});

  /// Safety cap on how much of a `moov` box to read into memory.
  final int maxMoovBytes;

  // 1904-01-01T00:00:00Z, the MP4/QuickTime epoch.
  static const int _epoch1904Offset = 2082844800; // seconds before Unix epoch

  static final RegExp _isoDate = RegExp(
    r'(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)',
  );
  // ISO-6709 e.g. "+25.0339+121.5645/" or "+25.0339+121.5645+010.000/".
  static final RegExp _iso6709 = RegExp(r'([+-]\d+\.\d+)([+-]\d+\.\d+)');

  @override
  Future<MediaMetadata> probe(String path, MediaFileSystem fs) async {
    try {
      final moov = await _readMoov(path, fs);
      if (moov == null) return const MediaMetadata();

      final text = String.fromCharCodes(moov);
      DateTime? capture;
      double? lat;
      double? lng;

      // 1. Apple timezone-aware creation date, if any.
      final idx = text.indexOf('creationdate');
      if (idx >= 0) {
        final m = _isoDate.firstMatch(text.substring(idx));
        capture = _parseIso(m?.group(1));
      }
      capture ??= _parseIso(_isoDate.firstMatch(text)?.group(1));

      // 2. Fall back to mvhd creation_time.
      capture ??= _mvhdTime(moov);

      // GPS from an ISO-6709 location string.
      final loc = text.indexOf('location');
      if (loc >= 0) {
        final m = _iso6709.firstMatch(text.substring(loc));
        if (m != null) {
          lat = double.tryParse(m.group(1)!);
          lng = double.tryParse(m.group(2)!);
        }
      }

      return MediaMetadata(captureTime: capture, latitude: lat, longitude: lng);
    } catch (_) {
      return const MediaMetadata();
    }
  }

  DateTime? _parseIso(String? raw) {
    if (raw == null) return null;
    // Normalize a colon-less timezone ("+0800" → "+08:00") for DateTime.parse.
    final fixed = raw.replaceFirstMapped(
      RegExp(r'([+-]\d{2})(\d{2})$'),
      (m) => '${m.group(1)}:${m.group(2)}',
    );
    return DateTime.tryParse(fixed)?.toLocal();
  }

  /// Walks top-level boxes and returns the `moov` payload bytes, or null.
  Future<Uint8List?> _readMoov(String path, MediaFileSystem fs) async {
    final total = await fs.length(path);
    final random = fs is RandomAccessReader ? fs as RandomAccessReader : null;
    Uint8List? whole; // used when no random access
    if (random == null) whole = await fs.readAsBytes(path);

    Future<Uint8List> read(int start, int length) async {
      if (random != null) return random.readRange(path, start, length);
      final end = (start + length).clamp(0, whole!.length);
      return Uint8List.sublistView(whole, start, end);
    }

    var offset = 0;
    while (offset + 8 <= total) {
      final header = await read(offset, 16);
      if (header.length < 8) break;
      final bd = ByteData.sublistView(header);
      var size = bd.getUint32(0);
      final type = String.fromCharCodes(header.sublist(4, 8));
      var headerSize = 8;
      if (size == 1) {
        if (header.length < 16) break;
        size = bd.getUint64(8); // 64-bit largesize
        headerSize = 16;
      } else if (size == 0) {
        size = total - offset; // extends to EOF
      }
      if (size < headerSize) break; // malformed

      if (type == 'moov') {
        final payloadLen = (size - headerSize).clamp(0, maxMoovBytes);
        return read(offset + headerSize, payloadLen);
      }
      offset += size;
    }
    return null;
  }

  /// Reads `mvhd` creation_time from a `moov` payload, as local time.
  DateTime? _mvhdTime(Uint8List moov) {
    final bd = ByteData.sublistView(moov);
    var offset = 0;
    while (offset + 8 <= moov.length) {
      final size = bd.getUint32(offset);
      final type = String.fromCharCodes(moov.sublist(offset + 4, offset + 8));
      if (size < 8) break;
      if (type == 'mvhd') {
        final p = offset + 8; // box payload
        if (p >= moov.length) return null;
        final version = moov[p];
        int seconds;
        if (version == 1) {
          if (p + 12 > moov.length) return null;
          seconds = bd.getUint64(p + 4);
        } else {
          if (p + 8 > moov.length) return null;
          seconds = bd.getUint32(p + 4);
        }
        if (seconds == 0) return null;
        final unix = seconds - _epoch1904Offset;
        return DateTime.fromMillisecondsSinceEpoch(
          unix * 1000,
          isUtc: true,
        ).toLocal();
      }
      offset += size;
    }
    return null;
  }
}
