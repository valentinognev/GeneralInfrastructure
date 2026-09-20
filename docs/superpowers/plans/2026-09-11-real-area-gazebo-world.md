# Real-area Gazebo Classic World Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generic host generator (`lat/lon/radius/out`) writes a Gazebo Classic world (ortho + heightmap + OSM solids) under `Dockerfiles/models/`, inject it into Noetic PX4 SITL via `--volume`, and let the GUI pick Empty vs that world.

**Architecture:** Host Python script mosaics Terrarium DEM + Esri imagery + Overpass OSM into a Gazebo model directory. `runSimNoeticMulti.sh` bind-mounts `Dockerfiles/models` as an extra model-path root (`catswarm_host`); `sitl_multiple_run.sh` appends that path after `setup_gazebo.bash`. GUI lists host `*.world` files and passes `--world` plus `PX4_HOME_*` from `origin.json`.

**Tech Stack:** Python 3, numpy, Pillow, requests, shapely, pyproj, pytest; Gazebo Classic 11 / PX4 SITL Docker; React + Express GUI.

**Spec:** `general_infrastructure/docs/superpowers/specs/2026-09-11-real-area-gazebo-world-design.md`

## Global Constraints

- Sim: existing **Gazebo Classic** Noetic image `px4-noetic-sim-ros` (not Jetty/Cesium/Unreal)
- Generator: `general_infrastructure/Dockerfiles/scripts/generate_real_area.py`
- CLI: `--lat --lon --radius-m --out` only (name = basename of `--out`)
- Maps: `general_infrastructure/Dockerfiles/models/<name>/`
- Inject with docker `--volume`; do **not** `COPY` maps into the Dockerfile; do **not** overlay PX4 `models/` (iris must stay)
- First demo: `32.869354, 35.274463`, radius `500` m → 1000 m square, `--out .../models/teradyon`
- OSM extrusion: `height` else `building:levels * 3.0` else `8.0` m; bridges `bridge=yes` / `man_made=bridge`
- Heightmap: **257×257**; origin ground Gazebo z = 0; ENU +X east +Y north
- Tests: pytest fixtures only; no live HTTP
- GUI v1: dropdown only; do not call the generator from Start Sim
- **No git commits** unless the user explicitly asks
- Nested git: `Dockerfiles/` is its own repo; `runSimNoeticMulti.sh` and `multidrone/sitl_multiple_run.sh` live in `general_infrastructure/`
- Empty world: do not set `PX4_HOME_*`; do not mount a host `.world`

## File structure

| Path | Responsibility |
|------|----------------|
| `Dockerfiles/scripts/generate_real_area.py` | CLI + generate pipeline (importable functions) |
| `Dockerfiles/scripts/requirements-real-area.txt` | Host pip deps |
| `Dockerfiles/scripts/tests/test_generate_real_area.py` | Fixture pytest |
| `Dockerfiles/scripts/tests/fixtures/` | Tiny OSM XML used by tests |
| `multidrone/sitl_multiple_run.sh` | Append `GAZEBO_MODEL_PATH` after `setup_gazebo.bash` |
| `runSimNoeticMulti.sh` | `--world`, model volume, world file volume, `PX4_HOME_*` |
| `GUI/server/src/worlds.ts` | List/validate host worlds |
| `GUI/server/src/worlds.test.ts` | Node assert tests for worlds.ts |
| `GUI/server/src/index.ts` | `GET /api/sim/worlds`; `POST /api/sim/start` `world` |
| `GUI/client/src/components/TopController.tsx` | World dropdown |
| `GUI/client/src/App.tsx` | Fetch worlds, persist `catswarm_world`, send `world` |

---

### Task 1: Bbox, CLI validation, building height

**Files:**
- Create: `general_infrastructure/Dockerfiles/scripts/requirements-real-area.txt`
- Create: `general_infrastructure/Dockerfiles/scripts/generate_real_area.py`
- Create: `general_infrastructure/Dockerfiles/scripts/tests/test_generate_real_area.py`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `HEIGHTMAP_N: int = 257`
  - `DEFAULT_BUILDING_HEIGHT_M: float = 8.0`
  - `METERS_PER_LEVEL: float = 3.0`
  - `bbox_from_center(lat: float, lon: float, radius_m: float) -> tuple[float, float, float, float]` → `(south, west, north, east)` WGS84
  - `building_height_m(tags: dict[str, str]) -> float`
  - `parse_args(argv: list[str] | None) -> argparse.Namespace` with `.lat` `.lon` `.radius_m` `.out` (Path)
  - `main(argv: list[str] | None = None) -> int` (0 ok, 2 usage/validation)

- [ ] **Step 1: Write the failing tests**

```python
from pathlib import Path
import sys

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from generate_real_area import (  # noqa: E402
    HEIGHTMAP_N,
    bbox_from_center,
    building_height_m,
    main,
    parse_args,
)

def test_heightmap_n_is_257():
    assert HEIGHTMAP_N == 257
    assert (HEIGHTMAP_N - 1) & (HEIGHTMAP_N - 2) == 0  # 2^n+1

def test_bbox_500m_is_1km_square():
    south, west, north, east = bbox_from_center(32.869354, 35.274463, 500.0)
    assert south < 32.869354 < north
    assert west < 35.274463 < east
    # ~500 m north ≈ 0.0045 deg; allow 20%
    assert 0.0036 < (north - 32.869354) < 0.0055
    assert 0.0036 < (32.869354 - south) < 0.0055

def test_building_height_tag_levels_default():
    assert building_height_m({"height": "12.5"}) == 12.5
    assert building_height_m({"building:levels": "3"}) == 9.0
    assert building_height_m({"building": "yes"}) == 8.0
    assert building_height_m({"height": "10", "building:levels": "99"}) == 10.0

def test_cli_requires_all_flags():
    assert main([]) == 2
    assert main(["--lat", "1", "--lon", "2", "--radius-m", "10"]) == 2

def test_cli_rejects_bad_lat():
    assert main(["--lat", "91", "--lon", "0", "--radius-m", "10", "--out", "/tmp/x"]) == 2
    assert main(["--lat", "0", "--lon", "0", "--radius-m", "0", "--out", "/tmp/x"]) == 2

def test_parse_args_out_is_path():
    ns = parse_args(["--lat", "32.869354", "--lon", "35.274463", "--radius-m", "500", "--out", "/tmp/teradyon"])
    assert ns.lat == pytest.approx(32.869354)
    assert ns.radius_m == 500.0
    assert ns.out == Path("/tmp/teradyon")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd /home/valentin/RL/CatSwarm/general_infrastructure && python3 -m pytest Dockerfiles/scripts/tests/test_generate_real_area.py::test_bbox_500m_is_1km_square -v`

Expected: FAIL (`ModuleNotFoundError: generate_real_area`)

- [ ] **Step 3: Write `requirements-real-area.txt`**

```text
numpy
Pillow
requests
shapely
pyproj
pytest
```

Install: `python3 -m pip install -r Dockerfiles/scripts/requirements-real-area.txt`

- [ ] **Step 4: Minimal implementation**

```python
#!/usr/bin/env python3
"""Generate a Gazebo Classic real-area model (DEM + ortho + OSM solids)."""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

from pyproj import Geod

HEIGHTMAP_N = 257
DEFAULT_BUILDING_HEIGHT_M = 8.0
METERS_PER_LEVEL = 3.0
_GEOD = Geod(ellps="WGS84")


def bbox_from_center(lat: float, lon: float, radius_m: float) -> tuple[float, float, float, float]:
    """Square: center ± radius_m east and north. Returns (south, west, north, east)."""
    _n_lon, north, _ = _GEOD.fwd(lon, lat, 0.0, radius_m)
    _s_lon, south, _ = _GEOD.fwd(lon, lat, 180.0, radius_m)
    east, _e_lat, _ = _GEOD.fwd(lon, lat, 90.0, radius_m)
    west, _w_lat, _ = _GEOD.fwd(lon, lat, 270.0, radius_m)
    return south, west, north, east


def building_height_m(tags: dict[str, str]) -> float:
    h = tags.get("height")
    if h:
        try:
            return float(str(h).split()[0])
        except ValueError:
            pass
    levels = tags.get("building:levels")
    if levels:
        try:
            return float(levels) * METERS_PER_LEVEL
        except ValueError:
            pass
    return DEFAULT_BUILDING_HEIGHT_M


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Generate a Gazebo Classic real-area world")
    p.add_argument("--lat", type=float, required=True)
    p.add_argument("--lon", type=float, required=True)
    p.add_argument("--radius-m", type=float, required=True)
    p.add_argument("--out", type=Path, required=True)
    return p.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    try:
        ns = parse_args(argv)
    except SystemExit:
        return 2
    if not math.isfinite(ns.lat) or not math.isfinite(ns.lon) or not math.isfinite(ns.radius_m):
        print("lat/lon/radius-m must be finite", file=sys.stderr)
        return 2
    if not -90.0 <= ns.lat <= 90.0 or not -180.0 <= ns.lon <= 180.0 or ns.radius_m <= 0:
        print("lat [-90,90], lon [-180,180], radius-m > 0", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

`parse_args` uses argparse `required=True`, so `main([])` must catch `SystemExit`. Do **not** call `generate()` yet (Task 4).

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd /home/valentin/RL/CatSwarm/general_infrastructure && python3 -m pytest Dockerfiles/scripts/tests/test_generate_real_area.py -v`

Expected: PASS (all Task 1 tests)

- [ ] **Step 6: Do not commit**

---

### Task 2: Heightmap, origin.json, world XML

**Files:**
- Modify: `Dockerfiles/scripts/generate_real_area.py`
- Modify: `Dockerfiles/scripts/tests/test_generate_real_area.py`

**Interfaces:**
- Consumes: `HEIGHTMAP_N`, `bbox_from_center`
- Produces:
  - `enu_to_wgs84(lat0, lon0, east_m, north_m) -> tuple[float, float]`
  - `wgs84_to_enu(lat0, lon0, lat, lon) -> tuple[float, float]`
  - `encode_heightmap(dem_amsl: numpy.ndarray, origin_amsl: float) -> tuple[numpy.ndarray, float]`
    - uint8 (N,N); `z_range` = max(dem)−min(dem) (minimum 1.0 m if flat)
    - pixel 0 = min(dem); pixel 255 = max(dem)
    - origin ground Gazebo z = `origin_amsl - min(dem)` mapped through that scale (assert ≈ 0 when origin is min, else the encoded value at center corresponds to local z = origin−min)
  - `local_z_from_amsl(amsl: float, dem_min: float, z_range: float) -> float` = `amsl - dem_min` (Gazebo heightmap maps 0..z_range)
  - `write_origin_json(path: Path, lat, lon, alt_amsl, radius_m) -> None` keys exactly `lat, lon, alt_amsl, radius_m, size_m`
  - `write_world_file(path: Path, name: str, lat, lon, alt_amsl) -> None`
    - no `ground_plane`; includes `model://<name>`; `<spherical_coordinates>` as spec

Heightmap SDF later (Task 4) uses `<size>size_m size_m z_range</size>` and `<pos>0 0 0</pos>` so Gazebo z = AMSL − dem_min. Origin local z = `origin_amsl - dem_min`. Spec says origin ground z ≈ 0: **shift DEM by subtracting origin_amsl** so the center sample is 0 and `<pos>0 0 0</pos>` puts origin on z=0. Lock this:

- `dem_local = dem_amsl - origin_amsl` (center ≈ 0; valleys negative)
- Gazebo heightmaps dislike negative heights: offset by `-min(dem_local)` so all ≥ 0, then `<pos>0 0 min(dem_local)</pos>` i.e. `pos_z = min(dem_local)` which is ≤ 0. Center z = 0.

`encode_heightmap` returns `(png_u8, size_z, pos_z)` where `size_z = max(dem_local)-min(dem_local)` (floor 1.0), `pos_z = min(dem_local)`.

- [ ] **Step 1: Write the failing tests** (append to test file)

```python
import json
import numpy as np
from generate_real_area import encode_heightmap, write_origin_json, write_world_file, wgs84_to_enu

def test_encode_heightmap_origin_is_z0():
    dem = np.array([[190.0, 200.0], [200.0, 210.0]])
    u8, size_z, pos_z = encode_heightmap(dem, origin_amsl=200.0)
    assert u8.dtype == np.uint8
    # local = dem-200 → [-10,0; 0,10]; shift +10 → [0,10; 10,20]; pos_z = -10
    assert pos_z == pytest.approx(-10.0)
    assert size_z == pytest.approx(20.0)
    center_local = 0.0  # origin
    gazebo_z = pos_z + (u8[0, 1] / 255.0) * size_z  # if origin is dem[0,1]=200
    # Don't assume index; compute gazebo z at the origin sample
    # After shift, origin sample value 10/20*255
    origin_u8 = int(round((0.0 - pos_z) / size_z * 255))
    gazebo_z = pos_z + origin_u8 / 255.0 * size_z
    assert gazebo_z == pytest.approx(0.0, abs=0.15)

def test_write_origin_json_keys(tmp_path):
    p = tmp_path / "origin.json"
    write_origin_json(p, 32.869354, 35.274463, 245.1, 500.0)
    data = json.loads(p.read_text())
    assert set(data) == {"lat", "lon", "alt_amsl", "radius_m", "size_m"}
    assert data["size_m"] == 1000.0
    assert data["alt_amsl"] == pytest.approx(245.1)

def test_world_has_spherical_and_no_ground_plane(tmp_path):
    p = tmp_path / "teradyon.world"
    write_world_file(p, "teradyon", 32.869354, 35.274463, 245.1)
    xml = p.read_text()
    assert "ground_plane" not in xml
    assert "<latitude_deg>32.869354</latitude_deg>" in xml
    assert "<longitude_deg>35.274463</longitude_deg>" in xml
    assert "<elevation>245.1</elevation>" in xml
    assert "model://teradyon" in xml
    assert "<heading_deg>0</heading_deg>" in xml
    assert "EARTH_WGS84" in xml

def test_wgs84_to_enu_origin_is_zero():
    e, n = wgs84_to_enu(32.869354, 35.274463, 32.869354, 35.274463)
    assert e == pytest.approx(0.0, abs=0.05)
    assert n == pytest.approx(0.0, abs=0.05)
```

- [ ] **Step 2: Run to verify fail**

Run: `python3 -m pytest Dockerfiles/scripts/tests/test_generate_real_area.py::test_world_has_spherical_and_no_ground_plane -v`

Expected: FAIL (`ImportError` or `not defined`)

- [ ] **Step 3: Implement**

Use `pyproj.Proj(proj="aeqd", lat_0=lat0, lon_0=lon0, ellps="WGS84")` for ENU.

`write_world_file` template (physics can be the short default; sun include required):

```xml
<?xml version="1.0" ?>
<sdf version="1.6">
  <world name="NAME">
    <spherical_coordinates>
      <surface_model>EARTH_WGS84</surface_model>
      <latitude_deg>LAT</latitude_deg>
      <longitude_deg>LON</longitude_deg>
      <elevation>ALT</elevation>
      <heading_deg>0</heading_deg>
    </spherical_coordinates>
    <include><uri>model://sun</uri></include>
    <include><uri>model://NAME</uri></include>
  </world>
</sdf>
```

`encode_heightmap`: bilinear-resample callers pass already 257×257; this function only encodes values, does not resize. If `dem_amsl` shape != (N,N), still encode as given (Task 4 resamples to 257). For the 2×2 test, do not require N=257.

```python
def encode_heightmap(dem_amsl: np.ndarray, origin_amsl: float) -> tuple[np.ndarray, float, float]:
    dem_local = np.asarray(dem_amsl, dtype=np.float64) - origin_amsl
    zmin = float(np.min(dem_local))
    zmax = float(np.max(dem_local))
    size_z = max(zmax - zmin, 1.0)
    pos_z = zmin
    u8 = np.clip(np.rint((dem_local - zmin) / size_z * 255.0), 0, 255).astype(np.uint8)
    return u8, size_z, pos_z
```

- [ ] **Step 4: Run tests PASS**

Run: `python3 -m pytest Dockerfiles/scripts/tests/test_generate_real_area.py -v`

- [ ] **Step 5: Do not commit**

---

### Task 3: OSM parse + DAE extrusion

**Files:**
- Create: `Dockerfiles/scripts/tests/fixtures/sample.osm.xml`
- Modify: `generate_real_area.py`
- Modify: `test_generate_real_area.py`

**Interfaces:**
- Consumes: `building_height_m`, `wgs84_to_enu`
- Produces:
  - `OsmSolid` dataclass: `kind: str` (`"building"|"bridge"`), `footprint_enu: list[tuple[float,float]]` (east, north), `height_m: float`
  - `parse_osm_xml(xml: str, lat0: float, lon0: float) -> list[OsmSolid]`
    - `building=*` closed ways / relations with `type=multipolygon` outer
    - `bridge=yes` or `man_made=bridge` ways with ≥2 nodes: expand to a 4 m wide rectangle along the way (skip if <2 nodes)
    - skip footprints with <3 unique vertices or zero area (shapely)
  - `write_buildings_dae(path: Path, solids: list[OsmSolid], dem_amsl_fn) -> None`
    - `dem_amsl_fn(east: float, north_m: float) -> float` AMSL at centroid
    - `base_z = amsl(centroid) - origin_amsl` passed in via a callable that already returns **local z** (Gazebo), so signature: `local_z_fn(east, north) -> float`
    - prism: footprint at `z=local_z`, top at `local_z+height_m`
    - omit file if `solids` empty (caller must not call, or write_buildings_dae is no-op if empty — **if solids empty, do not write the file**)

Fixture OSM: one way `building=yes height=12`, one way `building=yes building:levels=2`, one `bridge=yes` way of 2 nodes, one open 2-node building (degenerate, skipped).

- [ ] **Step 1: Write fixture + failing tests**

`sample.osm.xml`: standard OSM XML 0.6 with node ids and ways. Place nodes around 32.869354, 35.274463 so ENU is tens of meters, not zero-area.

```python
def test_parse_osm_heights_and_skip_degenerate():
    xml = Path(__file__).parent.joinpath("fixtures/sample.osm.xml").read_text()
    solids = parse_osm_xml(xml, 32.869354, 35.274463)
    heights = sorted(s.height_m for s in solids if s.kind == "building")
    assert 12.0 in heights
    assert 6.0 in heights  # 2 levels * 3
    assert any(s.kind == "bridge" for s in solids)
    assert all(len(s.footprint_enu) >= 3 for s in solids)

def test_write_dae_skipped_when_empty(tmp_path):
    p = tmp_path / "buildings.dae"
    write_buildings_dae(p, [], lambda e, n: 0.0)
    assert not p.exists()

def test_write_dae_has_geometry(tmp_path):
    solids = parse_osm_xml(Path(__file__).parent.joinpath("fixtures/sample.osm.xml").read_text(), 32.869354, 35.274463)
    p = tmp_path / "buildings.dae"
    write_buildings_dae(p, solids, lambda e, n: 0.0)
    text = p.read_text()
    assert "<COLLADA" in text
    assert "<triangles" in text or "<polylist" in text or "<float_array" in text
```

- [ ] **Step 2: Run to verify fail**

Run: `python3 -m pytest Dockerfiles/scripts/tests/test_generate_real_area.py::test_parse_osm_heights_and_skip_degenerate -v`

Expected: FAIL

- [ ] **Step 3: Implement parse + DAE writer**

Parse with `xml.etree.ElementTree`. COLLADA 1.4.1, Z_UP, one mesh combining all solids (triangle list). Use shapely `Polygon` + `shapely.ops.triangulate` or earcut via fan triangulation **only if the polygon is convex**; otherwise `shapely.geometry.polygon.orient` + `shapely.ops.triangulate`.

Bridge width: 4.0 m. Bridge default height (deck thickness) 1.0 m if no `height` tag.

- [ ] **Step 4: Run tests PASS**

- [ ] **Step 5: Do not commit**

---

### Task 4: `generate()` with injectable HTTP + atomic replace

**Files:**
- Modify: `generate_real_area.py`
- Modify: `test_generate_real_area.py`

**Interfaces:**
- Consumes: all previous functions
- Produces:
  - `HttpGet = Callable[[str], bytes]`
  - `default_http_get(url: str) -> bytes` — `requests.get(..., timeout=60, headers={"User-Agent": "CatSwarm-real-area/1.0 (research)"}).raise_for_status(); return content`
  - `TERRARIUM_URL = "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png"`
  - `ESRI_URL = "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"`
  - `OVERPASS_URL = "https://overpass-api.de/api/interpreter"`
  - `generate(lat: float, lon: float, radius_m: float, out: Path, http_get: HttpGet | None = None) -> None`
  - `main` calls `generate` after validation (return 1 on exception, print traceback to stderr)

`generate` algorithm:

1. `name = out.name`; `size_m = 2 * radius_m`; `tmp = Path(str(out) + ".generating")`; `shutil.rmtree(tmp, ignore_errors=True)`; `tmp.mkdir(parents=True)`; `(tmp / "media").mkdir()`
2. `south,west,north,east = bbox_from_center(...)`
3. Mosaic DEM at zoom 15 over bbox into float AMSL array, resample to `(HEIGHTMAP_N, HEIGHTMAP_N)` with numpy. Terrarium decode: `(R * 256 + G + B/256) - 32768`.
4. `origin_amsl =` sample DEM at center (array center pixel).
5. Mosaic Esri z=18 into `ortho.png` (RGB), covering the square.
6. POST or GET Overpass: buildings + bridges in bbox. Parse. `local_z_fn` interpolates DEM local z = `amsl - origin_amsl` (same as encode). Write DAE if solids else skip.
7. `encode_heightmap`; save `media/elevation.png` (Pillow `L` mode).
8. `write_model_sdf`, `write_world_file`, `write_origin_json`, `model.config`.
9. If `out.exists()`: `old = Path(str(out) + ".old")`; `shutil.rmtree(old, ignore_errors=True)`; `out.rename(old)`
10. `tmp.rename(out)`; `shutil.rmtree(old, ignore_errors=True)`
11. On any exception: `shutil.rmtree(tmp, ignore_errors=True)`; do **not** delete `out`; re-raise

`write_model_sdf(path, name, size_m, size_z, pos_z, has_buildings: bool)`:

- static model `name`
- heightmap visual+collision: uri `model://{name}/media/elevation.png`, `<size>{size_m} {size_m} {size_z}</size>`, `<pos>0 0 {pos_z}</pos>`
- **two** textures (Gazebo Classic): both `model://{name}/media/ortho.png`, size `size_m`; one blend `min_height={size_z+1}` `fade_dist=1` so ortho covers all
- buildings link only if `has_buildings`: mesh `model://{name}/media/buildings.dae`

`model.config`: name, sdf 1.5 `model.sdf`, description "Generated real-area heightmap"

Overpass query (data=):

```
[out:xml][timeout:60];
(
  way["building"](south,west,north,east);
  relation["building"](south,west,north,east);
  way["bridge"="yes"](south,west,north,east);
  way["man_made"="bridge"](south,west,north,east);
);
(._;>;);
out body;
```

Use GET `OVERPASS_URL + "?data=" + quote(query)`.

- [ ] **Step 1: Failing tests**

Provide `fake_http_get(url: str) -> bytes` in the test file:

- if `"overpass"` in url: return fixture OSM XML
- if `"terrarium"` in url or `"elevation-tiles"` in url: 256×256 PNG, all pixels RGB = terrarium encoding of 200 m (`v=200+32768`; R=v//256, G=v%256, B=0)
- if `"World_Imagery"` in url or `"arcgisonline"` in url: 256×256 RGB orange PNG
- else: raise `RuntimeError(url)`

```python
def test_generate_layout_mocked(tmp_path):
    out = tmp_path / "teradyon"
    generate(32.869354, 35.274463, 500.0, out, http_get=fake_http_get)
    assert (out / "model.config").is_file()
    assert (out / "model.sdf").is_file()
    assert (out / "teradyon.world").is_file()
    assert (out / "origin.json").is_file()
    assert (out / "media" / "elevation.png").is_file()
    assert (out / "media" / "ortho.png").is_file()
    from PIL import Image
    im = Image.open(out / "media" / "elevation.png")
    assert im.size == (257, 257)
    origin = json.loads((out / "origin.json").read_text())
    assert origin["lat"] == pytest.approx(32.869354)
    assert origin["size_m"] == 1000.0
    sdf = (out / "model.sdf").read_text()
    assert "elevation.png" in sdf
    assert "ortho.png" in sdf

def test_generate_http_failure_leaves_existing(tmp_path):
    out = tmp_path / "teradyon"
    generate(32.869354, 35.274463, 500.0, out, http_get=fake_http_get)
    marker = out / "origin.json"
    old = marker.read_text()
    def boom(url: str) -> bytes:
        raise RuntimeError("network down")
    with pytest.raises(Exception):
        generate(32.869354, 35.274463, 500.0, out, http_get=boom)
    assert marker.read_text() == old
    assert not Path(str(out) + ".generating").exists()

def test_main_generate_mocked(tmp_path, monkeypatch):
    import generate_real_area as g
    monkeypatch.setattr(g, "default_http_get", fake_http_get)
    out = tmp_path / "site"
    rc = main(["--lat", "32.869354", "--lon", "35.274463", "--radius-m", "500", "--out", str(out)])
    assert rc == 0
    assert (out / "site.world").is_file()
```

- [ ] **Step 2: Run to verify fail**

Run: `python3 -m pytest Dockerfiles/scripts/tests/test_generate_real_area.py::test_generate_layout_mocked -v`

Expected: FAIL (`generate` not defined)

- [ ] **Step 3: Implement mosaic + generate + wire main**

Tile math: Web Mercator `lon/lat → xtile, ytile` at zoom. Loop x,y covering bbox, fetch, stitch, crop to bbox, resize.

If Overpass returns 0 solids: no `buildings.dae`, no buildings link.

- [ ] **Step 4: Run tests PASS**

Run: `python3 -m pytest Dockerfiles/scripts/tests/test_generate_real_area.py -v`

Expected: PASS

- [ ] **Step 5: Do not commit**

---

### Task 5: Docker volume + `--world` + `GAZEBO_MODEL_PATH`

**Files:**
- Modify: `general_infrastructure/multidrone/sitl_multiple_run.sh` (immediately after line 145 `source ... setup_gazebo.bash`)
- Modify: `general_infrastructure/runSimNoeticMulti.sh` (defaults ~41–43, help ~48–58, parse loop ~46–91, `DOCKER_VOLUMES` ~123–144, `docker run` ~157–169)
- Create: `general_infrastructure/multidrone/tests/test_real_area_sim_scripts.py`

**Interfaces:**
- Consumes: `origin.json` keys from Task 2
- Produces: `--world NAME` on `runSimNoeticMulti.sh` (default `empty`); host models mounted at `.../models/catswarm_host`; `-w ${WORLD}` passed to `sitl_multiple_run2.sh`

- [ ] **Step 1: Write the failing tests**

```python
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SITL = ROOT / "multidrone" / "sitl_multiple_run.sh"
RUN = ROOT / "runSimNoeticMulti.sh"

def test_sitl_appends_catswarm_host_after_setup():
    text = SITL.read_text()
    i_src = text.index("setup_gazebo.bash")
    i_host = text.index("models/catswarm_host")
    assert i_src < i_host
    assert "GAZEBO_MODEL_PATH" in text

def test_runsim_help_and_world_flag():
    import subprocess
    out = subprocess.check_output(["bash", str(RUN), "--help"], text=True)
    assert "--world" in out

def test_runsim_missing_world_exits_before_docker(tmp_path):
    import subprocess
    proc = subprocess.run(
        ["bash", str(RUN), "--world", "definitely_missing_world_xyz", "--num", "1"],
        cwd=str(ROOT), capture_output=True, text=True, timeout=15,
    )
    assert proc.returncode != 0
    assert "generate_real_area.py" in (proc.stdout + proc.stderr)
```

Note: `--help` currently exits 0 *inside* the parse loop before docker. After adding `--world`, `--help` must still work. For missing world, check files **after** parse, **before** `trap cleanup_on_exit` / `docker run`. If current script always `trap cleanup` then `cleanup_on_exit` (kills gazebo!) at start — keep that behavior, but missing-world exit must happen **after** parse and **without** requiring docker. Place the world-file check immediately after the parse loop, **before** the initial `cleanup_on_exit` call, so a bad `--world` does not kill a running sim. Tests depend on that.

- [ ] **Step 2: Run to verify fail**

Run: `python3 -m pytest general_infrastructure/multidrone/tests/test_real_area_sim_scripts.py -v` from CatSwarm root **or** `cd general_infrastructure && python3 -m pytest multidrone/tests/test_real_area_sim_scripts.py -v`

Expected: FAIL (`catswarm_host` not found / `--world` not in help)

- [ ] **Step 3: Implement sitl_multiple_run.sh**

Right after `source ${src_path}/.../setup_gazebo.bash ...`:

```bash
export GAZEBO_MODEL_PATH="${GAZEBO_MODEL_PATH}:/home/valentin/PX4-Autopilot/Tools/simulation/gazebo-classic/sitl_gazebo-classic/models/catswarm_host"
```

- [ ] **Step 4: Implement runSimNoeticMulti.sh**

Default: `WORLD=empty`

Help line: `  --world=NAME, --world NAME  Gazebo world (default: empty). Host maps in Dockerfiles/models/NAME/`

Parse:

```bash
        --world=*)
            WORLD="${1#*=}"
            shift
            ;;
        --world)
            WORLD="$2"
            shift 2
            ;;
```

After parse, if `WORLD` is not `empty`:

```bash
HOST_MODELS="${SCRIPT_DIR}/Dockerfiles/models"
WORLD_FILE="${HOST_MODELS}/${WORLD}/${WORLD}.world"
ORIGIN_FILE="${HOST_MODELS}/${WORLD}/origin.json"
if [[ ! -f "$WORLD_FILE" || ! -f "$ORIGIN_FILE" ]]; then
    echo "World '${WORLD}' not found (need ${WORLD_FILE} and origin.json)."
    echo "Generate it first, e.g.:"
    echo "  python3 ${SCRIPT_DIR}/Dockerfiles/scripts/generate_real_area.py --lat 32.869354 --lon 35.274463 --radius-m 500 --out ${SCRIPT_DIR}/Dockerfiles/models/teradyon"
    exit 1
fi
PX4_HOME_LAT=$(python3 -c "import json; print(json.load(open('${ORIGIN_FILE}'))['lat'])")
PX4_HOME_LON=$(python3 -c "import json; print(json.load(open('${ORIGIN_FILE}'))['lon'])")
PX4_HOME_ALT=$(python3 -c "import json; print(json.load(open('${ORIGIN_FILE}'))['alt_amsl'])")
```

Always add to **both** `DOCKER_VOLUMES` arrays:

```bash
--volume="${SCRIPT_DIR}/Dockerfiles/models:/home/valentin/PX4-Autopilot/Tools/simulation/gazebo-classic/sitl_gazebo-classic/models/catswarm_host:ro"
```

If not empty, also:

```bash
--volume="${WORLD_FILE}:/home/valentin/PX4-Autopilot/Tools/simulation/gazebo-classic/sitl_gazebo-classic/worlds/${WORLD}.world:ro"
```

`docker run` extra env when not empty:

```bash
--env="PX4_HOME_LAT=${PX4_HOME_LAT}" \
--env="PX4_HOME_LON=${PX4_HOME_LON}" \
--env="PX4_HOME_ALT=${PX4_HOME_ALT}" \
```

Inner command always pass `-w`:

```bash
/bin/bash -c "./Tools/simulation/gazebo-classic/sitl_multiple_run2.sh -p ${CONTAINER_POSITIONS_PATH} -n ${NUM_DRONES} -w ${WORLD}"
```

- [ ] **Step 5: Run tests PASS**

Run: `cd /home/valentin/RL/CatSwarm/general_infrastructure && python3 -m pytest multidrone/tests/test_real_area_sim_scripts.py -v`

Expected: PASS. `--help` must not trigger the missing-world check (help exits inside the case).

- [ ] **Step 6: Do not commit**

---

### Task 6: GUI server world list + start validation

**Files:**
- Create: `GUI/server/src/worlds.ts`
- Create: `GUI/server/src/worlds.test.ts`
- Modify: `GUI/server/src/index.ts` (`PROJECT_ROOT` already ~line 27; add GET; change POST `/api/sim/start` ~311–343)

**Interfaces:**
- Consumes: disk layout from Task 4 (`NAME/NAME.world`, `origin.json`)
- Produces:
  - `export type HostWorld = { name: string; label: string }`
  - `export function modelsDir(projectRoot: string): string`
  - `export const TERADYON_GENERATOR_HINT: string` (exact generator command from spec)
  - `export function listHostWorlds(modelsRoot: string): HostWorld[]`
  - `export function validateWorld(world: string, modelsRoot: string): string | null` (`null` = ok)

- [ ] **Step 1: Write failing tests** `worlds.test.ts`

```typescript
import assert from 'assert';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { listHostWorlds, modelsDir, validateWorld, TERADYON_GENERATOR_HINT } from './worlds';

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'cs-worlds-'));
const a = path.join(tmp, 'teradyon');
fs.mkdirSync(a);
fs.writeFileSync(path.join(a, 'teradyon.world'), '<sdf/>');
fs.writeFileSync(path.join(a, 'origin.json'), '{}');
fs.mkdirSync(path.join(tmp, 'yosemite'));
fs.writeFileSync(path.join(tmp, 'yosemite', 'model.config'), '');

const listed = listHostWorlds(tmp);
assert.deepStrictEqual(listed.map((w) => w.name), ['teradyon']);
assert.strictEqual(validateWorld('empty', tmp), null);
assert.strictEqual(validateWorld('', tmp), null);
assert.ok(validateWorld('teradyon', tmp) === null);
const err = validateWorld('nope', tmp);
assert.ok(err && err.includes('generate_real_area.py'));
assert.ok(TERADYON_GENERATOR_HINT.includes('32.869354'));
assert.ok(modelsDir('/catswarm').endsWith('general_infrastructure/Dockerfiles/models'));
fs.rmSync(tmp, { recursive: true });
console.log('worlds.test.ts ok');
```

- [ ] **Step 2: Run to verify fail**

Run: `cd /home/valentin/RL/CatSwarm/GUI/server && npx ts-node --transpile-only src/worlds.test.ts`

Expected: FAIL (cannot find `./worlds`)

- [ ] **Step 3: Implement `worlds.ts`**

```typescript
import fs from 'fs';
import path from 'path';

export type HostWorld = { name: string; label: string };

export const TERADYON_GENERATOR_HINT =
    'python3 general_infrastructure/Dockerfiles/scripts/generate_real_area.py --lat 32.869354 --lon 35.274463 --radius-m 500 --out general_infrastructure/Dockerfiles/models/teradyon';

export function modelsDir(projectRoot: string): string {
    return path.join(projectRoot, 'general_infrastructure/Dockerfiles/models');
}

export function listHostWorlds(modelsRoot: string): HostWorld[] {
    if (!fs.existsSync(modelsRoot)) return [];
    const names = fs.readdirSync(modelsRoot, { withFileTypes: true })
        .filter((d) => d.isDirectory())
        .map((d) => d.name)
        .filter((name) => fs.existsSync(path.join(modelsRoot, name, `${name}.world`)))
        .sort();
    return names.map((name) => ({ name, label: name }));
}

export function validateWorld(world: string, modelsRoot: string): string | null {
    if (!world || world === 'empty') return null;
    if (!/^[A-Za-z0-9_-]+$/.test(world)) return `Invalid world name`;
    const worldFile = path.join(modelsRoot, world, `${world}.world`);
    const origin = path.join(modelsRoot, world, 'origin.json');
    if (!fs.existsSync(worldFile) || !fs.existsSync(origin)) {
        return `World '${world}' is missing. Generate it first, e.g.: ${TERADYON_GENERATOR_HINT}`;
    }
    return null;
}
```

- [ ] **Step 4: Wire `index.ts`**

`GET /api/sim/worlds` → `{ worlds: [{ name: 'empty', label: 'Empty' }, ...listHostWorlds(modelsDir(PROJECT_ROOT))] }`

In `POST /api/sim/start`, read `world` from body default `'empty'`. `const werr = validateWorld(String(world), modelsDir(PROJECT_ROOT)); if (werr) return res.status(400).json({ error: werr });`

Change send line to:

```typescript
const worldArg = (!world || world === 'empty') ? 'empty' : String(world);
await tmux.sendToTmux(TMUX_SESSION, `${scriptPath} --num ${droneCount} --file ${positionsPath} --world ${worldArg}`);
```

- [ ] **Step 5: Run tests PASS**

Run: `cd /home/valentin/RL/CatSwarm/GUI/server && npx ts-node --transpile-only src/worlds.test.ts`

Expected: `worlds.test.ts ok`

- [ ] **Step 6: Do not commit**

---

### Task 7: GUI World dropdown

**Files:**
- Modify: `GUI/client/src/components/TopController.tsx` (props ~4–17, drone dropdown block ~43–117 — add a sibling World control)
- Modify: `GUI/client/src/App.tsx` (state + localStorage ~16–90, `handleStartSim` body ~276–279, `<TopController` ~504–517)

**Interfaces:**
- Consumes: `GET /api/sim/worlds` `{ worlds: { name, label }[] }`; `POST /api/sim/start` field `world: string`
- Produces: `catswarm_world` in localStorage; dropdown disabled when `isSimRunning`

No new frontend test runner (spec).

- [ ] **Step 1: Extend TopController props**

```typescript
    world: string;
    setWorld: (world: string) => void;
    worldOptions: { name: string; label: string }[];
```

Add `isWorldDropdownOpen` state. Place a **World:** control immediately to the right of the Drones dropdown (same visual pattern, wider ~140px). Options from `worldOptions`. Clicking a row calls `setWorld(name)` and closes. `pointerEvents`/opacity follow `isSimRunning` like drone count.

- [ ] **Step 2: App.tsx state**

```typescript
  const [world, setWorld] = useState(() => localStorage.getItem('catswarm_world') || 'empty');
  const [worldOptions, setWorldOptions] = useState<{ name: string; label: string }[]>([
    { name: 'empty', label: 'Empty' },
  ]);
```

`useEffect` persist `catswarm_world`. On mount fetch `${SERVER_URL}/api/sim/worlds` and `setWorldOptions(data.worlds)` if array. If current `world` is not in the list, `setWorld('empty')`.

Start body:

```typescript
body: JSON.stringify({ droneCount, missionFiles, positions: dronePositions, world })
```

Pass new props into `TopController`.

- [ ] **Step 3: Manual check (no browser required for this task’s gate)**

With backend running: `curl -s http://localhost:3001/api/sim/worlds` returns Empty plus any generated maps.

If the GUI is already up, restart the frontend (`./attach.sh`) so the dropdown appears.

- [ ] **Step 4: Do not commit**

---

### Task 8: Docs + gitignore + spec status

**Files:**
- Modify: `general_infrastructure/Dockerfiles/README.md` (Noetic section ~76–87)
- Modify: `general_infrastructure/Dockerfiles/UPDATES.md` (new top entry)
- Modify: `general_infrastructure/UPDATES.md` (new top entry)
- Modify: `GUI/UPDATES.md` (bump **1.14.0** world dropdown)
- Modify: `GUI/README.md` Features list — one bullet: world dropdown Empty vs host maps under `Dockerfiles/models`
- Modify: spec status line to `approved`
- Modify: `general_infrastructure/Dockerfiles/.gitignore` or create if missing: ignore generated rasters only

- [ ] **Step 1: gitignore inside Dockerfiles repo** (do not ignore `ksql_airport/media/*.DAE`)

```
# generated real-area rasters/meshes
models/**/media/elevation.png
models/**/media/ortho.png
models/**/media/buildings.dae
models/**/*.generating/
models/**/*.old/
```

- [ ] **Step 2: README Noetic subsection** — generator CLI, Teradyon example, `--volume` to `models/catswarm_host`, attribution:

  - Imagery: Esri World Imagery
  - DEM: AWS Terrain / Terrarium tiles
  - Buildings: OpenStreetMap ODbL

- [ ] **Step 3: UPDATES entries** as listed above. GUI feature bump `1.13.5` → `1.14.0`.

- [ ] **Step 4: Do not commit**

---

## Self-review

**Spec coverage**

| Spec item | Task |
|-----------|------|
| Generic CLI `--lat --lon --radius-m --out` | 1, 4 |
| 500 m → 1 km square; 257 heightmap | 1, 2, 4 |
| origin.json keys; spherical_coordinates; no ground_plane | 2, 4 |
| OSM height / levels×3 / 8 m; bridges; empty OSM ok | 3, 4 |
| Atomic write; injectable HTTP; fixture tests | 4 |
| `Dockerfiles/models` + `--volume` catswarm_host; do not overlay iris | 5 |
| `GAZEBO_MODEL_PATH` after setup_gazebo.bash | 5 |
| `--world`; PX4_HOME from origin.json; empty unchanged | 5 |
| GUI dropdown; GET worlds; start 400 + generator hint | 6, 7 |
| Docs + attribution | 8 |
| No generator from GUI; no photoreal; no Dockerfile COPY | all |

**Placeholders:** none.

**Types:** `HttpGet`, `OsmSolid`, `HostWorld`, `origin.json` keys, `--world` name = directory basename — consistent across tasks.

**Optional smoke (not a gate):** after Task 4, on a machine with network:

```bash
python3 general_infrastructure/Dockerfiles/scripts/generate_real_area.py \
  --lat 32.869354 --lon 35.274463 --radius-m 500 \
  --out general_infrastructure/Dockerfiles/models/teradyon
```

Then Start Sim with World = teradyon. If Overpass/Esri/Terrarium fail, the unit suite still stands.
