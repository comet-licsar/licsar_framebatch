#!/bin/bash

if [ -z $2 ]; then echo "usage: licsar_rebuild_rslc.sh FRAME DATE"; exit; fi
echo "(this script will regenerate RSLC for given epoch date - it will delete existing related data in your BATCHDIR. Use e.g. for RSLCs that have missing bursts)"
echo "warning, this will delete all files that use the RSLC. cancel me in 5 sec"
sleep 5

frame=$1
date=$2

if [ `pwd | rev | cut -d '/' -f1 | rev | grep -c $frame` -eq 0 ]; then
 echo "you should start this script in the frame folder. exiting"
 exit
fi

#check and auto-download needed images
echo "first of all, we will check and auto-download needed images"
startdate=`date -d "$date - 1 day" +%Y-%m-%d`
enddate=`date -d "$date + 1 day" +%Y-%m-%d`
framebatch_data_refill.sh $frame $startdate $enddate

echo "now lets generate SLC"
master=`ls geo/2???????.hgt | cut -d '/' -f2 | cut -d '.' -f1`
echo $date > oo
rm -rf SLC/$date 2>/dev/null
LiCSAR_01_mk_images.py -f $frame -d `pwd` -l oo -n

echo "now we will delete related files"
rm -rf RSLC/$date 2>/dev/null
rm -rf IFG/*$date* 2>/dev/null
rm -rf GEOC/*$date* 2>/dev/null

echo "and now we will coregister it."
#bsub -n 1 -q cpom-comet -W 03:00 -R "rusage[mem=25000]" -M 25000 -Ep "cd `pwd`/..; store_to_curdir_earmla_norslc.sh $frame" LiCSAR_02_coreg.py -f $frame -d `pwd` -l oo -k -i -m $master
#bsub -n 1 -q cpom-comet -W 03:00 -R "rusage[mem=25000]" -M 25000 LiCSAR_02_coreg.py -f $frame -d `pwd` -l oo -k -i -m $master
LiCSAR_02_coreg.py -f $frame -d `pwd` -l oo -k -i -m $master
