#!/usr/bin/env bash
# cd /lab/repos/cytokit/pub/analysis/cell-size; bash -e pipeline_execution.sh

EXPERIMENTS=`cat experiments.csv | tail -n +2`

for EXP in $EXPERIMENTS
do
    EXP_NAME=`echo $EXP | cut -d',' -f 1`
    EXP_STEPZ=`echo $EXP | cut -d',' -f 2`
    EXP_NUMZ=`echo $EXP | cut -d',' -f 3`
    EXP_MAG=`echo $EXP | cut -d',' -f 4`
    DATA_DIR=$CYTOKIT_DATA_DIR/cytokit/cell-size/20181024/$EXP_NAME
    BASE_CONF=$CYTOKIT_REPO_DIR/pub/config/cell-size/experiment_${EXP_MAG}.yaml
    
    echo "Clearing results for experiment $EXP_NAME at $DATA_DIR/output/*"
    rm -rf $DATA_DIR/output/*
    
    cytokit config editor --base-config-path=$BASE_CONF --output-dir=$DATA_DIR/output \
    set name $EXP_NAME \
    set acquisition.axial_resolution $EXP_STEPZ \
    set acquisition.num_z_planes $EXP_NUMZ \
    set processor.cytometry.segmentation_params.memb_sigma 2 \
    save_variant v00/config \
    set processor.cytometry.segmentation_params.memb_sigma 4 \
    save_variant v01/config \
    set processor.cytometry.segmentation_params.memb_sigma 8 \
    save_variant v02/config \
    exit

    for VARIANT in v00 v01 v02 
    do
        OUTPUT_DIR=$DATA_DIR/output/$VARIANT
        CONFIG_DIR=$OUTPUT_DIR/config
        echo "Processing experiment $EXP_NAME (config = $CONFIG_DIR, zplanes = $EXP_NUMZ, step = $EXP_STEPZ)"
        
        cytokit processor run_all --config-path=$CONFIG_DIR --data-dir=$DATA_DIR/raw --output-dir=$OUTPUT_DIR
        cytokit operator run_all  --config-path=$CONFIG_DIR --data-dir=$OUTPUT_DIR --raw-dir=$DATA_DIR/raw
        cytokit analysis run_all  --config-path=$CONFIG_DIR --data-dir=$OUTPUT_DIR 
    done
done

