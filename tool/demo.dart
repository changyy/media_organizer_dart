// Zero-arg demo: organizes the committed `example/demo_input` into
// `example/demo_output`, printing the before → after mapping.
//
//   dart run tool/demo.dart
//
// (Regenerate the input media with: python example/make_demo_samples.py)
import 'dart:io';

import 'package:media_organizer/media_organizer.dart';
import 'package:path/path.dart' as p;

/// Demo geocoder: anything near Taipei 101 → "Taipei-101". Replace with a real
/// geocoder in production.
class Taipei101Geocoder implements LocationResolver {
  @override
  Future<String?> resolve(double latitude, double longitude) async {
    final near =
        (latitude - 25.0340).abs() < 0.02 &&
        (longitude - 121.5645).abs() < 0.02;
    return near ? 'Taipei-101' : null;
  }
}

Future<void> main() async {
  final input = Directory('example/demo_input');
  final output = Directory('example/demo_output');
  if (!input.existsSync()) {
    stderr.writeln(
      'Missing example/demo_input — generate it first:\n'
      '  python example/make_demo_samples.py example/demo_input',
    );
    exit(1);
  }
  // Start clean so the demo always shows the full conversion.
  if (output.existsSync()) output.deleteSync(recursive: true);

  final report = await MediaOrganizer(
    probe: const ExifMediaProbe(),
    locationResolver: Taipei101Geocoder(),
  ).run(input: input.path, output: output.path);

  stdout.writeln('input  (example/demo_input):');
  for (final f in input.listSync()..sort((a, b) => a.path.compareTo(b.path))) {
    stdout.writeln('  ${p.basename(f.path)}');
  }
  stdout.writeln('\noutput (example/demo_output):');
  for (final item in report.organized) {
    stdout.writeln(
      '  ${p.basename(item.source).padRight(18)} →  '
      '${p.basename(item.target)}',
    );
  }
  if (report.duplicates.isNotEmpty) {
    for (final d in report.duplicates) {
      stdout.writeln('  ${p.basename(d).padRight(18)} →  (duplicate, skipped)');
    }
  }
  stdout.writeln('\n$report');
}
