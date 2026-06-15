import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:media_organizer/media_organizer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _FakeProbe implements MediaProbe {
  _FakeProbe(this.time, {this.lat, this.lng});
  final DateTime time;
  final double? lat;
  final double? lng;
  @override
  Future<MediaMetadata> probe(String path, MediaFileSystem fs) async =>
      MediaMetadata(captureTime: time, latitude: lat, longitude: lng);
}

class _FakeGeocoder implements LocationResolver {
  @override
  Future<String?> resolve(double latitude, double longitude) async => 'Taipei';
}

void main() {
  late Directory input;
  late Directory output;
  final t = DateTime(2026, 6, 15, 9, 5, 3);

  setUp(() async {
    final root = await Directory.systemTemp.createTemp('mo_test');
    input = Directory(p.join(root.path, 'in'))..createSync();
    output = Directory(p.join(root.path, 'out'));
  });

  tearDown(() async {
    final root = input.parent;
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<File> write(String name, List<int> bytes) async {
    final f = File(p.join(input.path, name));
    await f.writeAsBytes(bytes);
    return f;
  }

  String md58(List<int> bytes) => md5.convert(bytes).toString().substring(0, 8);

  test('renames media + dedups by content, copies to output', () async {
    final a = List<int>.filled(100, 1);
    final b = List<int>.filled(200, 2);
    await write('a.jpg', a);
    await write('b.jpg', b);
    await write('dup.jpg', a); // same bytes as a → duplicate

    final report = await MediaOrganizer(
      probe: _FakeProbe(t),
    ).run(input: input.path, output: output.path);

    expect(report.organized.length, 2);
    expect(report.duplicates.length, 1);

    final names = output.listSync().map((e) => p.basename(e.path)).toList()
      ..sort();
    expect(names, [
      '20260615T090503_100_${md58(a)}.jpg',
      '20260615T090503_200_${md58(b)}.jpg',
    ]);
  });

  test('dry-run plans without writing', () async {
    await write('a.jpg', [1, 2, 3]);
    final report = await MediaOrganizer(
      probe: _FakeProbe(t),
    ).run(input: input.path, output: output.path, dryRun: true);
    expect(report.organized.length, 1);
    expect(await output.exists(), isFalse);
  });

  test('move deletes the source', () async {
    final f = await write('a.jpg', [9, 9, 9]);
    await MediaOrganizer(
      probe: _FakeProbe(t),
    ).run(input: input.path, output: output.path, move: true);
    expect(await f.exists(), isFalse);
    expect(output.listSync().length, 1);
  });

  test('ignores non-media files', () async {
    await write('notes.txt', [1]);
    await write('a.jpg', [1, 2]);
    final report = await MediaOrganizer(
      probe: _FakeProbe(t),
    ).run(input: input.path, output: output.path);
    expect(report.organized.length, 1);
    expect(report.organized.single.name.extension, 'jpg');
  });

  test('uses the location resolver when GPS is present', () async {
    await write('a.jpg', [1, 2, 3, 4]);
    final report = await MediaOrganizer(
      probe: _FakeProbe(t, lat: 25.03, lng: 121.56),
      locationResolver: _FakeGeocoder(),
    ).run(input: input.path, output: output.path);
    expect(report.organized.single.name.place, 'Taipei');
  });

  test('re-running is idempotent (output content keys are skipped)', () async {
    await write('a.jpg', [5, 5, 5, 5, 5]);
    final org = MediaOrganizer(probe: _FakeProbe(t));
    await org.run(input: input.path, output: output.path);
    final report2 = await org.run(input: input.path, output: output.path);
    expect(report2.organized, isEmpty);
    expect(report2.duplicates.length, 1);
    expect(output.listSync().length, 1);
  });
}
