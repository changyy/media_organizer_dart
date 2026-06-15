#!/usr/bin/env python3
"""Generate demo media for media_organizer.

Creates a few photos with EXIF capture-time + GPS at Taipei 101, plus a couple
of videos (their capture time comes from the file mtime, which the organizer
uses as a fallback for videos), and one duplicate photo to show dedup.

Requires: ffmpeg on PATH, and `pip install piexif`.

Usage: python make_demo_samples.py [output_dir]   # default: example/demo_input
"""
import os
import shutil
import subprocess
import sys
from datetime import datetime

import piexif

OUT = sys.argv[1] if len(sys.argv) > 1 else "example/demo_input"
os.makedirs(OUT, exist_ok=True)
FF = shutil.which("ffmpeg")
if not FF:
    sys.exit("ffmpeg not found on PATH")

LAT, LNG = 25.033964, 121.564468  # Taipei 101


def make_jpg(path, color):
    subprocess.run(
        [FF, "-y", "-f", "lavfi", "-i", f"color=c={color}:s=640x480",
         "-frames:v", "1", path],
        check=True, capture_output=True,
    )


def make_mp4(path, seconds):
    subprocess.run(
        [FF, "-y", "-f", "lavfi",
         "-i", f"testsrc=size=320x240:rate=15:duration={seconds}",
         "-pix_fmt", "yuv420p", path],
        check=True, capture_output=True,
    )


def to_dms(value):
    value = abs(value)
    d = int(value)
    m = int((value - d) * 60)
    s = round((value - d - m / 60) * 3600 * 100)
    return [(d, 1), (m, 1), (s, 100)]


def set_exif(path, dt_str, lat, lng):
    gps = {
        piexif.GPSIFD.GPSLatitudeRef: "N" if lat >= 0 else "S",
        piexif.GPSIFD.GPSLatitude: to_dms(lat),
        piexif.GPSIFD.GPSLongitudeRef: "E" if lng >= 0 else "W",
        piexif.GPSIFD.GPSLongitude: to_dms(lng),
    }
    exif = {
        "0th": {},
        "Exif": {piexif.ExifIFD.DateTimeOriginal: dt_str},
        "GPS": gps, "1st": {}, "thumbnail": None,
    }
    piexif.insert(piexif.dump(exif), path)


def touch(path, when: datetime):
    ts = when.timestamp()
    os.utime(path, (ts, ts))


# Photos — EXIF capture time + GPS at Taipei 101.
make_jpg(f"{OUT}/sunset.jpg", "orange")
set_exif(f"{OUT}/sunset.jpg", "2026:01:15 08:30:00", LAT, LNG)
make_jpg(f"{OUT}/skyline.jpg", "blue")
set_exif(f"{OUT}/skyline.jpg", "2026:03:20 17:45:10", LAT, LNG)

# A byte-for-byte duplicate of the first photo (to show dedup).
shutil.copyfile(f"{OUT}/sunset.jpg", f"{OUT}/sunset_again.jpg")

# Videos — no EXIF; the organizer uses the file mtime as the capture time.
make_mp4(f"{OUT}/clip_a.mp4", 2)
touch(f"{OUT}/clip_a.mp4", datetime(2026, 2, 10, 12, 0, 0))
make_mp4(f"{OUT}/clip_b.mp4", 3)
touch(f"{OUT}/clip_b.mp4", datetime(2026, 4, 5, 19, 30, 15))

print(f"Wrote demo media to {OUT}/")
for name in sorted(os.listdir(OUT)):
    print(f"  {name}")
