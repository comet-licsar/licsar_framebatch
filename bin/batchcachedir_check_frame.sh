#!/bin/bash
PROC=0
if [ -z $1 ]; then echo "set parameter - frame"; exit; fi
frame=$1
if [ ! -z $2 ]; then PROC=$2; fi
#cd $BATCH_CACHE_DIR
todel=0

  #check if it is empty
  if [ ! -d $frame/RSLC ]; then todel=1;
  else
   slcdates=`ls $frame/SLC | wc -l`
   rslcdates=`ls $frame/RSLC | wc -l`
   if [ $slcdates -gt 1 ]; then echo "this frame has SLCs to process: "$frame;
         if [ $PROC == 1 ]; then
           batchcachedir_reprocess_from_slcs.sh $frame
         fi
   else
    if [ $rslcdates -lt 2 ]; then todel=1;
    else
     if [ ! -d $frame/IFG ]; then echo "this frame has no ifgs: "$frame;
         if [ $PROC == 1 ]; then
           mkdir $frame/IFG
           batchcachedir_reprocess_ifgs.sh $frame
         fi
     else
      ifgdates=`ls $frame/IFG | wc -l`
      let expifgdates=3*$rslcdates'-3'
      if [ $ifgdates -lt $expifgdates ]; then
       echo "this frame may need ifg gapfilling: "$frame
         if [ $PROC == 1 ]; then
           batchcachedir_reprocess_ifgs.sh $frame
         fi
      else
       if [ ! -d $frame/GEOC ]; then
        if [ ! -f $frame/framebatch_06_geotiffs_nowait.sh ]; then
         echo "this frame has geocoding script missing: "$frame;
        else
         echo "this frame needs geocoding: "$frame;
         if [ $PROC == 1 ]; then
           batchcachedir_reprocess_ifgs.sh $frame
         fi
        fi
       else
        geocdates=`ls $frame/GEOC | wc -l`
        if [ ! $ifgdates==$geocdates ]; then
         echo "this frame should be geocoded: "$frame
         if [ $PROC == 1 ]; then
           batchcachedir_reprocess_ifgs.sh $frame
         fi
        else
         echo "this frame should be stored and deleted: "$frame
         if [ $PROC == 1 ]; then
           store_to_curdir.sh $frame 1
         fi

        fi
       fi
      fi
     fi
    fi
   fi
fi

if [ $todel == 1 ]; then echo "this frame dir will be deleted now: " $frame; rm -rf $frame; fi
