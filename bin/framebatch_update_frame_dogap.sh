 #!/bin/bash

# ML 06/2020
# this script cleans the frame (auto), gets gaps (updates network.png and gaps.txt files)
# and starts gapfilling of the first gap
if [ -z $1 ]; then
 echo "Usage: FRAME_ID gapsfile.txt [run quality check first?] [input txt file]" #[geocode_to_public_website]"
 echo "optional parameters: "
 echo "-d ... densify - will check also for missing epochs" #1"
 echo "-k ... keep frames in batchdir - do not store and delete after running this"
 echo "-n ... not run the processing - only get gaps/densify to the gapsfile.txt"
 exit;
fi
densify=0
norun=0
extrapar=''
source $LiCSARpath/lib/LiCSAR_bash_lib.sh

while getopts ":dkn" option; do
 case "${option}" in
  d) densify=1; echo "run the densification workflow";
     ;;
  k) extrapar='-k';
     ;;
  n) norun=1;
     ;;
 esac
done
#shift
shift $((OPTIND -1))


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

if [ $densify == 1 ]; then
 echo "Identifying missing epochs (densify)"
 get_dates_scihub.py $frame 20141001 `date +%Y%m%d` > $gapfile.tmp.all2
 tail -n+2 $gapfile.tmp.all2 > $gapfile.tmp.all
 rm $gapfile.tmp.all2
 track=`track_from_frame $frame`
 ls $LiCSAR_public/$track/$frame/int*/20*_* -d | rev | cut -d '/' -f1 | rev | cut -d '_' -f1 > $gapfile.tmp.existt
 ls $LiCSAR_public/$track/$frame/int*/20*_* -d | rev | cut -d '/' -f1 | rev | cut -d '_' -f2 >> $gapfile.tmp.existt
 sort -u $gapfile.tmp.existt >$gapfile.tmp.exist
 rm $gapfile.tmp.existt
 rm $gapfile.tmp.missing 2>/dev/null
 for x in `cat $gapfile.tmp.all`; do
  if [ `grep -c $x $gapfile.tmp.exist` -lt 1 ]; then
   echo $x >> $gapfile.tmp.missing
  fi
 done
 rm $gapfile.tmp.exist $gapfile.tmp.all
 touch $gapfile
 get_gaps.py $frame $gapfile.tmp.missing | grep $frame > $gapfile
else
 echo "Identifying gaps"
 touch $gapfile
 get_gaps.py $frame | grep $frame > $gapfile
fi

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
 echo framebatch_update_frame.sh $extrapar $frame gapfill $gapin $gapout 1
 if [ $norun -eq 0 ]; then
  framebatch_update_frame.sh $extrapar $frame gapfill $gapin $gapout 1
 fi
done
