import 'dart:io';
import 'dart:typed_data';

import 'package:media_organizer/media_organizer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Builds an ISO-BMFF box: `[size:4][type:4][payload]`.
Uint8List _box(String type, List<int> payload) {
  final size = 8 + payload.length;
  final b = BytesBuilder();
  final sz = ByteData(4)..setUint32(0, size);
  b.add(sz.buffer.asUint8List());
  b.add(type.codeUnits);
  b.add(payload);
  return b.takeBytes();
}

/// Minimal version-0 `mvhd` payload carrying [creationUnix] (seconds, Unix).
Uint8List _mvhd(int creationUnix) {
  const epoch1904 = 2082844800;
  final b = BytesBuilder();
  b.add([0, 0, 0, 0]); // version 0 + flags
  final ct = ByteData(4)..setUint32(0, creationUnix + epoch1904);
  b.add(ct.buffer.asUint8List());
  b.add(List.filled(12, 0)); // modification_time, timescale, duration
  return b.takeBytes();
}

Future<String> _writeMp4(
  Directory dir,
  String name,
  Uint8List moovPayload, {
  int mdatBytes = 200,
}) async {
  final b = BytesBuilder();
  b.add(_box('ftyp', 'isom'.codeUnits));
  b.add(
    _box('mdat', List.filled(mdatBytes, 0xAA)),
  ); // must be skipped, not read
  b.add(_box('moov', moovPayload));
  final path = p.join(dir.path, name);
  await File(path).writeAsBytes(b.takeBytes());
  return path;
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('mp4probe'));
  tearDown(() async => dir.delete(recursive: true));

  test('reads mvhd creation_time (1904 epoch) past mdat', () async {
    final want = DateTime.utc(2026, 6, 15, 9, 5, 3);
    final unix = want.millisecondsSinceEpoch ~/ 1000;
    final path = await _writeMp4(dir, 'a.mp4', _mvhdBox(unix));

    final meta = await const Mp4MediaProbe().probe(
      path,
      const LocalFileSystem(),
    );
    expect(meta.captureTime, want.toLocal());
    expect(meta.hasLocation, isFalse);
  });

  test('prefers the Apple creationdate and reads ISO-6709 location', () async {
    final mvhdTime = DateTime.utc(2000, 1, 1).millisecondsSinceEpoch ~/ 1000;
    final udta = <int>[
      ...'com.apple.quicktime.creationdate'.codeUnits,
      ...' 2026-06-15T09:05:03+08:00 '.codeUnits,
      ...'com.apple.quicktime.location.ISO6709'.codeUnits,
      ...' +25.0339+121.5645/'.codeUnits,
    ];
    final moov = BytesBuilder()
      ..add(_mvhdBox(mvhdTime))
      ..add(_box('udta', udta));
    final path = await _writeMp4(dir, 'b.mp4', moov.takeBytes());

    final meta = await const Mp4MediaProbe().probe(
      path,
      const LocalFileSystem(),
    );
    // 09:05:03+08:00 == 01:05:03 UTC, regardless of the test machine's zone.
    expect(meta.captureTime!.toUtc(), DateTime.utc(2026, 6, 15, 1, 5, 3));
    expect(meta.latitude, closeTo(25.0339, 1e-6));
    expect(meta.longitude, closeTo(121.5645, 1e-6));
  });

  test('returns empty metadata for a non-MP4 blob', () async {
    final path = p.join(dir.path, 'notvideo.mp4');
    await File(path).writeAsBytes(Uint8List.fromList([1, 2, 3, 4, 5]));
    final meta = await const Mp4MediaProbe().probe(
      path,
      const LocalFileSystem(),
    );
    expect(meta.captureTime, isNull);
  });
}

Uint8List _mvhdBox(int unix) => _box('mvhd', _mvhd(unix));
