#!/bin/bash

# Adapts and runs FSLNets' nets_examples.m

# Written by Andreas Bartsch & Andreas Heckel
# University of Heidelberg
# heckelandreas@googlemail.com
# https://github.com/ahheckel
# 02/27/2013

# set error flag
set -e

# define error trap
trap 'echo "$0 : An ERROR has occured."' ERR

# define exit trap
trap "set +e ; echo -e \"\n\n`basename $0`: cleanup...\" ; rm -fv /tmp/nets_examples.m$$ ; exit" EXIT

Usage() {
    echo ""
    echo "Usage:   `basename $0` <template_nets_examples.m> <dreg_stage1_path> <groupIC> <good_comp> <design_path> <nperm> <out-dir>"
    echo "Example: `basename $0` ./template_nets_examples.m ./dreg ./melodic/melodicIC.nii.gz \"[1 2 3 4 5 6 7 8 9 10]\" ./glm/design 5000 ./grp/FSLNETS/dreg"
    echo ""
    exit 1
}

[ "$7" = "" ] && Usage

template="$1"
dreg_path="$2"
group_maps="$3"
good_comp="$4"
design_path="$5"
nperm=$6
outdir="$7"

install_path="/home/andi/FSL-scripts/rsc/scripts/FSLNets"
l1prec_path="$install_path/L1precision"
causal_path="$install_path/pwling"
design_mat="$design_path/design.mat"
design_con="$design_path/design.con"
design_grp="$design_path/design.grp"

cp $template /tmp/nets_examples.m$$ 

sed -i "s|design_nperm=.*|design_nperm=${nperm}|g"   /tmp/nets_examples.m$$
sed -i "s|design_mat=.*|design_mat='$design_mat'|g"  /tmp/nets_examples.m$$
sed -i "s|design_con=.*|design_con='$design_con'|g"  /tmp/nets_examples.m$$
sed -i "s|design_grp=.*|design_grp='$design_grp'|g"  /tmp/nets_examples.m$$

sed -i "s|addpath FSLNETS.*|addpath $install_path|g"   /tmp/nets_examples.m$$
sed -i "s|addpath L1PREC.*|addpath $l1prec_path|g"     /tmp/nets_examples.m$$
sed -i "s|addpath PAIRCAUSAL.*|addpath $causal_path|g" /tmp/nets_examples.m$$

sed -i "s|group_maps=.*|group_maps='${group_maps}'|g" /tmp/nets_examples.m$$
sed -i "s|ts.DD=.*|ts.DD=${good_comp}|g"              /tmp/nets_examples.m$$  
sed -i "s|ts_dir='.*|ts_dir='${dreg_path}'|g"         /tmp/nets_examples.m$$  

sed -i "s|outputdir=.*|outputdir='${outdir}'|g"       /tmp/nets_examples.m$$

# check
cat /tmp/nets_examples.m$$ | head -n 40
read -p "Press Key to continue..."

# start MATLAB
mkdir -p $outdir
cd $outdir
mv /tmp/nets_examples.m$$ ./nets_examples.m
matlab -nodesktop -r nets_examples