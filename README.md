# media_organizer

[![Pub Version](https://img.shields.io/pub/v/media_organizer)](https://pub.dev/packages/media_organizer)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Normalize photos and videos into **self-describing, sortable, dedup-friendly
filenames** — then they're easy to manage anywhere (local, Google Drive, NAS).

```
<YYYYMMDDTHHmmss>[_<place>]_<sizeBytes>_<md5-8>.<ext>
20260615T091500_Taipei_1048576_9f3ab2c1.jpg
```

- **Sortable** — sort by name = sort by capture time.
- **Self-describing** — capture time + optional place are in the name.
- **Dedup-friendly** — the trailing `<size>_<md5-8>` is a content key; identical
  bytes ⇒ identical key, so duplicates are detected without a database.

Ships as a **CLI and a library**, pure `dart:io` — runs on desktop and mobile
(import the library on tablets/phones; not web).

## CLI

```sh
dart pub global activate media_organizer

# Organize: rename + dedup into an output folder
media_organizer organize -i ~/Camera -o ~/Organized
media_organizer organize -i ~/Camera -o ~/Organized --move       # move, not copy
media_organizer organize -i ~/Camera -o ~/Organized --dry-run    # preview only
media_organizer organize -i ~/Camera -o ~/Organized --verify     # re-hash each copy
#   --move always verifies first: a copy is re-hashed and only on a match is the
#   original deleted, so a bad copy never loses an original. Ctrl-C stops
#   cleanly after the current file; a live [i/total] line shows progress.
media_organizer organize -i ~/Camera -o ~/Organized --transcode  # re-encode videos
#   --transcode re-encodes videos to 1080p H.264 + faststart via ffmpeg.
#   Needs ffmpeg on PATH (or --ffmpeg <path>); if missing it prints install
#   instructions and exits without touching your files.

# Stats: total + per-month photo/video counts (no database — reads the names)
media_organizer stats ~/Organized
#   Total: 120 (95 photos, 25 videos)
#     2026.01    12 photos     3 videos
#     2026.02     8 photos     1 videos
```

In this repo you can run it without installing:

```sh
dart run bin/media_organizer.dart organize -i <in> -o <out>
dart run bin/media_organizer.dart stats <folder>
dart run tool/demo.dart        # organizes the bundled example/demo_input
```

> `stats` needs no database — the filename **is** the index (capture time + kind
> are in the name), so it works on any folder of normalized files.

## Library

```dart
import 'package:media_organizer/media_organizer.dart';

final report = await MediaOrganizer().run(
  input: '/camera',
  output: '/organized',
  verify: true, // re-hash each copy (forced on when move: true)
  onProgress: (p) => print('[${p.index}/${p.total}] ${p.path}'),
  cancelled: () => false, // return true to stop the run cleanly
);
print(report); // organized / duplicates / failed
```

### Pluggable (cross-platform by design)

The engine is platform-independent; the platform-specific or networked parts are
injectable interfaces with safe defaults:

- `MediaProbe` — capture time + GPS. Default `CompositeMediaProbe` routes by
  kind: `ExifMediaProbe` (image EXIF) for photos, `Mp4MediaProbe` (parses the
  MP4/MOV `moov` box — Apple `creationdate`, `mvhd` time, ISO-6709 GPS) for
  videos, then falls back to the file's modified time when neither has a date.
- `LocationResolver` — GPS → place label for the filename. Default: none (no
  network). Ships with `OfflineGeocoder` (haversine nearest-neighbour, fully
  offline, **no API key**) — see [Offline geocoding](#offline-geocoding).
- `MediaTranscoder` — optional transcode before output. Default
  `PassthroughTranscoder` (no transcode). A ready-made `FfmpegTranscoder`
  re-encodes videos to 1080p H.264 + faststart (`FfmpegTranscoder.isAvailable()`
  / `FfmpegTranscoder.installHint()` let you detect ffmpeg and guide the user);
  it shells out to ffmpeg and reads/writes real files, so use it with
  `LocalFileSystem`.
- `MediaFileSystem` — all file IO (list/read/copy/delete) goes through this.
  Default `LocalFileSystem` uses `dart:io` (desktop + mobile). Inject your own
  for an alternate source or fully in-memory tests — the engine itself never
  touches `dart:io`. (`dart:io` covers every native platform; only web lacks it,
  and a folder organizer can't run in a browser anyway.)

```dart
MediaOrganizer(
  probe: MyVideoAwareProbe(),
  locationResolver: MyGeocoder(),
  transcoder: FfmpegTranscoder(),
);
```

## Upload (Google Drive / NAS)

**NAS needs no code** — it's a mount, so just organize straight into it:

```sh
media_organizer organize -i ~/Camera -o /Volumes/nas/Photos
```

For cloud targets, `UploadTarget` is a tiny injectable sink that consumes an
organize run. The core stays SDK-free — implement the target in your app (or a
side package) with whatever client you like:

```dart
final report = await MediaOrganizer().run(input: '/camera', output: '/staged');
final upload = await MediaUploader(target: MyDriveTarget()).run(report.organized);
print(upload); // uploaded / skipped / failed
```

The **same content key** that dedups locally also dedups remotely: a target
reports the keys it already has via `existingContentKeys()`, so re-runs upload
only what's new (and identical bytes within one run upload once). See
`test/upload_target_test.dart` for the `FakeUploadTarget` skeleton a real
Drive/S3/SFTP target follows.

## Offline geocoding

`OfflineGeocoder` turns the GPS in a photo into the nearest place name for the
`<place>` slot — fully offline, no API key. The core ships **no geo data**: you
pass the place list, so the package never bundles (or assumes a format for) a
dataset.

```dart
final geocoder = OfflineGeocoder(const [
  GeoPlace('Taipei', 25.0330, 121.5654),
  GeoPlace('Kaohsiung', 22.6273, 120.3014),
  // …
], maxDistanceKm: 50); // farther than this ⇒ no place

await MediaOrganizer(locationResolver: geocoder).run(input: '/camera', output: '/out');
// 20260115T083000_Taipei_2187_de2c09bb.jpg
```

For real coverage, load a dataset into `List<GeoPlace>` and localize names by
choosing what you put in `GeoPlace.name`:

- `example/offline_geocoder_example.dart` — inline cities + a `parseGeoNamesCities`
  helper for GeoNames. Get the data from
  [download.geonames.org](https://download.geonames.org/export/dump/): the
  `citiesN.zip` files list places with population > N. For reverse-geocoding
  prefer the **dense** `cities500` (~200k) or `cities1000` (~140k); `cities5000`/
  `cities15000` are major-cities-only (coarse for reverse, fine for a picker).
- `example/immich_geodata_example.dart` — reads the **already zh-TW localized**
  CSVs from [immich-geodata-zh-TW](https://github.com/RxChi1d/immich-geodata-zh-TW)
  (`latitude,longitude,country,admin_1..4`); a Taipei 101 photo comes out as
  `…_臺北市-信義區_…`. Fully offline — you supply the downloaded CSV path.

The lookup is a linear scan (fine for thousands of points; a country file like
`tw` is ~8k); for a full global set, wrap it with a spatial index in your app.

### Which geocoding strategy?

`LocationResolver` is just an interface — pick the backing that fits your
context (they all inject the same way, no core change):

| Strategy | Best for | Trade-offs |
| --- | --- | --- |
| **Offline dataset** (`OfflineGeocoder` + GeoNames / immich-geodata) | CLI / batch over thousands of files | Reproducible, no rate limits, works offline. You ship/download the data; names only as precise as the dataset. |
| **Platform geocoder** (iOS/macOS `CLGeocoder`, Android `Geocoder`, via the `geocoding` plugin) | Interactive Flutter app, modest volume | Best names, auto-localized, no data to ship. But it's an online call, **rate-limited** (bad for big batches), and Apple/Android-only — so it lives in your app, not this pure-Dart core. |
| **Offline-first hybrid** | Want quality *and* scale | Resolve offline first; only fall back to the platform geocoder on a miss, and **cache** results (rounded coords → name) so a trip's worth of nearby photos doesn't hammer the API. |

```dart
// Hybrid sketch (lives in your app — the platform geocoder is not pure Dart):
class HybridGeocoder implements LocationResolver {
  HybridGeocoder(this.offline, this.platform);
  final LocationResolver offline;
  final LocationResolver platform; // e.g. backed by package:geocoding
  final _cache = <String, String?>{};

  @override
  Future<String?> resolve(double lat, double lng) async {
    final key = '${lat.toStringAsFixed(2)},${lng.toStringAsFixed(2)}';
    return _cache[key] ??=
        await offline.resolve(lat, lng) ?? await platform.resolve(lat, lng);
  }
}
```

### Geo-data licensing

This package bundles **no geo data** — you supply it — so nothing here is
encumbered. But the datasets the examples point at carry their own licenses, and
**complying is the responsibility of whoever ships them**:

- **GeoNames** — CC BY 4.0: free (incl. commercial), **attribution required**.
- **SimpleMaps** (free tier) — CC BY 4.0: **attribution required**.
- **OpenStreetMap** (and OSM-derived data, e.g. the immich-geodata sets) — ODbL
  1.0: **attribution** (“© OpenStreetMap contributors”) **and share-alike** on a
  derived database you distribute.
- **Natural Earth** — public domain; **Wikidata** — CC0 (public domain).

Note: the immich-geodata-zh-TW *project code* is GPL v3, but this package only
reads its **data output** (governed by the data licenses above) — it does not
include or link that code, so your MIT package stays MIT.

## Filename helper

`MediaFilename.build(...)` / `MediaFilename.parse(name)` give you the scheme on
its own (e.g. to sort or group an existing library).

## Status & limits

- Capture time: **image EXIF** for photos, **MP4/MOV `moov`** for videos, with a
  file-mtime fallback. Containers without embedded time (e.g. some camera/transcoded
  clips) use mtime. `mvhd` time is treated as UTC; an Apple `creationdate` (with a
  real timezone) is preferred when present.
- **Geocoding is not built in** — it's an injectable interface (no network by
  default). Transcoding is opt-in via `FfmpegTranscoder` (needs ffmpeg
  installed); the core itself stays ffmpeg-free. Upload targets (Google Drive /
  NAS) are out of scope for the core and layered on top.
- No web (uses `dart:io`).

## License

MIT
