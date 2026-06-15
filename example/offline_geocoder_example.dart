// Offline reverse-geocoding example: turn the GPS in a photo's EXIF into a
// place name in the filename, with NO network and NO API key.
//
// Run it against the bundled demo (whose photos carry Taipei 101 GPS):
//
//   dart run example/offline_geocoder_example.dart
//   dart run example/offline_geocoder_example.dart <input_dir> <output_dir>
//
// The core ships no geo data — you supply the place list. Here it's a tiny
// inline set of Taiwanese cities; for real coverage load a dataset into a
// List<GeoPlace> (see `parseGeoNamesCities` below) such as GeoNames `cities500`
// or the immich-geodata-zh-TW sets, and localize names by choosing what you put
// in `GeoPlace.name` (e.g. 臺北市).
import 'dart:io';

import 'package:media_organizer/media_organizer.dart';
import 'package:path/path.dart' as p;

const _taiwanCities = <GeoPlace>[
  GeoPlace('Taipei', 25.0330, 121.5654),
  GeoPlace('New-Taipei', 25.0169, 121.4628),
  GeoPlace('Keelung', 25.1276, 121.7392),
  GeoPlace('Taoyuan', 24.9936, 121.3010),
  GeoPlace('Hsinchu', 24.8138, 120.9675),
  GeoPlace('Taichung', 24.1477, 120.6736),
  GeoPlace('Tainan', 22.9999, 120.2270),
  GeoPlace('Kaohsiung', 22.6273, 120.3014),
  GeoPlace('Hualien', 23.9871, 121.6015),
  GeoPlace('Taitung', 22.7583, 121.1444),
];

Future<void> main(List<String> argv) async {
  final input = argv.isNotEmpty ? argv[0] : 'example/demo_input';
  final output = argv.length > 1
      ? argv[1]
      : p.join(Directory.systemTemp.path, 'media_organizer_geo_demo');

  final report = await MediaOrganizer(
    locationResolver: OfflineGeocoder(_taiwanCities, maxDistanceKm: 50),
  ).run(input: input, output: output);

  stdout.writeln('Organized into $output:');
  for (final item in report.organized) {
    stdout.writeln(
      '  ${p.basename(item.source)}  ->  ${p.basename(item.target)}',
    );
  }
  stdout.writeln(report);
}

/// Loads a GeoNames `cities500.txt`-style TSV into [GeoPlace]s (columns:
/// 0 id · 1 name · 2 asciiname · … · 4 latitude · 5 longitude · …). Swap in your
/// own column mapping / name field for a localized dataset.
///
/// Get the data from https://download.geonames.org/export/dump/ — the
/// `citiesN.zip` files list places with population > N:
///   - `cities500`  (~200k rows) — densest; best reverse-geocoding accuracy.
///   - `cities1000` (~140k rows) — a good default; rarely far from a photo.
///   - `cities5000` / `cities15000` — major cities only; coarse for reverse use
///     (a photo can be tens of km from the nearest entry), fine for a picker.
/// For reverse-geocoding into filenames prefer `cities500`/`1000`; for covered
/// countries the zh-TW immich-geodata sets are denser and already localized.
List<GeoPlace> parseGeoNamesCities(String tsv) {
  final out = <GeoPlace>[];
  for (final line in tsv.split('\n')) {
    if (line.trim().isEmpty) continue;
    final c = line.split('\t');
    if (c.length < 6) continue;
    final lat = double.tryParse(c[4]);
    final lng = double.tryParse(c[5]);
    if (lat == null || lng == null) continue;
    out.add(GeoPlace(c[1], lat, lng));
  }
  return out;
}
