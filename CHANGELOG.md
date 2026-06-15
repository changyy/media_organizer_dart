## 1.20260615.1205955

Initial release. Versions follow `1.YYYYMMDD.1HHmmss`; `mediaOrganizerVersion`
(printed by `media_organizer --version`) and `pubspec.yaml` are kept in sync by
`tool/set_version.dart`.

- `MediaFilename` — build/parse `<datetime>[_<place>]_<size>_<md5-8>.<ext>`.
- `MediaOrganizer` — scan a folder, probe capture time + GPS, checksum, dedup by
  content key, rename into the scheme, copy/move to an output folder
  (dry-run + idempotent re-runs).
- Injectable `MediaProbe` (default `CompositeMediaProbe`: image EXIF +
  `Mp4MediaProbe` for video `moov` time/GPS + mtime fallback), `LocationResolver`
  (default none), `MediaTranscoder` (default passthrough), and `MediaFileSystem`
  (default `LocalFileSystem`, optionally `RandomAccessReader`) — keeps the core
  pure, IO-agnostic, and cross-platform.
- `OfflineGeocoder` + `GeoPlace` — a `LocationResolver` that maps GPS to the
  nearest place name fully offline (haversine, no API key). Data-free: you
  supply the place list (e.g. from GeoNames / immich-geodata). Examples:
  `example/offline_geocoder_example.dart` (GeoNames) and
  `example/immich_geodata_example.dart` (zh-TW localized immich-geodata CSVs).
- `Mp4MediaProbe` — pure-Dart MP4/MOV capture time + GPS from the `moov` box
  (Apple `creationdate`, `mvhd` 1904 time, ISO-6709 location); seeks past `mdat`
  via `RandomAccessReader` instead of reading the whole file.
- Verified copies: `verify` (forced on with `move`) re-hashes each written file
  and aborts that item on mismatch, so a corrupt copy never deletes an original.
- Progress + cancellation: `onProgress` per-file callback and a `cancelled`
  predicate on `run()`; the CLI shows a live `[i/total]` line and stops cleanly
  on Ctrl-C.
- `FfmpegTranscoder` — opt-in video re-encode to 1080p H.264 + faststart, with
  `isAvailable()` detection and a per-OS `installHint()` when ffmpeg is missing.
- `UploadTarget` + `MediaUploader` — push an organize run to a cloud sink
  (Google Drive / S3 / SFTP), idempotent via the same content key (NAS needs no
  target — organize straight into the mount). Core stays SDK-free; targets are
  injectable and faked in tests.
- CLI: `media_organizer organize -i <input> -o <output>
  [--move] [--verify] [--dry-run] [-r] [--progress] [--transcode]
  [--ffmpeg <path>]`, plus `media_organizer stats <folder>` and
  `media_organizer --version`.
