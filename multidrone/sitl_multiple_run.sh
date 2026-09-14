#!/bin/bash
# run multiple instances of the 'px4' binary, with the gazebo SITL simulation
# It assumes px4 is already built, with 'make px4_sitl_default sitl_gazebo-classic'

# The simulator is expected to send to TCP port 4560+i for i in [0, N-1]
# For example gazebo can be run like this:
#./Tools/simulation/gazebo-classic/sitl_multiple_run.sh -n 10 -m iris

function cleanup() {
	pkill -x px4
	pkill gzclient
	pkill gzserver
}

function spawn_model() {
	MODEL=$1
	N=$2 #Instance Number
	X=$3
	Y=$4
	Z=$5
	X=${X:=0.0}
	Y=${Y:=$((3*${N}))}
	Z=${Z:=0.83}

	SUPPORTED_MODELS=("iris" "plane" "standard_vtol" "rover" "r1_rover" "typhoon_h480")
	if [[ " ${SUPPORTED_MODELS[*]} " != *"$MODEL"* ]];
	then
		echo "ERROR: Currently only vehicle model $MODEL is not supported!"
		echo "       Supported Models: [${SUPPORTED_MODELS[@]}]"
		trap "cleanup" SIGINT SIGTERM EXIT
		exit 1
	fi

	working_dir="$build_path/rootfs/$n"
	[ ! -d "$working_dir" ] && mkdir -p "$working_dir"

	pushd "$working_dir" &>/dev/null
	echo "starting instance $N in $(pwd)"

	set --
	set -- ${@} ${src_path}/Tools/simulation/gazebo-classic/sitl_gazebo-classic/scripts/jinja_gen.py
	set -- ${@} ${src_path}/Tools/simulation/gazebo-classic/sitl_gazebo-classic/models/${MODEL}/${MODEL}.sdf.jinja
	set -- ${@} ${src_path}/Tools/simulation/gazebo-classic/sitl_gazebo-classic
	set -- ${@} --mavlink_tcp_port $((4560+${N}))
	set -- ${@} --mavlink_udp_port $((14560+${N}))
	set -- ${@} --mavlink_id $((1+${N}))
	# 5700+drone_index. N is PX4 instance (1-based); 5600+ is claimed by PX4 gst_udp_port and VIO.
	set -- ${@} --gst_udp_port $((5700 + ${N} - 1))
	set -- ${@} --video_uri $((5600+${N}))
	set -- ${@} --mavlink_cam_udp_port $((14530+${N}))
	set -- ${@} --override_parameters_json_path /tmp/hil_jinja_override.json
	set -- ${@} --output-file /tmp/${MODEL}_${N}.sdf

	python3 ${@}

	echo "Spawning ${MODEL}_${N} at ${X} ${Y} ${Z}"

	gz model --spawn-file=/tmp/${MODEL}_${N}.sdf --model-name=${MODEL}_${N} -x ${X} -y ${Y} -z ${Z}

	$build_path/bin/px4 -i $N -d "$build_path/etc" >out.log 2>err.log &

	popd &>/dev/null

}

if [ "$1" == "-h" ] || [ "$1" == "--help" ]
then
	echo "Usage: $0 [-n <num_vehicles>] [-m <vehicle_model>] [-w <world>] [-s <script>] [-p <positions_file>]"
	echo "-s flag is used to script spawning vehicles e.g. $0 -s iris:3,plane:2"
	echo "-p flag is used to specify a file with initial positions (X Y format, one line per drone, Z defaults to 0.83)"
	exit 1
fi

NUM_VEHICLES_SET=false
while getopts n:m:w:s:t:l:p: option
do
	case "${option}"
	in
		n) NUM_VEHICLES=${OPTARG}; NUM_VEHICLES_SET=true;;
		m) VEHICLE_MODEL=${OPTARG};;
		w) WORLD=${OPTARG};;
		s) SCRIPT=${OPTARG};;
		t) TARGET=${OPTARG};;
		l) LABEL=_${OPTARG};;
		p) POSITIONS_FILE=${OPTARG};;
	esac
done

num_vehicles=${NUM_VEHICLES:=3}
world=${WORLD:=empty}
target=${TARGET:=px4_sitl_default}
vehicle_model=${VEHICLE_MODEL:="iris"}
export PX4_SIM_MODEL=gazebo-classic_${vehicle_model}

# If positions file was not provided with -p, check remaining positional arguments for a file
if [ -z "${POSITIONS_FILE}" ]; then
	shift $((OPTIND-1))
	if [ -n "$1" ] && [ -f "$1" ]; then
		POSITIONS_FILE="$1"
		echo "Using positional argument as positions file: ${POSITIONS_FILE}"
	fi
fi

echo ${SCRIPT}
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
src_path="$SCRIPT_DIR/../../.."

build_path=${src_path}/build/${target}
mavlink_udp_port=14560
mavlink_tcp_port=4560

echo "killing running instances"
pkill -x px4 || true

sleep 1

source ${src_path}/Tools/simulation/gazebo-classic/setup_gazebo.bash ${src_path} ${src_path}/build/${target}

CATSWARM_MODELS="/home/valentin/catswarm_models"
if [ -d "${CATSWARM_MODELS}" ]; then
	export GAZEBO_MODEL_PATH="${CATSWARM_MODELS}:${GAZEBO_MODEL_PATH}"
fi

# Positive CATSWARM_HIL_CAM_PITCH (degrees) is nose-down; Gazebo camera +Y pitch looks down.
HIL_CAM_PITCH_DEG="${CATSWARM_HIL_CAM_PITCH:-45}"
python3 - <<PY
import json, math
path = "${src_path}/Tools/simulation/gazebo-classic/sitl_gazebo-classic/resources/px4_gazebo_jinja_parameters.json"
try:
    with open(path) as f:
        params = json.load(f)
except (OSError, ValueError):
    params = {}
params["hil_cam_pitch_rad"] = math.radians(float("${HIL_CAM_PITCH_DEG}"))
with open("/tmp/hil_jinja_override.json", "w") as f:
    json.dump(params, f)
PY

# To use gazebo_ros ROS2 plugins
if [[ -n "$ROS_VERSION" ]] && [ "$ROS_VERSION" == "2" ]; then
	ros_args="-s libgazebo_ros_init.so -s libgazebo_ros_factory.so"
else
	ros_args=""
fi

echo "Starting gazebo"
gzserver ${src_path}/Tools/simulation/gazebo-classic/sitl_gazebo-classic/worlds/${world}.world --verbose $ros_args </dev/null &
sleep 8

if [ -f "${CATSWARM_MODELS}/hil_target_ground/model.sdf" ]; then
	echo "Spawning hil_target_ground"
	gz model --spawn-file="${CATSWARM_MODELS}/hil_target_ground/model.sdf" --model-name=hil_target_ground -x 0 -y 0 -z 0.08
fi

# Read positions from file if provided
declare -a positions_x
declare -a positions_y
declare -a positions_z
if [ -n "${POSITIONS_FILE}" ]; then
	if [ ! -f "${POSITIONS_FILE}" ]; then
		echo "ERROR: Positions file '${POSITIONS_FILE}' not found!"
		exit 1
	fi
	echo "Reading positions from ${POSITIONS_FILE}"
	line_num=0
	while IFS=' ' read -r x y z || [ -n "$x" ]; do
		# Skip empty lines and comments
		[[ -z "$x" || "$x" =~ ^# ]] && continue
		positions_x[$line_num]=$x
		positions_y[$line_num]=$y
		# Use provided Z if available, otherwise default to 0.83
		if [ -n "$z" ] && [ "$z" != "" ]; then
			positions_z[$line_num]=$z
		else
			positions_z[$line_num]=0.83  # Default Z to 0.83 if not provided
		fi
		line_num=$((line_num + 1))
	done < "${POSITIONS_FILE}"
	echo "Loaded ${#positions_x[@]} positions from file"
	# Automatically set num_vehicles to number of positions if -n was not explicitly provided
	if [ "$NUM_VEHICLES_SET" = "false" ]; then
		num_vehicles=${#positions_x[@]}
		echo "Automatically setting number of vehicles to ${num_vehicles} based on positions file"
	fi
fi

n=0
if [ -z ${SCRIPT} ]; then
	if [ $num_vehicles -gt 255 ]
	then
		echo "Tried spawning $num_vehicles vehicles. The maximum number of supported vehicles is 255"
		exit 1
	fi

	while [ $n -lt $num_vehicles ]; do
		instance_num=$(($n + 1))
		if [ -n "${POSITIONS_FILE}" ] && [ $n -lt ${#positions_x[@]} ]; then
			spawn_model ${vehicle_model} ${instance_num} ${positions_x[$n]} ${positions_y[$n]} ${positions_z[$n]}
		else
			spawn_model ${vehicle_model} ${instance_num}
		fi
		n=$(($n + 1))
	done
else
	IFS=,
	for target in ${SCRIPT}; do
		target="$(echo "$target" | tr -d ' ')" #Remove spaces
		target_vehicle=$(echo $target | cut -f1 -d:)
		target_number=$(echo $target | cut -f2 -d:)
		target_x=$(echo $target | cut -f3 -d:)
		target_y=$(echo $target | cut -f4 -d:)

		if [ $n -gt 255 ]
		then
			echo "Tried spawning $n vehicles. The maximum number of supported vehicles is 255"
			exit 1
		fi

		m=0
		while [ $m -lt ${target_number} ]; do
			export PX4_SIM_MODEL=gazebo-classic_${target_vehicle}
			instance_num=$(($n + 1))
			if [ -n "${POSITIONS_FILE}" ] && [ $n -lt ${#positions_x[@]} ]; then
				spawn_model ${target_vehicle}${LABEL} ${instance_num} ${positions_x[$n]} ${positions_y[$n]} ${positions_z[$n]}
			else
				spawn_model ${target_vehicle}${LABEL} ${instance_num} $target_x $target_y
			fi
			m=$(($m + 1))
			n=$(($n + 1))
		done
	done

fi
trap "cleanup" SIGINT SIGTERM EXIT

sleep 2
if [ "${CATSWARM_GZCLIENT:-1}" = "0" ]; then
	echo "Skipping gzclient (CATSWARM_GZCLIENT=0)"
	wait
else
	echo "Starting gazebo client"
	gzclient
fi
