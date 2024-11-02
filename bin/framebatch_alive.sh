#!/bin/bash

inputfile=$1
#onlyPOD should be 1 for 21 days delay or 0 for having up-to-today updates (using restituted orbits)
onlyPOD=$2
forcee='-f' # set to '' if we don't want to force-process (only when onlyPOD==0)

extrafup='-d '
echo "Warning, setting the update to not perform any download or nla request. Might need tweaking"

totalno=`wc -l $inputfile | gawk {'print $1'}`
echo "there are "$totalno" frames to update"

if [ -f $inputfile.lock ]; then echo "Update is locked - did the previous processing not finish??? Check it"; rm $inputfile.lock; exit; fi
touch $inputfile.lock

if [ $onlyPOD == 1 ]; then
  enddate=`date -d '21 days ago' +%Y-%m-%d`
 else
  enddate=`date +%Y-%m-%d`
fi

i=0
for frame in `cat $inputfile`; do
 let i=$i+1
 echo "Processing frame no. "$i"/"$totalno" (frame "$frame"):"
 date

 #debug - delete gapfilling and temp folders
 rm -rf $LiCSAR_temp/$frame 2>/dev/null
 rm -rf $LiCSAR_temp/gapfill_temp/$frame 2>/dev/null

 if [ $onlyPOD == 1 ]; then
  nohup framebatch_update_frame.sh $extrafup -P $frame upfill &
  #sleep 900
  sleep 200 # 1500 frames should then finish starting in 3 days
 else
  tr=`echo $frame | cut -d '_' -f1 | cut -c -3 | sed 's/^0//' | sed 's/^0//'`
  # master=`ls $LiCSAR_procdir/$tr/$frame/SLC | head -n1`
  #get last epoch based on public interferograms
  lastepoch=`ls $LiCSAR_public/$tr/$frame/interferograms | grep ^2 | tail -n1 | rev | cut -d '_' -f1 | rev`
  # start date will include at least last three images to process..
  startdate=`date -d $lastepoch'-37 days' +%Y-%m-%d`
  licsar_make_frame.sh -S -N $forcee -P $frame 0 1 $startdate $enddate #>$BATCH_CACHE_DIR/volc/auto_volc_$frame.log 2>$BATCH_CACHE_DIR/volc/auto_volc_$frame.err
 fi
done

rm $inputfile.lock 2>/dev/null
