#!/bin/bash

#this is to process batch, to be done twice per week
batches_dir=/gws/nopw/j04/nceo_geohazards_vol1/projects/LiCS/proc/current/batches
todayymd=`date +%Y%m%d`
batchfile=$batches_dir/$todayymd'.txt'

if [ ! -f $batchfile ]; then
  echo "ERROR - the Batch file does not exist: "
  echo $batchfile
  exit
fi

for frame in `cat $batchfile`; do 
 nohup framebatch_update_frame.sh $frame > $batches_dir/$todayymd'_'$frame'.log' &
done
