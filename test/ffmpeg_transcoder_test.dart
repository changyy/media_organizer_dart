import 'package:media_organizer/media_organizer.dart';
import 'package:test/test.dart';

void main() {
  test('images pass through (no ffmpeg involved)', () async {
    final t = FfmpegTranscoder(executable: 'definitely-not-ffmpeg');
    // Images never invoke ffmpeg, so a bogus executable is fine here.
    final out = await t.transcode('/photos/a.jpg', const LocalFileSystem());
    expect(out, '/photos/a.jpg');
  });

  test('isAvailable is false for a bogus executable', () async {
    expect(
      await FfmpegTranscoder.isAvailable('definitely-not-ffmpeg'),
      isFalse,
    );
  });

  test(
    'transcoding a video without ffmpeg throws FfmpegNotFoundException',
    () async {
      final t = FfmpegTranscoder(executable: 'definitely-not-ffmpeg');
      expect(
        () => t.transcode('/videos/clip.mp4', const LocalFileSystem()),
        throwsA(isA<FfmpegNotFoundException>()),
      );
    },
  );

  test('installHint mentions ffmpeg and the download page', () {
    final hint = FfmpegTranscoder.installHint();
    expect(hint, contains('ffmpeg'));
    expect(hint, contains('https://ffmpeg.org/download.html'));
  });
}
