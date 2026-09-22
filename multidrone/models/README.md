# HIL visual models

Tracked so a fresh clone can spawn Hailo targets. Do not rely on
`models.gazebosim.org` (often unreachable) or the gitignored `city_assets/` tree.

| Model | Used by | Notes |
| ----- | ------- | ----- |
| `simple_hil_walk` | fallback walker skin (`walk.dae`) | Gazebo media copy |
| `person_standing` | `simple_hil.world` sidewalk + empty-world props | Static visual |
| `person_walking` | `simple_hil.world` sidewalk + empty-world props | Static visual |
| `pickup` | `simple_hil.world` parked / actor car | DAE skin |
| `hil_target_ground` | optional pad texture | Not loaded by `simple_hil` |

`simple_hil.world` is a **25% downtown crop** of `hil_city.world` (see
`worlds/crop_simple_hil.py`). OSRF meshes come from gitignored `city_assets/`
(`thrift_shop`, `house_*`, `hatchback`, `actor`, …). `runSimNoeticMulti.sh`
runs `fetch_hil_city.sh` if those models are missing. No `city_terrain`, no
sidewalk polylines, no Prius plugin.
