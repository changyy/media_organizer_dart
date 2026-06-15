import 'dart:io';

import 'package:path/path.dart' as p;

import 'file_system.dart';
import 'media_metadata.dart';
import 'media_organizer_base.dart';

/// Thrown when [FfmpegTranscoder] is asked to transcode but `ffmpeg` is not on
/// the system. The message carries [FfmpegTranscoder.installHint] so callers can
/// surface it directly.
class FfmpegNotFoundException implements Exception {
  FfmpegNotFoundException(this.executable);

  /// The executable that could not be run (e.g. `ffmpeg`, or a custom path).
  final String executable;

  @override
  String toString() =>
      'FfmpegNotFoundException: "$executable" not found.\n'
      '${FfmpegTranscoder.installHint()}';
}

/// A [MediaTranscoder] that re-encodes videos to 1080p H.264 + AAC with
/// `+faststart` (moov atom at the front, so playback can begin before the whole
/// file is downloaded). Images pass through untouched.
///
/// This implementation shells out to `ffmpeg` and reads/writes **real files on
/// disk**, so it only works with a [LocalFileSystem] (real paths). For an
/// in-memory or remote [MediaFileSystem], keep the default
/// [PassthroughTranscoder] or provide your own.
///
/// `ffmpeg` is not bundled. Check [isAvailable] first; if it returns false,
/// show [installHint] to the user instead of crashing.
class FfmpegTranscoder implements MediaTranscoder {
  FfmpegTranscoder({
    this.executable = 'ffmpeg',
    this.crf = 23,
    this.preset = 'veryfast',
    Directory? workDir,
  }) : _workDir = workDir;

  /// The ffmpeg executable to invoke (name on `PATH`, or an absolute path).
  final String executable;

  /// x264 constant rate factor (lower = higher quality / bigger file).
  final int crf;

  /// x264 speed/efficiency preset.
  final String preset;

  Directory? _workDir;
  int _counter = 0;

  /// Whether [executable] can be run (i.e. `ffmpeg -version` succeeds).
  static Future<bool> isAvailable([String executable = 'ffmpeg']) async {
    try {
      final r = await Process.run(executable, const ['-version']);
      return r.exitCode == 0;
    } on ProcessException {
      return false;
    }
  }

  /// A per-OS message telling the user how to install ffmpeg.
  static String installHint() {
    final String os;
    if (Platform.isMacOS) {
      os = 'macOS:   brew install ffmpeg   (or: sudo port install ffmpeg)';
    } else if (Platform.isWindows) {
      os = 'Windows: winget install Gyan.FFmpeg   (or: choco install ffmpeg)';
    } else if (Platform.isLinux) {
      os =
          'Linux:   sudo apt install ffmpeg   (or your distro\'s package '
          'manager)';
    } else {
      os = 'See the download page below.';
    }
    return 'ffmpeg is required for transcoding but was not found.\n'
        '  $os\n'
        '  Downloads: https://ffmpeg.org/download.html';
  }

  Directory get _dir =>
      _workDir ??= Directory.systemTemp.createTempSync('mo_transcode');

  @override
  Future<String> transcode(String inputPath, MediaFileSystem fs) async {
    // Only videos are re-encoded; images pass straight through.
    final ext = p.extension(inputPath).replaceAll('.', '').toLowerCase();
    if (mediaKindForExtension(ext) != MediaKind.video) return inputPath;

    if (!await isAvailable(executable)) {
      throw FfmpegNotFoundException(executable);
    }

    final out = p.join(_dir.path, 'mo_${_counter++}.mp4');
    final args = <String>[
      '-y',
      '-i', inputPath,
      // Downscale to fit within 1920x1080 without upscaling, keeping aspect
      // ratio and even dimensions (required by libx264).
      '-vf',
      'scale=w=min(1920\\,iw):h=min(1080\\,ih):'
          'force_original_aspect_ratio=decrease:force_divisible_by=2',
      '-c:v', 'libx264',
      '-preset', preset,
      '-crf', '$crf',
      '-c:a', 'aac',
      '-movflags', '+faststart',
      out,
    ];
    final r = await Process.run(executable, args);
    if (r.exitCode != 0) {
      throw Exception(
        'ffmpeg failed (exit ${r.exitCode}) for $inputPath:\n${r.stderr}',
      );
    }
    return out;
  }
}
