#!/bin/bash

# ML 06/2020
# this script cleans the frame (auto), gets gaps (updates network.png and gaps.txt files)
# and starts gapfilling of the first gap

frame=$1
#logfile=
gapfile=$2

#third parameter (0 or 1) is for qualcheck
if [ ! -z $3 ]; then
 qualcheck=$3
else
 qualcheck=0
fi

#fourth parameter is for input txt file
if [ ! -z $4 ]; then
 inputfile=$4
else
 inputfile=''
fi

if [ -z $2 ]; then
 echo "usage - include parameters frame and gapfile"
 echo "e.g. \$frame \$LiCSAR_procdir/batches/gapfill/20200525_\$frame.gaps"
 exit
fi

if [ $qualcheck -eq 1 ]; then
 echo "Cleaning the frame - autoquality check"
 frame_ifg_quality_check.py -d $frame
fi

echo "Identifying gaps"
touch $gapfile
get_gaps.py $frame | grep $frame > $gapfile

if [ ! -z $inputfile ]; then
if [ `wc -l $gapfile 2>/dev/null | gawk {'print $1'}` -eq 0 ]; then
 echo "no gaps left for the frame, removing from the list"
 sed -i 'd/'$frame'/' $inputfile
fi
fi

for liner in `head -n1 $gapfile 2>/dev/null`; do
 echo "starting gapfilling of first gap for frame "$frame
 gapin=`echo $liner | cut -d ',' -f2`
 gapout=`echo $liner | cut -d ',' -f3`
 echo framebatch_update_frame.sh $frame gapfill $gapin $gapout 1
 framebatch_update_frame.sh $frame gapfill $gapin $gapout 1
done
