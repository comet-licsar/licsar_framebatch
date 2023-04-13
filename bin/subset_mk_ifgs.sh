#!/bin/bash

# this is to create ifgs
# just run in the subsets dir

if [ -z $1 ]; then
 echo "Usage e.g.: subset_mk_ifgs.sh $LiCSAR_procdir/subsets/Levee_Ramsey/165A [ifgs.list]"
 echo "this will copy and process ifgs and store in \$BATCH_CACHE_DIR/subsets/\$frame directory"
 echo "NOTE: if you use ifgs.list, please provide FULL PATH"
 exit
fi

extra=''
if [ ! -z $2 ]; then
 echo "using file "$2" as input for ifgs - please use full path"
 ifglist=$2
 extra='-i '$ifglist
fi

cd $1
subsetpath=`pwd`
sid=`echo $subsetpath | rev | cut -d '/' -f 2 | rev`
mlipar=`ls SLC/*/*.mli.par`
if [ -z $mlipar ]; then echo 'mli par of ref epoch does not exist, cancelling'; exit; fi

if [ `ls corners_clip* | wc -l` -gt 1 ]; then echo "more frames here, do it manually please"; exit; fi
frame=`ls corners_clip* | cut -d '.' -f2`
source local_config.py
#if [ -z $rglks ]; then
# rglks=`get_value $mlipar range_looks`
# azlks=`get_value $mlipar azimuth_looks`
#fi
if [ -z $azlks ]; then echo 'error - probably no local_config.py file, exiting'; exit; fi

tempdir=$BATCH_CACHE_DIR/subsets/$sid/$frame
mkdir -p $tempdir/log
cd $tempdir
echo "copying needed files"
for ddir in SLC RSLC tab; do
 rsync -r -u -l $subsetpath/$ddir .;
done
cp $subsetpath/local_config.py .
if [ ! -d geo ]; then cp -r $subsetpath/geo.$resol_m'm' geo; fi

echo "now this should work"
framebatch_gapfill.sh -l -P $extra -o 5 180 $rglks $azlks
