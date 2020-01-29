#!/bin/bash

#this is to process batch (for cron purposes)

#code can be either 'upfill' or 'backfill'
# or 'weekly' or 'monthly'..

code=$1
batchesdir=/gws/nopw/j04/nceo_geohazards_vol1/projects/LiCS/proc/current/batches


if [ $code == 'weekly' ] || [ $code == 'monthly' ]; then
 if [ $code == 'weekly' ]; then onlyPOD=0; else onlyPOD=1; fi
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
 done

else
 echo "wrong code - exiting"
 exit
fi

