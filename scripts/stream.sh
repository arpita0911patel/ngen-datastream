#!/bin/bash
set -e

SCRIPT_DIR=$(dirname "$(realpath "$0")")
PACAKGE_DIR=$(dirname $SCRIPT_DIR)

build_docker_container() {
    local DOCKER_TAG="$1"
    local DOCKER_IMAGE="$2"

    if docker inspect "$DOCKER_TAG" &>/dev/null; then
        echo "The Docker container '$DOCKER_TAG' exists. Not building."
    else
        echo "Building $DOCKER_TAG container..."
        docker build "$DOCKER_IMAGE" -t "$DOCKER_TAG" --no-cache
    fi
}

if [ $# -ne 1 ]; then
    echo "Usage: $0 <datastream-config.json>"
    exit 1
fi

CONFIG_FILE="$1"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "File not found: $CONFIG_FILE"
    exit 1
fi
config=$(cat "$CONFIG_FILE")

START_DATE=$(echo "$config" | jq -r '.globals.start_date')
END_DATE=$(echo "$config" | jq -r '.globals.end_date')
DATA_PATH=$(echo "$config" | jq -r '.globals.data_dir')
RESOURCE_PATH=$(echo "$config" | jq -r '.globals.resource_dir')
RELATIVE_TO=$(echo "$config" | jq -r '.globals.relative_to')

SUBSET_ID_TYPE=$(echo "$config" | jq -r '.subset.id_type')
SUBSET_ID=$(echo "$config" | jq -r '.subset.id')
HYDROFABRIC_VERSION=$(echo "$config" | jq -r '.subset.version')

if [ $START_DATE == "DAILY" ]; then
    DATA_PATH="${PACAKGE_DIR%/}/data/$(env TZ=US/Eastern date +'%Y%m%d')"
fi

if [ ${#RELATIVE_TO} -gt 0 ] ; then
    echo "Prepending ${RELATIVE_TO} to ${DATA_PATH#/}"
    DATA_PATH="${RELATIVE_TO%/}/${DATA_PATH%/}"
    if [ -n "$RESOURCE_PATH" ]; then
        echo "Prepending ${RELATIVE_TO} to ${RESOURCE_PATH#/}"
        RESOURCE_PATH="${RELATIVE_TO%/}/${RESOURCE_PATH%/}"
    fi
fi

if [ -e "$DATA_PATH" ]; then
    echo "The path $DATA_PATH exists. Please delete it or set a different path."
    exit 1
fi

mkdir -p $DATA_PATH
NGEN_RUN_PATH="${DATA_PATH%/}/ngen-run"
DATASTREAM_CONF_PATH="${DATA_PATH%/}/datastream-configs"
DATASTREAM_RESOURCES="${DATA_PATH%/}/datastream-resources"
mkdir -p $DATASTREAM_CONF_PATH

NGEN_CONFIG_PATH="${NGEN_RUN_PATH%/}/config"
NGEN_OUTPUT_PATH="${NGEN_RUN_PATH%/}/outputs"
mkdir -p $NGEN_CONFIG_PATH
mkdir -p $NGEN_OUTPUT_PATH

GEOPACKGE_NGENRUN="datastream.gpkg"
GEOPACKAGE_NGENRUN_PATH="${NGEN_CONFIG_PATH%/}/$GEOPACKGE_NGENRUN"

if [ -e "$RESOURCE_PATH" ]; then
    if [[ $RESOURCE_PATH == *"https://"* ]]; then
        echo "curl'ing $DATASTREAM_RESOURCES $RESOURCE_PATH"
        curl -# -L -o $DATASTREAM_RESOURCES $RESOURCE_PATH
        if [[ $RESOURCE_PATH == *".tar."* ]]; then
            tar -xzvf $(basename $RESOURCE_PATH)
        fi
    else
        cp -r $RESOURCE_PATH $DATASTREAM_RESOURCES
    fi 
    GEOPACKAGE_RESOURCES_PATH=$(find "$DATASTREAM_RESOURCES" -type f -name "*.gpkg")
    GEOPACKAGE=$(basename $GEOPACKAGE_RESOURCES_PATH)
    
else
    # if a resource path is not supplied, generate one with defaults
    echo "Generating datastream resources with defaults"
    DATASTREAM_RESOURCES_CONFIGS=${DATASTREAM_RESOURCES%/}/ngen-configs
    mkdir -p $DATASTREAM_RESOURCES
    mkdir -p $DATASTREAM_RESOURCES_CONFIGS
    GRID_FILE_DEFAULT="https://ngenresourcesdev.s3.us-east-2.amazonaws.com/nwm.t00z.short_range.forcing.f001.conus.nc"
    GRID_FILE_PATH="${DATASTREAM_RESOURCES%/}/nwm_example_grid_file.nc"
    NGEN_CONF_DEFAULT="https://ngenresourcesdev.s3.us-east-2.amazonaws.com/config.ini"
    NGEN_CONF_PATH="${DATASTREAM_RESOURCES_CONFIGS%/}/config.ini"
    NGEN_REAL_DEFAULT="https://ngenresourcesdev.s3.us-east-2.amazonaws.com/daily_run_realization.json"
    NGEN_REAL_PATH="${DATASTREAM_RESOURCES_CONFIGS%/}/realization.json"

    WEIGHTS_DEFAULT="https://ngenresourcesdev.s3.us-east-2.amazonaws.com/weights_conus_v21.json"
    WEIGHTS_PATH="${DATASTREAM_RESOURCES%/}/weights_conus.json"

    echo "curl'ing $GRID_FILE_PATH $GRID_FILE_DEFAULT"
    curl -L -o $GRID_FILE_PATH $GRID_FILE_DEFAULT 
    echo "curl'ing $NGEN_CONF_PATH $NGEN_CONF_DEFAULT"
    curl -L -o $NGEN_CONF_PATH $NGEN_CONF_DEFAULT
    echo "curl'ing $NGEN_REAL_PATH $NGEN_REAL_DEFAULT"
    curl -L -o $NGEN_REAL_PATH $NGEN_REAL_DEFAULT
    echo "curl'ing $WEIGHTS_PATH $WEIGHTS_DEFAULT"
    curl -L -o $WEIGHTS_PATH $WEIGHTS_DEFAULT

    GEOPACKAGE="conus.gpkg"
    GEOPACKAGE_DEFAULT="https://lynker-spatial.s3.amazonaws.com/v20.1/$GEOPACKAGE"
    GEOPACKAGE_RESOURCES_PATH="${DATASTREAM_RESOURCES%/}/$GEOPACKAGE"    
    echo "curl'ing $GEOPACKAGE_RESOURCES_PATH $GEOPACKAGE_DEFAULT"
    curl -L -o $GEOPACKAGE_RESOURCES_PATH $GEOPACKAGE_DEFAULT

fi

NGEN_CONFS="${DATASTREAM_RESOURCES%/}/ngen-configs/*"
cp $NGEN_CONFS $NGEN_CONFIG_PATH

if [ -e $GEOPACKAGE_RESOURCES_PATH ]; then
    cp $GEOPACKAGE_RESOURCES_PATH $GEOPACKAGE_NGENRUN_PATH
else
    if [ "$SUBSET_ID" = "null" ] || [ -z "$SUBSET_ID" ]; then
        echo "Geopackage does not exist and user has not specified subset! No way to determine spatial domain. Exiting." $GEOPACKAGE
        exit 1
    else

        GEOPACKAGE="$SUBSET_ID.gpkg"
        GEOPACKAGE_RESOURCES_PATH="${DATASTREAM_RESOURCES%/}/$GEOPACKAGE"

        if command -v "hfsubset" &>/dev/null; then
            echo "hfsubset is installed and available in the system's PATH. Subsetting, now!"
        else
            curl -L -o "$DATASTREAM_RESOURCES/hfsubset-linux_amd64.tar.gz" https://github.com/LynkerIntel/hfsubset/releases/download/hfsubset-release-12/hfsubset-linux_amd64.tar.gz
            tar -xzvf "$DATASTREAM_RESOURCES/hfsubset-linux_amd64.tar.gz"
        fi

        hfsubset -o $GEOPACKAGE_RESOURCES_PATH -r $HYDROFABRIC_VERSION -t $SUBSET_ID_TYPE $SUBSET_ID

        cp $GEOPACKAGE_RESOURCES_PATH $GEOPACKAGE_RESOURCES_PATH
        cp $GEOPACKAGE_RESOURCES_PATH $GEOPACKAGE_NGENRUN_PATH        

    fi        
fi

echo "Using geopackage" $GEOPACKAGE, "Named $GEOPACKGE_NGENRUN for ngen_run"

DOCKER_DIR="$(dirname "${SCRIPT_DIR%/}")/docker"
DOCKER_MOUNT="/mounted_dir"
DOCKER_RESOURCES="${DOCKER_MOUNT%/}/datastream-resources"
DOCKER_CONFIGS="${DOCKER_MOUNT%/}/datastream-configs"
DOCKER_FP_PATH="/ngen-datastream/forcingprocessor/src/forcingprocessor/"

# forcingprocessor
DOCKER_TAG="forcingprocessor"
FP_DOCKER="${DOCKER_DIR%/}/forcingprocessor"
build_docker_container "$DOCKER_TAG" "$FP_DOCKER"

WEIGHTS_FILENAME=$(find "$DATASTREAM_RESOURCES" -type f -name "*weights*")
if [ -e "$WEIGHTS_FILENAME" ]; then
    echo "Using weights found in resources directory" "$WEIGHTS_FILENAME"
    mv "$WEIGHTS_FILENAME" ""$DATASTREAM_RESOURCES"/weights.json"
else
    echo "Weights file not found. Creating from" $GEOPACKAGE
    NWM_FILE=$(find "$DATASTREAM_RESOURCES" -type f -name "*nwm*")
    NWM_FILENAME=$(basename $NWM_FILE)

    GEO_PATH_DOCKER=""$DOCKER_RESOURCES"/$GEOPACKAGE"
    WEIGHTS_DOCKER=""$DOCKER_RESOURCES"/weights.json"
    NWM_DOCKER=""$DOCKER_RESOURCES"/$NWM_FILENAME"
    if [ -e "$NWM_FILE" ]; then
        echo "Found $NWM_FILE"
    else
        echo "Missing nwm example grid file!"
        exit 1
    fi

    docker run -it -v "$DATA_PATH:"$DOCKER_MOUNT"" \
        -u $(id -u):$(id -g) \
        -w "$DOCKER_MOUNT" forcingprocessor \
        python "$DOCKER_FP_PATH"weight_generator.py \
        $GEO_PATH_DOCKER $WEIGHTS_DOCKER $NWM_DOCKER

    WEIGHTS_FILE="${DATA%/}/${GEOPACKAGE#/}"
fi

python3 -m pip install --upgrade pip
pip3 install -r $PACAKGE_DIR/requirements.txt --no-cache
CONF_GENERATOR="$PACAKGE_DIR/python/configure-datastream.py"
python3 $CONF_GENERATOR $CONFIG_FILE

echo "Creating nwm filenames file"
docker run -it --rm -v "$DATA_PATH:"$DOCKER_MOUNT"" \
    -u $(id -u):$(id -g) \
    -w "$DOCKER_RESOURCES" $DOCKER_TAG \
    python "$DOCKER_FP_PATH"nwm_filenames_generator.py \
    "$DOCKER_MOUNT"/datastream-configs/conf_nwmurl.json

echo "Creating forcing files"
docker run -it --rm -v "$DATA_PATH:"$DOCKER_MOUNT"" \
    -u $(id -u):$(id -g) \
    -w "$DOCKER_RESOURCES" $DOCKER_TAG \
    python "$DOCKER_FP_PATH"forcingprocessor.py "$DOCKER_CONFIGS"/conf_fp.json

VALIDATOR="/ngen-datastream/python/run_validator.py"
DOCKER_TAG="validator"
VAL_DOCKER="${DOCKER_DIR%/}/validator"
build_docker_container "$DOCKER_TAG" "$VAL_DOCKER"

echo "Validating " $NGEN_RUN_PATH
docker run -it --rm -v "$NGEN_RUN_PATH":"$DOCKER_MOUNT" \
    validator python $VALIDATOR \
    --data_dir $DOCKER_MOUNT


# ngen run
echo "Running NextGen in AUTO MODE from CIROH-UA/NGIAB-CloudInfra"
docker run --rm -it -v "$NGEN_RUN_PATH":"$DOCKER_MOUNT" awiciroh/ciroh-ngen-image:latest-local "$DOCKER_MOUNT" auto
 
# hashing
# docker run --rm -it -v "${NGEN_RUN_PATH%/}/outputs":/outputs zwills/ht ./ht --fmt=tree /outputs

TAR_NAME="ngen-run.tar.gz"
TAR_PATH="${DATA_PATH%/}/$TAR_NAME"
tar -czf  $TAR_PATH -C $NGEN_RUN_PATH .

# manage outputs
# aws s3 sync $DATA_PATH $SOME_BUCKET_NAME
