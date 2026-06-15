# Demo

`demo_input/` holds sample media; `demo_output/` is what `media_organizer`
produces from it. Photos carry EXIF capture-time + GPS at **Taipei 101**; videos
have no EXIF so their time comes from the file's modified time.

| input (`demo_input/`) | → output (`demo_output/`) |
|---|---|
| `sunset.jpg`  (EXIF 2026-01-15 08:30, GPS Taipei 101) | `20260115T083000_Taipei-101_2187_de2c09bb.jpg` |
| `skyline.jpg` (EXIF 2026-03-20 17:45, GPS Taipei 101) | `20260320T174510_Taipei-101_2187_1569bbbb.jpg` |
| `sunset_again.jpg` (byte-copy of `sunset.jpg`) | *(duplicate — skipped)* |
| `clip_a.mp4`  (mtime 2026-02-10 12:00) | `20260210T120000_11402_da8ef46e.mp4` |
| `clip_b.mp4`  (mtime 2026-04-05 19:30) | `20260405T193015_15064_6e823421.mp4` |

The place label (`Taipei-101`) comes from a demo `LocationResolver`; swap in a
real geocoder in production. Videos show no place yet (a video-metadata
`MediaProbe` is future work).

## Run it

```sh
dart run tool/demo.dart                                    # input → output
dart run example/media_organizer_example.dart demo_input demo_output
dart run bin/media_organizer.dart stats example/demo_output
```

Regenerate the input media (needs `ffmpeg` + `pip install piexif`):

```sh
python example/make_demo_samples.py example/demo_input
```
