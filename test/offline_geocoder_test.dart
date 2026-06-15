import 'package:media_organizer/media_organizer.dart';
import 'package:test/test.dart';

void main() {
  final places = const [
    GeoPlace('Taipei', 25.0330, 121.5654),
    GeoPlace('Kaohsiung', 22.6273, 120.3014),
    GeoPlace('Tokyo', 35.6812, 139.7671),
  ];

  test('resolves to the nearest place', () async {
    final g = OfflineGeocoder(places);
    // Taipei 101.
    expect(await g.resolve(25.0339, 121.5645), 'Taipei');
  });

  test('returns null beyond maxDistanceKm', () async {
    final g = OfflineGeocoder(places, maxDistanceKm: 50);
    expect(await g.resolve(0, 0), isNull); // middle of the ocean
  });

  test('a generous radius still returns the nearest', () async {
    final g = OfflineGeocoder(places, maxDistanceKm: 100000);
    expect(await g.resolve(24.0, 121.0), 'Taipei'); // central Taiwan
  });

  test('haversine distance is sane (Taipei→Kaohsiung ≈ 300 km)', () {
    final d = OfflineGeocoder.distanceKm(25.0330, 121.5654, 22.6273, 120.3014);
    expect(d, closeTo(296, 15));
  });

  test('plugs into MediaOrganizer as a LocationResolver', () async {
    // Trivial check that the type wires in (no IO).
    final LocationResolver r = OfflineGeocoder(places);
    expect(await r.resolve(25.0339, 121.5645), 'Taipei');
  });
}
