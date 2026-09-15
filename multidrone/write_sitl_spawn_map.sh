#!/bin/bash
# Write host-side SITL map frame so ObservationBoard LLA matches Gazebo XY.
# Gazebo X = East, Y = North; PX4 maps (0,0) → Zurich 47.3977, 8.5456.
# Same origin-shift heuristic as sitl_multiple_run.sh (hil_city pad at -15, 108).
#
# Usage: CATSWARM_WORLD=hil_city POSITIONS_FILE=... ./write_sitl_spawn_map.sh

write_sitl_spawn_map() {
    local spawn_json="${CATSWARM_SITL_SPAWN_FILE:-/tmp/catswarm_sitl_spawn.json}"
    local spawn_env="/tmp/catswarm_sitl_spawn.env"
    local world="${CATSWARM_WORLD:-hil_city}"
    local pos_file="${POSITIONS_FILE:-}"
    local xs=()
    local ys=()

    if [ -n "${pos_file}" ] && [ -f "${pos_file}" ]; then
        while IFS=' ' read -r x y z || [ -n "$x" ]; do
            [[ -z "$x" || "$x" =~ ^# ]] && continue
            xs+=("$x")
            ys+=("$y")
        done < "${pos_file}"
    fi
    if [ ${#xs[@]} -eq 0 ]; then
        if [ "${world}" = "hil_city" ]; then
            xs=(-15)
            ys=(108)
        else
            xs=(0)
            ys=(0)
        fi
    fi

    local first_x="${xs[0]}"
    local first_y="${ys[0]}"
    if [ "${world}" = "hil_city" ]; then
        awk_origin='BEGIN { x="'"${first_x}"'"; y="'"${first_y}"'"; if (x+0 >= -8 && x+0 <= 8 && y+0 >= -20 && y+0 <= 20) exit 0; exit 1 }'
        if awk "${awk_origin}"; then
            local i
            for i in "${!xs[@]}"; do
                xs[$i]=$(awk -v x="${xs[$i]}" 'BEGIN { printf "%.3f", x-15 }')
                ys[$i]=$(awk -v y="${ys[$i]}" 'BEGIN { printf "%.3f", y+108 }')
            done
        fi
    fi

    local east="${xs[0]}"
    local north="${ys[0]}"
    local de="0.000"
    local dn="3.000"
    if [ ${#xs[@]} -ge 2 ]; then
        de=$(awk -v a="${xs[1]}" -v b="${xs[0]}" 'BEGIN { printf "%.3f", a-b }')
        dn=$(awk -v a="${ys[1]}" -v b="${ys[0]}" 'BEGIN { printf "%.3f", a-b }')
    elif [ "${world}" = "hil_city" ]; then
        dn="4.000"
    fi

    cat > "${spawn_json}" << EOF
{"east_m": ${east}, "north_m": ${north}, "spacing_east_m": ${de}, "spacing_north_m": ${dn}}
EOF
    cat > "${spawn_env}" << EOF
CATSWARM_WORLD=${world}
CATSWARM_SITL_SPAWN_EAST_M=${east}
CATSWARM_SITL_SPAWN_NORTH_M=${north}
CATSWARM_SITL_SPAWN_SPACING_EAST_M=${de}
CATSWARM_SITL_SPAWN_SPACING_NORTH_M=${dn}
EOF
    echo "SITL map frame: Zurich + pad east=${east} north=${north} spacing E=${de} N=${dn} (${spawn_json})"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    write_sitl_spawn_map
fi
