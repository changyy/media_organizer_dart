// Example: organize a folder, with a (stub) geocoder that labels Taipei 101.
//
//   dart run example/media_organizer_example.dart <input> <output>
//
// Generate demo media first (photos with EXIF GPS at Taipei 101 + videos):
//   python example/make_demo_samples.py example/demo_input
import 'dart:io';

import 'package:media_organizer/media_organizer.dart';

/// A tiny demo geocoder: anything near Taipei 101 → "Taipei-101".
/// Swap in a real geocoder in production.
class Taipei101Geocoder implements LocationResolver {
  @override
  Future<String?> resolve(double latitude, double longitude) async {
    final near =
        (latitude - 25.0340).abs() < 0.02 &&
        (longitude - 121.5645).abs() < 0.02;
    return near ? 'Taipei-101' : null;
  }
}

Future<void> main(List<String> argv) async {
  if (argv.length < 2) {
    stderr.writeln(
      'Usage: dart run example/media_organizer_example.dart <input> <output>',
    );
    exit(64);
  }
  final report = await MediaOrganizer(
    probe: const ExifMediaProbe(),
    locationResolver: Taipei101Geocoder(),
  ).run(input: argv[0], output: argv[1]);

  stdout.writeln('Organized → ${argv[1]}:');
  for (final item in report.organized) {
    final n = item.name;
    stdout.writeln(
      '  $n   '
      '(time=${n.captureTime}, place=${n.place ?? "-"}, '
      '${n.sizeBytes}B, md5=${n.md5})',
    );
  }
  stdout.writeln(report.toString());
}
