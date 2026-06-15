import 'package:media_organizer/media_organizer.dart';
import 'package:test/test.dart';

void main() {
  test('summarizes normalized names by month, split photo/video', () {
    final summary = summarizeNames([
      '20260115T083000_Taipei-101_2187_de2c09bb.jpg', // 2026.01 photo
      '20260120T100000_10_aaaaaaaa.png', // 2026.01 photo
      '20260210T120000_11402_da8ef46e.mp4', // 2026.02 video
      '20260405T193015_15064_6e823421.mov', // 2026.04 video
      'IMG_1234.jpg', // not normalized → ignored
      '20260120T100000_10_aaaaaaaa.txt', // non-media ext → ignored
    ]);

    expect(summary.total, 4);
    expect(summary.photos, 2);
    expect(summary.videos, 2);
    expect(summary.byMonth.keys.toList(), ['2026.01', '2026.02', '2026.04']);
    expect(summary.byMonth['2026.01']!.photos, 2);
    expect(summary.byMonth['2026.01']!.videos, 0);
    expect(summary.byMonth['2026.02']!.videos, 1);
  });

  test('empty input → zero summary', () {
    final s = summarizeNames(const []);
    expect(s.total, 0);
    expect(s.byMonth, isEmpty);
  });

  test('mediaKindForExtension classifies', () {
    expect(mediaKindForExtension('JPG'), MediaKind.photo);
    expect(mediaKindForExtension('.mp4'), MediaKind.video);
    expect(mediaKindForExtension('txt'), MediaKind.other);
  });
}
