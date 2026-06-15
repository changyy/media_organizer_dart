import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:media_organizer/media_organizer.dart';

Future<void> main(List<String> argv) async {
  final runner =
      CommandRunner<int>(
          'media_organizer',
          'Normalize photos/videos to '
              '<datetime>[_<place>]_<size>_<md5-8>.<ext>, and summarize them.',
        )
        ..argParser.addFlag(
          'version',
          negatable: false,
          help: 'Print the version and exit.',
        )
        ..addCommand(_OrganizeCommand())
        ..addCommand(_StatsCommand());
  try {
    final top = runner.parse(argv);
    if (top['version'] as bool) {
      stdout.writeln('media_organizer $mediaOrganizerVersion');
      exit(0);
    }
    final code = await runner.runCommand(top) ?? 0;
    exit(code);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exit(64);
  }
}

class _OrganizeCommand extends Command<int> {
  _OrganizeCommand() {
    argParser
      ..addOption('input', abbr: 'i', help: 'Source folder to scan.')
      ..addOption('output', abbr: 'o', help: 'Destination folder.')
      ..addFlag('move', help: 'Move instead of copy.', defaultsTo: false)
      ..addFlag(
        'recursive',
        abbr: 'r',
        help: 'Scan subfolders.',
        defaultsTo: true,
      )
      ..addFlag('dry-run', abbr: 'n', help: 'Preview without writing.')
      ..addFlag(
        'verify',
        help:
            'Re-hash each written file; abort that item on mismatch. '
            'Always on with --move.',
        defaultsTo: false,
      )
      ..addFlag(
        'progress',
        help: 'Print a live [i/total] progress line to stderr.',
        defaultsTo: true,
      )
      ..addFlag(
        'transcode',
        help: 'Re-encode videos to 1080p H.264 + faststart via ffmpeg.',
        defaultsTo: false,
      )
      ..addOption(
        'ffmpeg',
        help: 'Path to the ffmpeg executable (default: found on PATH).',
        defaultsTo: 'ffmpeg',
      );
  }

  @override
  String get name => 'organize';
  @override
  String get description =>
      'Scan a folder and rename/dedup media into the output folder.';

  @override
  Future<int> run() async {
    final a = argResults!;
    final inPath = a['input'] as String?;
    final outPath = a['output'] as String?;
    if (inPath == null || outPath == null) {
      stderr.writeln('Both --input and --output are required.\n$usage');
      return 64;
    }
    if (!await Directory(inPath).exists()) {
      stderr.writeln('Input folder not found: $inPath');
      return 66;
    }
    final dryRun = a['dry-run'] as bool;

    MediaTranscoder? transcoder;
    if (a['transcode'] as bool) {
      final exe = a['ffmpeg'] as String;
      if (!await FfmpegTranscoder.isAvailable(exe)) {
        stderr.writeln(FfmpegTranscoder.installHint());
        return 69; // EX_UNAVAILABLE
      }
      transcoder = FfmpegTranscoder(executable: exe);
    }

    final showProgress = a['progress'] as bool && stderr.hasTerminal;
    var stop = false;
    final sigint = ProcessSignal.sigint.watch().listen((_) {
      stderr.writeln('\nCancelling — finishing current file…');
      stop = true;
    });

    final report = await MediaOrganizer(transcoder: transcoder).run(
      input: inPath,
      output: outPath,
      recursive: a['recursive'] as bool,
      move: a['move'] as bool,
      dryRun: dryRun,
      verify: a['verify'] as bool,
      cancelled: () => stop,
      onProgress: showProgress
          ? (pr) => stderr.write('\r[${pr.index}/${pr.total}] ')
          : null,
    );
    await sigint.cancel();
    if (showProgress) stderr.writeln();
    for (final item in report.organized) {
      stdout.writeln('  ${item.name}');
    }
    if (report.duplicates.isNotEmpty) {
      stdout.writeln('  (${report.duplicates.length} duplicate(s) skipped)');
    }
    for (final f in report.failed) {
      stderr.writeln('  FAILED ${f.$1}: ${f.$2}');
    }
    stdout.writeln(
      '${dryRun ? "[dry-run] " : ""}'
      '${report.organized.length} organized, '
      '${report.duplicates.length} duplicates, ${report.failed.length} failed.',
    );
    return report.failed.isEmpty ? 0 : 1;
  }
}

class _StatsCommand extends Command<int> {
  _StatsCommand() {
    argParser.addFlag(
      'recursive',
      abbr: 'r',
      help: 'Scan subfolders.',
      defaultsTo: true,
    );
  }

  @override
  String get name => 'stats';
  @override
  String get description =>
      'Summarize a folder of organized media: total + per-month photo/video '
      'counts (e.g. "2026.01  12 photos  3 videos").';
  @override
  String get invocation => 'media_organizer stats <folder>';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      stderr.writeln('Usage: $invocation');
      return 64;
    }
    final summary = await summarizeFolder(
      rest.first,
      recursive: argResults!['recursive'] as bool,
    );
    stdout.writeln(summary);
    return 0;
  }
}
