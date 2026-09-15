#!/bin/bash
# Script to start PX4 multi-drone simulation in Docker with a single command
# This script starts the Docker container and automatically runs the simulation
# based on positions defined in positions.txt

# Get script directory to make paths invariant to project location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=multidrone/write_sitl_spawn_map.sh
source "${SCRIPT_DIR}/multidrone/write_sitl_spawn_map.sh"

CONTAINER_NAME="px4-noetic-sim-ros"

# Cleanup function to be called on script exit or --kill
cleanup_on_exit() {
    echo ""
    echo "Cleaning up..."
    
    # Remove container
    echo "Removing container..."
    docker rm -f ${CONTAINER_NAME} 2>/dev/null || true
    
    # Clean up X11
    echo "Cleaning up X11 resources..."
    xhost -local:docker 2>/dev/null || true
    xhost - 2>/dev/null || true
    rm -f /tmp/.X*-lock 2>/dev/null || true
    
    # Clean up processes
    echo "Killing related processes..."
    pkill -x px4 2>/dev/null || true
    pkill gzclient 2>/dev/null || true
    pkill gzserver 2>/dev/null || true
    pkill -f "gz master" 2>/dev/null || true
    pkill -f "gazebo.*master" 2>/dev/null || true
    rm -f /tmp/catswarm_sitl_spawn.json /tmp/catswarm_sitl_spawn.env 2>/dev/null || true
    
    # Kill process on port 11345 if any
    if lsof -ti:11345 >/dev/null 2>&1; then
        echo "Killing process using Gazebo master port 11345..."
        lsof -ti:11345 | xargs kill -9 2>/dev/null || true
    fi
}

# Default values
NUM_DRONES=1
POSITIONS_FILE="${SCRIPT_DIR}/multidrone/positions.txt"

# Argument parsing
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Script to start PX4 multi-drone simulation in Docker."
            echo ""
            echo "Options:"
            echo "  --help, -h               Show this help message and exit"
            echo "  --kill                   Clean up/kill existing simulation containers and processes"
            echo "  --num=N, --num N         Number of drones to spawn (default: 1)"
            echo "  --file=PATH, --file PATH Path to positions file (default: multidrone/positions.txt)"
            echo ""
            echo "Environment:"
            echo "  PX4_VIDEO_HOST_IP        RTP destination IP (default: 127.0.0.1)"
            echo "  CATSWARM_HIL_CAM_PITCH   Camera pitch down, degrees (default: 45)"
            echo "  CATSWARM_GZCLIENT        Set to 0 to skip gzclient (default: 1)."
            echo "                           GUI Start Sim always sets this to 1 so the 3D"
            echo "                           window and the camera feed run together."
            echo "  CATSWARM_WORLD           Gazebo world name (default: hil_city if fetched,"
            echo "                           else empty). Run multidrone/fetch_hil_city.sh once."
            echo "  CATSWARM_SIM_GPU         1 = NVIDIA GL in Docker (--gpus all + PRIME offload)."
            echo "                           0 = CPU/llvmpipe (rollback). Unset = auto if nvidia-smi."
            echo "  CATSWARM_GST_BITRATE     GstCameraPlugin 1080p HEVC kbps (default: 4000)."
            echo "  CATSWARM_GST_SPEED_PRESET x265enc speed-preset (default: 1 = ultrafast)."
            echo "  LIBGL_ALWAYS_SOFTWARE    Set to 1 only if GPU GL is broken (very slow)"
            echo ""
            exit 0
            ;;
        --kill)
            echo "Kill command received."
            cleanup_on_exit
            exit 0
            ;;
        --num=*)
            NUM_DRONES="${1#*=}"
            shift
            ;;
        --num)
            NUM_DRONES="$2"
            shift 2
            ;;
        --file=*)
            POSITIONS_FILE="${1#*=}"
            shift
            ;;
        --file)
            POSITIONS_FILE="$2"
            shift 2
            ;;
        [0-9]*)
            NUM_DRONES="$1"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

# Set trap to cleanup on script exit
trap cleanup_on_exit EXIT INT TERM

# Initial cleanup to ensure clean state
cleanup_on_exit

# Setup X11 forwarding
xhost + 2>/dev/null || true
xhost +local:docker 2>/dev/null || true

# Verify display is accessible
if [ -z "$DISPLAY" ]; then
    echo "Warning: DISPLAY environment variable is not set"
    export DISPLAY=:0
fi

# Set XAUTHORITY if not set
if [ -z "$XAUTHORITY" ] && [ -f "$HOME/.Xauthority" ]; then
    export XAUTHORITY="$HOME/.Xauthority"
fi

# Build docker run command with conditional XAUTHORITY volume
XAUTH_FILE="${XAUTHORITY:-$HOME/.Xauthority}"

# Determine positions file mount
DEFAULT_POSITIONS="${SCRIPT_DIR}/multidrone/positions.txt"
if [ "$POSITIONS_FILE" = "$DEFAULT_POSITIONS" ]; then
    # Use default positions file location
    CONTAINER_POSITIONS_PATH="/home/valentin/PX4-Autopilot/Tools/simulation/positions.txt"
    DOCKER_VOLUMES=(
        --volume="/tmp/.X11-unix:/tmp/.X11-unix:rw"
        --volume="${POSITIONS_FILE}:${CONTAINER_POSITIONS_PATH}:rw"
        --volume="${SCRIPT_DIR}/multidrone/sitl_multiple_run.sh:/home/valentin/PX4-Autopilot/Tools/simulation/gazebo-classic/sitl_multiple_run2.sh:rw"
    )
else
    # Use custom positions file
    CONTAINER_POSITIONS_PATH="/tmp/custom_positions.txt"
    DOCKER_VOLUMES=(
        --volume="/tmp/.X11-unix:/tmp/.X11-unix:rw"
        --volume="${SCRIPT_DIR}/multidrone/positions.txt:/home/valentin/PX4-Autopilot/Tools/simulation/positions.txt:rw"
        --volume="${POSITIONS_FILE}:${CONTAINER_POSITIONS_PATH}:ro"
        --volume="${SCRIPT_DIR}/multidrone/sitl_multiple_run.sh:/home/valentin/PX4-Autopilot/Tools/simulation/gazebo-classic/sitl_multiple_run2.sh:rw"
    )
fi

# CatSwarm HIL: camera-enabled iris template, local props, OSRF city assets.
CITY_ASSETS="${SCRIPT_DIR}/multidrone/city_assets"
if [ "${CATSWARM_WORLD:-hil_city}" = "hil_city" ] && [ ! -f "${CITY_ASSETS}/worlds/hil_city.world" ]; then
    echo "City world missing; fetching OSRF citysim assets (once)…"
    "${SCRIPT_DIR}/multidrone/fetch_hil_city.sh"
fi
DOCKER_VOLUMES+=(
    --volume="${SCRIPT_DIR}/multidrone/iris.sdf.jinja:/home/valentin/PX4-Autopilot/Tools/simulation/gazebo-classic/sitl_gazebo-classic/models/iris/iris.sdf.jinja:ro"
    --volume="${SCRIPT_DIR}/multidrone/models:/home/valentin/catswarm_models:ro"
)
# Overlay patched GstCameraPlugin (1080p HEVC / ~4000 kbps) when built locally.
GST_CAMERA_PLUGIN="${SCRIPT_DIR}/../vision_hil/host/gst_camera_plugin/libgazebo_gst_camera_plugin.so"
if [ -f "${GST_CAMERA_PLUGIN}" ]; then
    DOCKER_VOLUMES+=(
        --volume="${GST_CAMERA_PLUGIN}:/home/valentin/PX4-Autopilot/build/px4_sitl_default/build_gazebo-classic/libgazebo_gst_camera_plugin.so:ro"
    )
    echo "GstCameraPlugin: bind-mount ${GST_CAMERA_PLUGIN}"
fi
if [ -d "${CITY_ASSETS}/models" ]; then
    DOCKER_VOLUMES+=(
        --volume="${CITY_ASSETS}:/home/valentin/catswarm_city:ro"
    )
fi

# Add XAUTHORITY volume only if file exists
if [ -f "$XAUTH_FILE" ]; then
    DOCKER_VOLUMES+=(--volume="${XAUTH_FILE}:${XAUTH_FILE}:ro")
fi

# Gazebo master must stay on loopback; --net=host otherwise publicizes 10.42.0.1 and gzclient crashes gzserver.
# Allocate a TTY only when stdin is a real terminal; a fake TTY injects NUL and aborts gzserver.
DOCKER_TTY=(-i)
if [ -t 0 ]; then
    DOCKER_TTY=(-it)
fi

DOCKER_ENVS=(
    --env="DISPLAY=$DISPLAY"
    --env="QT_X11_NO_MITSHM=1"
    --env="XAUTHORITY=${XAUTH_FILE}"
    --env="PX4_VIDEO_HOST_IP=${PX4_VIDEO_HOST_IP:-127.0.0.1}"
    --env="CATSWARM_HIL_CAM_PITCH=${CATSWARM_HIL_CAM_PITCH:-45}"
    --env="CATSWARM_GZCLIENT=${CATSWARM_GZCLIENT:-1}"
    --env="CATSWARM_WORLD=${CATSWARM_WORLD:-hil_city}"
    --env="CATSWARM_GST_BITRATE=${CATSWARM_GST_BITRATE:-4000}"
    --env="CATSWARM_GST_SPEED_PRESET=${CATSWARM_GST_SPEED_PRESET:-1}"
    --env="GAZEBO_MODEL_DATABASE_URI="
    --env="GAZEBO_IP=127.0.0.1"
    --env="GAZEBO_MASTER_URI=http://127.0.0.1:11345"
)
# Software GL (llvmpipe) makes gzclient+gzserver unusable for flight (~10x realtime lag).
# This machine can run the *existing* image on the NVIDIA GPU; see
# vision_hil/docs/2026-09-14-gpu-gazebo.md. CATSWARM_SIM_GPU=0 is the rollback.
if [ "${LIBGL_ALWAYS_SOFTWARE:-}" = "1" ]; then
    DOCKER_ENVS+=(--env="LIBGL_ALWAYS_SOFTWARE=1")
fi

DOCKER_GPU=()
SIM_GPU=0
case "${CATSWARM_SIM_GPU:-auto}" in
    0|false|no|off) SIM_GPU=0 ;;
    *)
        if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi -L >/dev/null 2>&1; then
            SIM_GPU=1
        fi
        ;;
esac
if [ "${CATSWARM_SIM_GPU:-}" = "0" ]; then
    SIM_GPU=0
fi
if [ "${LIBGL_ALWAYS_SOFTWARE:-}" = "1" ]; then
    SIM_GPU=0
fi
if [ "${SIM_GPU}" = "1" ]; then
    DOCKER_GPU=(--gpus all)
    DOCKER_ENVS+=(
        --env="__NV_PRIME_RENDER_OFFLOAD=1"
        --env="__GLX_VENDOR_LIBRARY_NAME=nvidia"
        --env="__NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0"
    )
    echo "Gazebo GL: NVIDIA GPU (CATSWARM_SIM_GPU). Rollback: CATSWARM_SIM_GPU=0"
else
    echo "Gazebo GL: CPU/llvmpipe (set CATSWARM_SIM_GPU=1 if nvidia-smi works)"
fi

# Host HA/SM read this so ObservationBoard LLA matches the Gazebo pad, not the
# empty-world 3 m parking line. Must run after CATSWARM_WORLD / POSITIONS_FILE.
# NUM_DRONES lets it record the same no-XY default the container script uses for
# drones past the end of the positions file.
NUM_DRONES="${NUM_DRONES}" write_sitl_spawn_map

docker run "${DOCKER_TTY[@]}" --net=host \
           --cap-drop=all \
           --privileged \
           "${DOCKER_GPU[@]}" \
           "${DOCKER_ENVS[@]}" \
           "${DOCKER_VOLUMES[@]}" \
           --name=${CONTAINER_NAME} \
           ${CONTAINER_NAME} \
           /bin/bash -c "./Tools/simulation/gazebo-classic/sitl_multiple_run2.sh -p ${CONTAINER_POSITIONS_PATH} -n ${NUM_DRONES}"

# Note: Cleanup is handled by the trap function on exit
