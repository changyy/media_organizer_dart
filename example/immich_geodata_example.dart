// Offline reverse-geocoding backed by the immich-geodata-zh-TW dataset
// (https://github.com/RxChi1d/immich-geodata-zh-TW) — fully offline, no network.
//
// That project ships clean per-country CSVs (in its `meta_data/` folder, or its
// release archive) with this header:
//
//   latitude,longitude,country,admin_1,admin_2,admin_3,admin_4
//   23.886,120.754,臺灣,南投縣,中寮鄉,中寮村,
//
// The place names are already localized (zh-TW), so loading one (or several) of
// these into a List<GeoPlace> is all it takes — the core package itself bundles
// no data and makes no network calls.
//
//   # point this at one *_geodata.csv, or a folder of them (all countries):
//   dart run example/immich_geodata_example.dart /path/to/tw_geodata.csv
//   dart run example/immich_geodata_example.dart /path/to/meta_data   # whole dir
//   dart run example/immich_geodata_example.dart <csv-or-dir> <in> <out>
//
// Load only the countries you care about: tw is ~8k points (instant); the full
// set (jp/id are 100k+) is ~250k and a linear scan over all of them per photo
// gets slow — add a spatial index in your app if you need the whole world.
import 'dart:io';

import 'package:media_organizer/media_organizer.dart';
import 'package:path/path.dart' as p;

/// Parses an immich-geodata-zh-TW `*_geodata.csv` into [GeoPlace]s.
///
/// [nameOf] composes the filename label from one row's fields; the default
/// joins the two most specific non-empty admin levels (e.g. `南投縣-中寮鄉`).
List<GeoPlace> loadGeodataCsv(
  String csv, {
  String Function(List<String> adminLevels, String country)? nameOf,
}) {
  final compose = nameOf ?? _defaultName;
  final places = <GeoPlace>[];
  final lines = csv.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) continue;
    final c = line.split(',');
    if (c.length < 7) continue;
    final lat = double.tryParse(c[0]);
    final lng = double.tryParse(c[1]);
    if (lat == null || lng == null) continue; // skips the header row too
    final country = c[2];
    final admin = c.sublist(3); // admin_1 .. admin_4
    final name = compose(admin, country);
    if (name.isEmpty) continue;
    places.add(GeoPlace(name, lat, lng));
  }
  return places;
}

/// Loads every `*_geodata.csv` in [dir] (all countries) into one list.
Future<List<GeoPlace>> loadGeodataDir(
  String dir, {
  String Function(List<String> adminLevels, String country)? nameOf,
}) async {
  final files =
      Directory(dir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('_geodata.csv'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final out = <GeoPlace>[];
  for (final f in files) {
    out.addAll(loadGeodataCsv(await f.readAsString(), nameOf: nameOf));
  }
  return out;
}

String _defaultName(List<String> admin, String country) {
  final filled = admin.where((s) => s.trim().isNotEmpty).toList();
  if (filled.isEmpty) return country;
  // The two most specific levels, broad-to-narrow (e.g. 南投縣-中寮鄉).
  final pick = filled.length <= 2 ? filled : filled.sublist(0, 2);
  return pick.join('-');
}

Future<void> main(List<String> argv) async {
  if (argv.isEmpty) {
    stderr.writeln(
      'Usage: dart run example/immich_geodata_example.dart '
      '<geodata.csv> [input_dir] [output_dir]',
    );
    exitCode = 64;
    return;
  }
  final src = argv[0];
  final input = argv.length > 1 ? argv[1] : 'example/demo_input';
  final output = argv.length > 2
      ? argv[2]
      : p.join(Directory.systemTemp.path, 'media_organizer_immich_demo');

  final isDir =
      await FileSystemEntity.type(src) == FileSystemEntityType.directory;
  final places = isDir
      ? await loadGeodataDir(src)
      : loadGeodataCsv(await File(src).readAsString());
  stdout.writeln('Loaded ${places.length} places from ${p.basename(src)}');

  final report = await MediaOrganizer(
    locationResolver: OfflineGeocoder(places, maxDistanceKm: 25),
  ).run(input: input, output: output);

  stdout.writeln('Organized into $output:');
  for (final item in report.organized) {
    stdout.writeln(
      '  ${p.basename(item.source)}  ->  ${p.basename(item.target)}',
    );
  }
  stdout.writeln(report);
}
