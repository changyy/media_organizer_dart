import 'package:media_organizer/media_organizer.dart';
import 'package:test/test.dart';

void main() {
  final t = DateTime(2026, 6, 15, 9, 5, 3);

  test('build → parse round-trips', () {
    final name = MediaFilename.build(
      captureTime: t,
      sizeBytes: 1048576,
      md5Hex: '9f3ab2c1deadbeef',
      extension: 'JPG',
      place: 'Taipei',
    );
    expect(name, '20260615T090503_Taipei_1048576_9f3ab2c1.jpg');

    final parsed = MediaFilename.parse(name)!;
    expect(parsed.captureTime, t);
    expect(parsed.place, 'Taipei');
    expect(parsed.sizeBytes, 1048576);
    expect(parsed.md5, '9f3ab2c1');
    expect(parsed.extension, 'jpg');
    expect(parsed.contentKey, '9f3ab2c1:1048576');
  });

  test('place is optional', () {
    final name = MediaFilename.build(
      captureTime: t,
      sizeBytes: 42,
      md5Hex: '0011223344',
      extension: 'mp4',
    );
    expect(name, '20260615T090503_42_00112233.mp4');
    expect(MediaFilename.parse(name)!.place, isNull);
  });

  test('place sanitization drops separators we split on', () {
    final name = MediaFilename.build(
      captureTime: t,
      sizeBytes: 1,
      md5Hex: 'aabbccdd',
      extension: 'jpg',
      place: 'New York / Times_Square',
    );
    // '_' and '/' and spaces → '-', so the place stays one token.
    expect(name.contains('New-York-Times-Square'), isTrue);
    expect(MediaFilename.parse(name)!.place, 'New-York-Times-Square');
  });

  test('rejects non-matching names', () {
    expect(MediaFilename.parse('IMG_1234.jpg'), isNull);
    expect(MediaFilename.parse('random.txt'), isNull);
    expect(MediaFilename.parse('noext'), isNull);
    // bad md5 (not 8 hex)
    expect(MediaFilename.parse('20260615T090503_42_zzzz.jpg'), isNull);
  });

  test('CJK place is preserved', () {
    final name = MediaFilename.build(
      captureTime: t,
      sizeBytes: 9,
      md5Hex: '12345678',
      extension: 'heic',
      place: '台北',
    );
    expect(MediaFilename.parse(name)!.place, '台北');
  });
}
