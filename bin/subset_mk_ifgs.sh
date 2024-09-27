#!/bin/bash

# this is to create ifgs
# just run in the subsets dir

if [ -z $1 ]; then
 echo "Usage e.g.: subset_mk_ifgs.sh [-P] [-s foo.sh] $LiCSAR_procdir/subsets/Levee_Ramsey/165A [ifgs.list]"
 echo "parameter -P will run through comet queue"
 echo "parameter -s foo.sh .. will run foo.sh script after end of generation of ifgs"
 echo "----"
 echo "this will copy and process ifgs and store in \$BATCH_CACHE_DIR/subsets/\$sid/\$frameid directory"
 echo "NOTE: if you use ifgs.list, please provide FULL PATH. Also note, the ifgs.list should contain pairs in the form of e.g.:"
 echo "20180101_20180303"
 exit
fi

extra=''
shscript=''

while getopts ":PRs:" option; do
 case "${option}" in
  P ) extra='-P ';
     ;;
  R ) extra='-R ';
     ;;
  s ) shscript=$OPTARG; echo "will run this script afterwards: "$shscript;
#      shift
      ;;
 esac
done
#shift
shift $((OPTIND -1))

if [ -z $1 ]; then echo "please check provided parameters"; exit; fi

if [ ! -z $2 ]; then
 echo "using file "$2" as input for ifgs"
 ifglist=`realpath $2`
 extra='-i '$ifglist
fi

cd $1
subsetpath=`pwd`
sid=`echo $subsetpath | rev | cut -d '/' -f 2 | rev`
frameid=`echo $subsetpath | rev | cut -d '/' -f 1 | rev`
mlipar=`ls SLC/*/*.mli.par`
if [ -z $mlipar ]; then echo 'mli par of ref epoch does not exist, cancelling'; exit; fi

#if [ `ls corners_clip* | wc -l` -gt 1 ]; then echo "more frames here, do it manually please"; exit; fi
#frame=`ls corners_clip* | head -n 1 | cut -d '.' -f2`
source local_config.py
#if [ -z $rglks ]; then
# rglks=`get_value $mlipar range_looks`
# azlks=`get_value $mlipar azimuth_looks`
#fi
if [ -z $azlks ]; then echo 'error - probably no local_config.py file, exiting'; exit; fi

tempdir=$BATCH_CACHE_DIR/subsets/$sid/$frameid
mkdir -p $tempdir/log $tempdir/tab
cd $tempdir
echo "copying needed core files"
# fix the master SLC
m=`ls $subsetpath/SLC | grep 20 | head -n1`
mkdir -p SLC/$m
cd SLC/$m; for x in slc slc.mli slc.mli.par slc.par; do if [ ! -f $m.$x ]; then ln -s $tempdir/RSLC/$m/$m.r$x $m.$x; fi; done;
cd $tempdir
#done
cp $subsetpath/local_config.py .
echo $subsetpath/corners_clip.* | rev | cut -d '.' -f1 | rev > sourceframe

if [ ! -d geo ]; then cp -r $subsetpath/geo.$resol_m'm' geo; fi
mkdir GEOC 2>/dev/null
if [ ! -d GEOC/geo ]; then cp -r $subsetpath/GEOC.meta.$resol_m'm' GEOC/geo; cp GEOC/geo/* GEOC/.; fi   # yes, double copy, but LiCSBAS expects it in different dir than LiCSAR

echo "copying existing clipped RSLCs"
#for ddir in SLC RSLC; do
ddir=RSLC
rsync -r -u -l $subsetpath/$ddir .;
# fix issue with different multilooking of ref epoch:
rm *LC/$m/*mli*

if [ ! -z $shscript ]; then
  chmod 777 $shscript 2>/dev/null
  extra=$extra" -s "$shscript
fi
echo "now sending jobs to generate ifgs using command:"
echo "framebatch_gapfill.sh -l -T -n 5 "$extra" -o 5 480" $rglks $azlks
framebatch_gapfill.sh -l -T -n 5 $extra -o 5 480 $rglks $azlks
