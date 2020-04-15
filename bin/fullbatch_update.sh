#!/bin/bash

#this is to process batch (for cron purposes)

#code can be either 'upfill' or 'backfill'
# or 'weekly' or 'monthly'..

code=$1
batchesdir=/gws/nopw/j04/nceo_geohazards_vol1/projects/LiCS/proc/current/batches
cd $batchesdir

if [ $code == 'weekly' ] || [ $code == 'monthly' ]; then
 if [ $code == 'weekly' ]; then onlyPOD=0; else onlyPOD=1; fi
 if [ $code == 'monthly' ]; then
  volcfile=/gws/nopw/j04/nceo_geohazards_vol1/projects/LiCS/volc-proc/active_frames.txt
  monthlyfile=$batchesdir/alive/$code.txt

  echo "fixing for volc frames that should be included as well"
  for monthlyvolc in `cat $batchesdir/alive/monthly.volc`; do
   if [ `grep -c $monthlyvolc $volcfile` -eq 0 ]; then
    echo "not in active volcanoes, processing frame "$monthlyvolc" monthly"
    if [ `grep -c $monthlyvolc $monthlyfile` -eq 0 ]; then
     echo $monthlyvolc >> $monthlyfile
    fi
   else
    sed -i '/'$monthlyvolc'/d' $monthlyfile
   fi
  done
 fi

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
  sleep 1800
 done

else
 echo "wrong code - exiting"
 exit
fi

