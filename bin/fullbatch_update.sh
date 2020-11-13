#!/bin/bash

#this is to process batch (for cron purposes)

#code can be either 'upfill' or 'backfill'
# or 'weekly' or 'monthly'..
# ... and since 06/2020 also gapfill

code=$1
batchesdir=/gws/nopw/j04/nceo_geohazards_vol1/projects/LiCS/proc/current/batches
cd $batchesdir

if [ $code == 'weekly' ] || [ $code == 'monthly' ]; then
 volcfile=/gws/nopw/j04/nceo_geohazards_vol1/projects/LiCS/volc-proc/active_frames.txt
 if [ $code == 'weekly' ]; then
  updatefile=$batchesdir/alive/$code.txt
  #echo "running volc updates only first"
  #volc_responder.py
  #echo "updating the weekly list"
  for activevolcframe in `cat $volcfile`; do
   if [ `grep -c $activevolcframe $updatefile` -gt 0 ]; then
    echo "Frame "$activevolcframe" is processed by volc_responder already. Removing from weekly updates"
    sed -i '/'$activevolcframe'/d' $updatefile
   fi
  done
  onlyPOD=0;
 else
  #means... if it is monthly updates..
  onlyPOD=1;
  updatefile=$batchesdir/alive/$code.txt
  echo "fixing for volc frames that should be included as well"
  for monthlyvolc in `cat $batchesdir/alive/monthly.volc`; do
   if [ `grep -c $monthlyvolc $volcfile` -eq 0 ]; then
    echo "not in active volcanoes, processing frame "$monthlyvolc" monthly"
    if [ `grep -c $monthlyvolc $updatefile` -eq 0 ]; then
     echo $monthlyvolc >> $updatefile
    fi
   else
    sed -i '/'$monthlyvolc'/d' $updatefile
   fi
  done
  
  echo "finally check for weekly frames - we should not update weekly frames on monthly basis:"
  for weekframe in `cat $batchesdir/alive/weekly.txt`; do
   if [ `grep -c $weekframe $updatefile` -gt 0 ]; then
    echo "Frame "$weekframe" is in both weekly and monthly updates. Removing from monthly updates"
    sed -i '/'$weekframe'/d' $updatefile
   fi
  done
 fi
 
 #a fix for duplicities
 sort -u $updatefile > $updatefile'.temp'
 mv $updatefile'.temp' $updatefile
 
 nohup framebatch_alive.sh $batchesdir/alive/$code.txt $onlyPOD > $batchesdir/alive/$code.`date +%Y%m%d`.out 2> $batchesdir/alive/$code.`date +%Y%m%d`.err &

elif [ $code == 'upfill' ] || [ $code == 'backfill' ]; then

 todayymd=`date +%Y%m%d`
 batchfile=$batchesdir/$code/$todayymd'.txt'

 if [ ! -f $batchfile ]; then
  echo "ERROR - the Batch file for today ("$todayymd") does not exist: "
  echo $batchfile
  exit
 fi

 for frame in `cat $batchfile`; do
   nohup framebatch_update_frame.sh $frame $code > $batchesdir/$code/$todayymd'_'$frame'.log' &
  sleep 900
 done

elif [ $code == 'gapfill' ]; then
 todayymd=`date +%Y%m%d`
 batchfile=$batchesdir/gapfill/gapfill.txt
 for frame in `cat $batchfile`; do
  echo "gapfilling - only the first identified gap"
  nohup framebatch_update_frame_dogap.sh $frame $batchesdir/$code/$todayymd'_'$frame'.gaps' 1 $batchfile > $batchesdir/$code/$todayymd'_'$frame'.log' &
  sleep 900
 done
else
 echo "wrong code - exiting"
 exit
fi

