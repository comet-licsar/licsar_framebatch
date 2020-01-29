#!/bin/bash

inputfile=$1
#onlyPOD should be 1 for 21 days delay or 0 for having up-to-today updates (using restituted orbits)
onlyPOD=$2

totalno=`wc -l $inputfile | gawk {'print $1'}`
echo "there are "$totalno" frames to update"

if [ -f $inputfile.lock ]; then echo "Update is locked - did the previous processing not finish??? Check it"; exit; fi
touch $inputfile.lock

i=0
for frame in `cat $inputfile`; do
 let i=$i+1
 echo "Processing frame no. "$i"/"$totalno" (frame "$frame"):"
 date
 if [ $onlyPOD == 1 ]; then
  enddate=`date -d '21 days ago' +%Y-%m-%d`
 else
  enddate=`date +%Y-%m-%d`
 fi

 tr=`echo $frame | cut -d '_' -f1 | cut -c -3 | sed 's/^0//' | sed 's/^0//'`
 master=`ls $LiCSAR_procdir/$tr/$frame/SLC | head -n1`

 #get last epoch based on public interferograms
 lastepoch=`ls $LiCSAR_public/$tr/$frame/products/2*_2* -d | tail -n1 | rev | cut -d '_' -f1 | rev`
 # start date will include last three images to process..
 startdate=`date -d $lastepoch'-37 days' +%Y-%m-%d`

 licsar_make_frame.sh -S -N $frame 0 1 $startdate $enddate #>$BATCH_CACHE_DIR/volc/auto_volc_$frame.log 2>$BATCH_CACHE_DIR/volc/auto_volc_$frame.err

done

rm $inputfile.lock
