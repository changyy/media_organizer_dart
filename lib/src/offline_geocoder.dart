import 'dart:math' as math;

import 'media_metadata.dart';

/// A named point used by [OfflineGeocoder].
class GeoPlace {
  const GeoPlace(this.name, this.latitude, this.longitude);
  final String name;
  final double latitude;
  final double longitude;
}

/// A [LocationResolver] that turns GPS into the nearest place name **fully
/// offline** — no network, no API keys. It is intentionally **data-free**: you
/// supply the [places] list, so the core package never bundles (or assumes a
/// format for) a geo dataset. Point it at any source you like — GeoNames
/// `cities500`, the immich-geodata sets, your own list — and localize names
/// however you want (e.g. zh-TW) by choosing what goes in [GeoPlace.name].
///
/// Resolution is a haversine nearest-neighbour scan; matches farther than
/// [maxDistanceKm] resolve to `null` (so the filename simply omits the place).
/// The scan is linear — fine for thousands of points; for a full global dataset
/// (hundreds of thousands) wrap it with a spatial index (geohash buckets / a
/// k-d tree) in your app.
class OfflineGeocoder implements LocationResolver {
  OfflineGeocoder(this.places, {this.maxDistanceKm = 50});

  final List<GeoPlace> places;

  /// Beyond this distance from the nearest place, resolve to `null`.
  final double maxDistanceKm;

  @override
  Future<String?> resolve(double latitude, double longitude) async {
    GeoPlace? best;
    var bestKm = double.infinity;
    for (final place in places) {
      final d = distanceKm(
        latitude,
        longitude,
        place.latitude,
        place.longitude,
      );
      if (d < bestKm) {
        bestKm = d;
        best = place;
      }
    }
    if (best == null || bestKm > maxDistanceKm) return null;
    return best.name;
  }

  /// Great-circle distance between two coordinates, in kilometres.
  static double distanceKm(double aLat, double aLng, double bLat, double bLng) {
    const earthKm = 6371.0;
    final dLat = _rad(bLat - aLat);
    final dLng = _rad(bLng - aLng);
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(aLat)) *
            math.cos(_rad(bLat)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return 2 * earthKm * math.asin(math.min(1.0, math.sqrt(h)));
  }

  static double _rad(double deg) => deg * math.pi / 180.0;
}
