# Real-area Gazebo Classic world (image + DEM + OSM)

Date: 2026-09-11  
Status: approved

## Goal

Add a host-side, generic generator that turns a lat/lon + radius into a Gazebo Classic world (satellite ortho, heightmap terrain, OSM-extruded buildings/bridges), store that world under `Dockerfiles/models/`, inject it into the existing Noetic PX4 SITL container with `--volume`, and let the CatSwarm GUI pick **Empty** vs any generated host world. First baked site: Teradyon industrial park.

## Decisions (locked)

| Topic | Choice |
|--------|--------|
| Sim stack | Existing **Gazebo Classic** Noetic image (`px4-noetic-sim-ros`). No Jetty / Cesium / Unreal. |
| Approach | Host Python generator + bind-mount. Do **not** `COPY` maps into the Dockerfile. |
| Generator path | `general_infrastructure/Dockerfiles/scripts/generate_real_area.py` |
| CLI | `--lat --lon --radius-m --out` (generic; Teradyon is one invocation, not a special case) |
| Map path | `general_infrastructure/Dockerfiles/models/<name>/` (`<name>` = basename of `--out`) |
| Injection | `runSimNoeticMulti.sh` `--volume` of the whole `Dockerfiles/models` dir plus the chosen `.world` file |
| First site | Center **32.869354, 35.274463** (Katom / Teradyon industrial park), **500 m radius** → **1000 m × 1000 m** square |
| Objects | OSM footprints extruded to solids (`building=*`, `bridge=yes`). Boxy, collidable. |
| GUI v1 | Dropdown: **Empty** + every host model dir that contains `<name>.world`. Does **not** run the generator. |
| GPS | World `<spherical_coordinates>` + `PX4_HOME_LAT/LON/ALT` from generator `origin.json`. Empty world does not set `PX4_HOME_*`. |
| Tests | Pytest fixtures only; no live DEM/imagery/Overpass. |
| Git | Do not commit unless explicitly asked. Do not assume generated `media/` is in git. |

## Non-goals (v1)

- In-GUI location picker or calling the generator from Start Sim
- Photorealistic 3D tiles / textured building meshes
- Overlaying or replacing PX4’s in-image `models/` (iris must stay)
- Changing the Empty world
- Noble / Gazebo Jetty / FlightGear
- Auto-download on Start Sim
- `.csm` persistence of world choice (localStorage only)

## Generator

### CLI

```bash
python3 general_infrastructure/Dockerfiles/scripts/generate_real_area.py \
  --lat 32.869354 --lon 35.274463 --radius-m 500 \
  --out general_infrastructure/Dockerfiles/models/teradyon
```

- `--lat`, `--lon`: WGS84 decimal degrees. Non-finite or out of range → exit 2.
- `--radius-m`: half-width of a square in local meters. `500` → bbox center ±500 m east and north (1000 m side). Must be `> 0`.
- `--out`: destination **model directory**. Created if missing. Model name and `*.world` stem = `Path(out).name` (e.g. `teradyon`).
- Missing required args → usage on stderr, exit 2.

Host-only (not inside the sim container). Dependencies listed in `Dockerfiles/scripts/requirements-real-area.txt`: `numpy`, `Pillow`, `requests`, `shapely`, `pyproj`. No GDAL required: ~30 m DEM via **AWS Terrarium** tiles (Copernicus GLO-30-class equivalent). Imagery: **Esri World Imagery** tiles (zoom 18). OSM via **Overpass**. Attribution for Esri + OSM + DEM goes in `Dockerfiles/README.md`.

### Output layout

```text
Dockerfiles/models/<name>/
  model.config
  model.sdf                 # static heightmap + one buildings/bridges mesh
  <name>.world              # no ground_plane; includes model://<name>
  origin.json
  media/
    elevation.png           # 257×257, 8-bit grayscale heightmap
    ortho.png               # ortho covering the same square
    buildings.dae          # combined extruded mesh; omit file and buildings link if OSM is empty
```

`origin.json` (exact keys):

```json
{
  "lat": 32.869354,
  "lon": 35.274463,
  "alt_amsl": 245.1,
  "radius_m": 500,
  "size_m": 1000
}
```

`alt_amsl` is DEM elevation at the center in meters (example value above is illustrative). `size_m` is always `2 * radius_m`.

### Geometry

- Local frame: ENU meters, origin = requested lat/lon. +X east, +Y north, heading 0.
- Heightmap size **257×257** (`2^n+1`). `<size>` in SDF is `size_m size_m (z_max - z_min)` of the patch.
- Shift so **ground at the origin is Gazebo z = 0** (iris spawn z ≈ 0.83 still valid at the center).
- Texture `<size>` equals `size_m` so the ortho maps 1:1 (no tiling).
- `<spherical_coordinates>` in the world: `EARTH_WGS84`, requested lat/lon, `elevation` = `alt_amsl`, `heading_deg` 0.

### OSM extrusion

- Query bbox in WGS84 matching the square.
- Buildings: closed ways / multipolygons with `building=*`. Height: `height` (meters) if present; else `building:levels * 3.0`; else **8.0** m.
- Bridges: ways with `bridge=yes` (and similar `man_made=bridge`) as a thin extruded deck; skip if geometry is unusable.
- Place each solid so its base sits on the DEM at the footprint centroid (local z = DEM(centroid) − origin_amsl).
- One combined mesh in `media/buildings.dae` (same split as `ksql_airport`: heightmap link vs buildings link). Skip degenerate polygons. If OSM yields no solids: omit `buildings.dae` and the buildings link; terrain-only is valid; log a warning.

### Atomic write

Write into `<out>.generating/` then `os.replace` onto `<out>` (remove previous `<out>` only after success). Any fetch/HTTP/parse failure: non-zero exit, leave previous `<out>` intact, do not leave a half-written destination.

Fetch is a single injectable HTTP function so tests never touch the network.

## Docker injection

`runSimNoeticMulti.sh` always adds:

```text
--volume="${SCRIPT_DIR}/Dockerfiles/models:/home/valentin/PX4-Autopilot/Tools/simulation/gazebo-classic/sitl_gazebo-classic/models/catswarm_host:ro"
```

Do **not** mount over `.../sitl_gazebo-classic/models` (would hide `iris`). `setup_gazebo.bash` overwrites `GAZEBO_MODEL_PATH`, so `sitl_multiple_run.sh` (already bind-mounted from the host) **appends after that source**:

```bash
export GAZEBO_MODEL_PATH="${GAZEBO_MODEL_PATH}:/home/valentin/PX4-Autopilot/Tools/simulation/gazebo-classic/sitl_gazebo-classic/models/catswarm_host"
```

That directory is a model-path root (children are `teradyon/`, `yosemite/`, …) so `model://teradyon` resolves. Existing host maps become resolvable as a side effect; they do not appear in the GUI until they have a matching `<name>.world` in that folder.

When `--world NAME` is set and `NAME != empty`:

1. Require `Dockerfiles/models/NAME/NAME.world` and `origin.json`.
2. `--volume=.../models/NAME/NAME.world:.../sitl_gazebo-classic/worlds/NAME.world:ro`
3. Pass `-w NAME` into `sitl_multiple_run2.sh` (already supports `-w`).
4. `--env PX4_HOME_LAT/LON/ALT` from `origin.json`.

`empty`: current behavior, no `PX4_HOME_*`, no extra world mount.

New flag: `--world=NAME` / `--world NAME` (default `empty`).

## GUI (CatSwarm GUI repo)

- `TopController`: **World** dropdown next to drone count; disabled while sim is running.
- Options: `empty` (label **Empty**) plus `GET /api/sim/worlds` → `{ worlds: [{ name, label }] }` from scanning `CatSwarm/general_infrastructure/Dockerfiles/models/*/NAME.world` (`PROJECT_ROOT` already used by the GUI server).
- `POST /api/sim/start` body adds `world: string` (default `"empty"`).
- If `world !== "empty"` and the world file or `origin.json` is missing: HTTP 400, message includes the generator command with Teradyon defaults as the example.
- Persist `world` in `localStorage` (`catswarm_world`), same pattern as `catswarm_droneCount`.
- No `.csm` field in v1.

## Tests

`Dockerfiles/scripts/tests/test_generate_real_area.py` (pytest, same import style as `multidrone/tests`).

Fixtures (no network): tiny numeric DEM grid + OSM XML with (1) `height`, (2) `building:levels`, (3) a bridge, (4) a degenerate polygon.

Must fail first, then pass:

- Bbox: 500 m radius → 1000 m square around the given point.
- CLI rejects missing `--lat/--lon/--radius-m/--out`.
- Successful generate (mocked fetch) writes the layout above; heightmap is 257×257; origin ground z ≈ 0; `origin.json` and spherical coords match inputs; `alt_amsl` from the fixture DEM.
- Extrusion heights: `height` tag, else levels × 3, else 8 m; ENU poses; buildings on the DEM.
- Mocked HTTP failure: exit ≠ 0; `--out` unchanged if it already existed.

No new frontend test runner. GUI/server proof for the missing-world 400 is a small server-side check of the same validation function if it is extracted; otherwise manual Start Sim is enough for the dropdown.

## Docs

When implementation lands:

- `general_infrastructure/Dockerfiles/README.md` — generator CLI, `--volume` mounts, Esri/OSM/DEM attribution, first Teradyon command.
- `general_infrastructure/Dockerfiles/UPDATES.md` and `general_infrastructure/UPDATES.md` as appropriate.
- `GUI/UPDATES.md` — feature bump (world dropdown). `GUI/README.md` only if the architecture blurb must mention world selection.

## Success criteria

1. Generator is generic: any lat/lon/radius/`--out` produces a Gazebo Classic model directory on the host.
2. Fixture pytest suite is green.
3. `Start Sim` with Empty matches today’s behavior.
4. After the Teradyon command, GUI lists **teradyon**; Start Sim shows ortho on real terrain, OSM solids, and GPS origin **32.869354, 35.274463**.
5. Map edits do not require a Docker image rebuild.

## First demo command

```bash
python3 general_infrastructure/Dockerfiles/scripts/generate_real_area.py \
  --lat 32.869354 --lon 35.274463 --radius-m 500 \
  --out general_infrastructure/Dockerfiles/models/teradyon
```
