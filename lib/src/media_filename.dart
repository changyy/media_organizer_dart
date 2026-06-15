/// Parsed form of a normalized media filename.
class MediaName {
  const MediaName({
    required this.captureTime,
    required this.sizeBytes,
    required this.md5,
    required this.extension,
    this.place,
  });

  final DateTime captureTime;
  final String? place;
  final int sizeBytes;

  /// Short md5 (first 8 hex chars) used as the content fingerprint.
  final String md5;

  /// Lower-case extension without the dot.
  final String extension;

  /// Content key for dedup: same bytes ⇒ same `<md5>:<size>`.
  String get contentKey => '$md5:$sizeBytes';

  @override
  String toString() => MediaFilename.build(
    captureTime: captureTime,
    sizeBytes: sizeBytes,
    md5Hex: md5,
    extension: extension,
    place: place,
  );
}

/// Builds and parses self-describing media filenames:
///
///   `<YYYYMMDDTHHmmss>[_<place>]_<sizeBytes>_<md5-8>.<ext>`
///
/// e.g. `20260615T091500_taipei_1048576_9f3ab2c1.jpg`. Sorting by name sorts by
/// capture time; the trailing `<size>_<md5-8>` is a stable content key for
/// dedup; `place` is optional.
class MediaFilename {
  const MediaFilename._();

  static final RegExp _dt = RegExp(
    r'^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})$',
  );
  static final RegExp _hex8 = RegExp(r'^[0-9a-f]{8}$');

  static String build({
    required DateTime captureTime,
    required int sizeBytes,
    required String md5Hex,
    required String extension,
    String? place,
  }) {
    final t = captureTime;
    String two(int v) => v.toString().padLeft(2, '0');
    final dt =
        '${t.year.toString().padLeft(4, '0')}${two(t.month)}${two(t.day)}'
        'T${two(t.hour)}${two(t.minute)}${two(t.second)}';
    final md58 = md5Hex.length >= 8 ? md5Hex.substring(0, 8) : md5Hex;
    final ext = extension.replaceAll('.', '').toLowerCase();
    final placePart = (place != null && sanitizePlace(place).isNotEmpty)
        ? '_${sanitizePlace(place)}'
        : '';
    return '$dt${placePart}_${sizeBytes}_$md58.$ext';
  }

  /// Makes a place safe to embed: drops the separators we split on (`_`,
  /// whitespace, slashes) so parsing stays unambiguous. Keeps letters/digits
  /// (incl. non-ASCII).
  static String sanitizePlace(String place) => place
      .trim()
      .replaceAll(RegExp(r'[_\s/\\]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  /// Parses a normalized filename, or null if it doesn't match the scheme.
  static MediaName? parse(String filename) {
    final dot = filename.lastIndexOf('.');
    if (dot <= 0) return null;
    final ext = filename.substring(dot + 1).toLowerCase();
    final stem = filename.substring(0, dot);
    final parts = stem.split('_');
    if (parts.length < 3) return null;

    final md58 = parts.last;
    final sizeStr = parts[parts.length - 2];
    final dtStr = parts.first;
    if (!_hex8.hasMatch(md58)) return null;
    final size = int.tryParse(sizeStr);
    if (size == null) return null;
    final m = _dt.firstMatch(dtStr);
    if (m == null) return null;
    final captureTime = DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
      int.parse(m.group(4)!),
      int.parse(m.group(5)!),
      int.parse(m.group(6)!),
    );
    final place = parts.length > 3
        ? parts.sublist(1, parts.length - 2).join('_')
        : null;
    return MediaName(
      captureTime: captureTime,
      place: (place != null && place.isNotEmpty) ? place : null,
      sizeBytes: size,
      md5: md58,
      extension: ext,
    );
  }
}
