/// The package version, also printed by the CLI (`media_organizer --version`).
///
/// Scheme: `1.YYYYMMDD.1HHmmss` — date as the minor, time-of-day as the patch
/// (the leading `1` keeps the patch free of leading zeros, which semver
/// forbids). Kept in sync with `pubspec.yaml` by `tool/set_version.dart`; do not
/// edit by hand.
const String mediaOrganizerVersion = '1.20260615.1205955';
