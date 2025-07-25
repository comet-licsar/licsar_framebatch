#!/bin/bash
PROC=0
if [ -z $1 ]; then echo "set parameter - frame"; echo "if second parameter is 1, this script will perform reprocessing automatically"; exit; fi
if [ ! -d $1 ]; then echo "set parameter - frame"; echo "if second parameter is 1, this script will perform reprocessing automatically"; exit; fi
frame=$1
if [ ! -z $2 ]; then PROC=$2; fi
#cd $BATCH_CACHE_DIR
todel=0

if [ `pwd` == $LiCSAR_public ]; then echo "NO.."; exit; fi
if [ `pwd` == $LiCSAR_procdir ]; then echo "NO.."; exit; fi
# we may have files deleted in scratch...
if [ -d $frame/geo ]; then
 if [ `ls $frame/geo | wc -l` == 0 ]; then echo "empty frame, deleting"; rm -rf $frame; exit; fi
elif [ -d $frame ]; then
 echo "no geo folder inside the frame directory - moving to todelete directory"
 mkdir todelete; mv $frame todelete/.; exit
else
 echo "no such frame dir, cancel"
 exit
fi
 
#first check - bad SLC - too large, i.e. over 30 GB:
for x in `ls $frame/SLC`; do
  if [ `ls -al $frame/SLC/$x/$x.slc 2>/dev/null | gawk {'print $5'}` -gt 30066815424 ]; then
    echo "deleting "$frame/SLC/$x; rm -rf $frame/SLC/$x;
  fi;
done

 #check if it is empty
if [ ! -d $frame/RSLC ]; then
  todel=1;
else
   slcdates=`ls $frame/SLC | wc -l`
   rslcdates=`ls $frame/RSLC | wc -l`
   if [ $slcdates -gt 1 ]; then echo "this frame has SLCs to process: "$frame;
         if [ $PROC == 1 ]; then
           if [ $slcdates -lt 5 ]; then
             batchcachedir_reprocess_from_slcs.sh $frame
           else
             echo "quite a lot of not processed SLCs. performing through postproc_coreg only"
             framebatch_postproc_coreg.sh $frame 1
             #~ echo "quite a lot of not processed SLCs. switching to licsar_make_frame.sh reprocessing"
             #~ mstr=`ls $frame/geo/*.hgt | head -n1`
             #~ ls $frame/SLC | sed '/'`basename $mstr .hgt`'/d' > $frame/tmp_reprocess.slc
             #~ startdate=`head -n1 $frame/tmp_reprocess.slc`
             #~ enddate=`tail -n1 $frame/tmp_reprocess.slc`
             #~ if [ `grep -c comet $frame/framebatch_02_coreg.nowait.sh` -gt 0 ]; then extral='-P'; fi
             #~ licsar_make_frame.sh -f $extral $frame 1 0 `date -d $startdate +'%Y-%m-%d'` `date -d $enddate +'%Y-%m-%d'`
             #~ rm $frame/tmp_reprocess.slc
           fi
         fi
   else
    if [ $rslcdates -lt 2 ]; then todel=1;
    else
     #if [ ! -d $frame/IFG ]; then echo "this frame has no ifgs: "$frame;
     #    if [ $PROC == 1 ]; then
     #      mkdir $frame/IFG
     #      batchcachedir_reprocess_ifgs.sh $frame
     #    fi
     #else
      rmdir $frame/GEOC/* 2>/dev/null
      ifgdates=`ls $frame/GEOC | wc -l`
      let expifgdates=4*$rslcdates'-3'
      if [ $ifgdates -lt $expifgdates ]; then
       echo "this frame needs ifg gapfilling: "$frame
         if [ $PROC == 1 ]; then
           #batchcachedir_reprocess_ifgs.sh $frame
           cd $frame; ./framebatch_05_gap_filling.nowait.sh; cd -
         fi
      else
      # if [ ! -d $frame/GEOC ]; then
      #  if [ ! -f $frame/framebatch_06_geotiffs.nowait.sh ]; then
      #   echo "this frame has geocoding script missing: "$frame;
      #  else
      #   echo "this frame needs geocoding: "$frame;
      #   if [ $PROC == 1 ]; then
      #     batchcachedir_reprocess_ifgs.sh $frame
      #   fi
      #  fi
      # else
      #  geocdates=`ls $frame/GEOC | wc -l`
      #  if [ ! $ifgdates == $geocdates ]; then
       #  echo "this frame should be geocoded: "$frame
      #   if [ $PROC == 1 ]; then
      #     batchcachedir_reprocess_ifgs.sh $frame
      #   fi
      #  else
         echo "this frame should be stored and deleted: "$frame
         if [ $PROC == 1 ]; then
           store_to_curdir.sh $frame 1 0 0
         fi

        fi
       fi
      #fi
     #fi
   # fi
   fi
fi

if [ $todel == 1 ]; then echo "this frame dir will be deleted now: " $frame; rm -rf $frame; fi
