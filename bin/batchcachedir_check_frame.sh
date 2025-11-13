#!/bin/bash
PROC=0
AUTODEL=1
if [ -z $1 ]; then echo "set parameter - frame"; echo "if second parameter is 1, this script will perform reprocessing automatically";
 echo "third parameter is to set autodelete in case all is checked OK - it is set to 1 by default, so careful"; exit; fi
if [ ! -d $1 ]; then echo "you need to be in a folder (e.g. your BATCH_CACHE_DIR) with this frame data"; exit; fi
frame=$1
if [ ! -z $2 ]; then PROC=$2; fi
if [ ! -z $3 ]; then AUTODEL=$3; fi
#cd $BATCH_CACHE_DIR
todel=0

if [ `pwd` == $LiCSAR_public ]; then echo "NO.."; exit; fi
if [ `pwd` == $LiCSAR_procdir ]; then echo "NO.."; exit; fi
# we may have files deleted in scratch...
if [ -d $frame/geo ]; then
 if [ `ls $frame/geo | wc -l` == 0 ]; then
   if [ `ls $frame/*LC | wc -l` -gt 2 ]; then
     echo "WARNING, empty geo folder - check manually in todelete folder";
     if [ -d todelete/$frame ]; then rm -r todelete/$frame; fi;
     mv $frame todelete/.;
   else
     echo "empty frame, deleting"; rm -rf $frame;
   fi;
   exit;
 fi
elif [ -d $frame ]; then
 echo "no geo folder inside the frame directory - moving to todelete directory"
 mkdir -p todelete; if [ -d todelete/$frame ]; then rm -r todelete/$frame; fi; mv $frame todelete/.; exit
else
 echo "no such frame dir, cancel"
 exit
fi

rmdir $frame/SLC/* 2>/dev/null
#first check - bad SLC - too large, i.e. over 30 GB:
for x in `ls $frame/SLC`; do
  if [ `ls -al $frame/SLC/$x/$x.slc 2>/dev/null | gawk {'print $5'}` -gt 30066815424 ]; then
    echo "deleting "$frame/SLC/$x; rm -rf $frame/SLC/$x;
  fi;
done

m=`ls $frame/geo/*.hgt | head -n 1 | rev | cut -d '.' -f 2 | cut -d '/' -f 1 | rev`
if [ -z $m ]; then echo "Something is wrong - no hgt file is in the frame geo directory - exiting"; exit; fi

 #check if it is empty
if [ ! -d $frame/RSLC ]; then
  todel=1;
else
   slcdates=`ls $frame/SLC/???????? -d | wc -l`
   rslcdates=`ls $frame/RSLC/???????? -d | wc -l`
   if [ $slcdates -gt 1 ]; then echo "this frame has SLCs to process: "$frame;
      # check on sizes
      #m=`ls $frame/geo/*.hgt | head -n 1 | rev | cut -d '.' -f 2 | cut -d '/' -f 1 | rev`
      #szm=`du -c $frame/SLC/$m/*IW?.slc | tail -n 1 | gawk {'print $1'}`
      # for r in `ls $frame/RSLC/???????? | rev | cut -d '/' -f 1 | rev`; do
      if [ $rslcdates -gt 1 ]; then
        lastrslc=`ls $frame/RSLC/???????? -d | rev | cut -d '/' -f 1 | rev | sed '/'$m'/d' | tail -n 1`
        firstrslc=`ls $frame/RSLC/???????? -d | rev | cut -d '/' -f 1 | rev | sed '/'$m'/d' | head -n 1`
      else
        lastrslc=$m #`ls $frame/RSLC/???????? -d | rev | cut -d '/' -f 1 | rev | tail -n 1`
        firstrslc=$m
      fi
      firstslc=`ls $frame/SLC/???????? -d | rev | cut -d '/' -f 1 | rev | sed '/'$m'/d' | head -n 1`
      lastslc=`ls $frame/SLC/???????? -d | rev | cut -d '/' -f 1 | rev | sed '/'$m'/d' | tail -n 1`
      postprocflag='-f'
      for s in $firstslc $lastslc; do
        for r in $firstrslc $lastrslc; do
         if [ `datediff $s $r 1` -lt 180 ]; then postprocflag=''; fi
        done
      done
      if [ ! -z $postprocflag ]; then
        echo "there is a large gap - try running:"
        if [ $firstrslc -lt $firstslc ]; then fdate=$firstrslc; else fdate=$firstslc; fi
        if [ $lastrslc -gt $lastslc ]; then ldate=$lastrslc; else ldate=$lastslc; fi
        echo "framebatch_update_frame.sh -U "$frame gapfill ${fdate:0:4}-${fdate:4:2}-${fdate:6:2} ${ldate:0:4}-${ldate:4:2}-${ldate:6:2}
        lutdir=$LiCSAR_procdir/`track_from_frame $frame`/$frame/LUT
        lut=`ls $lutdir | grep '.7z' | cut -d '.' -f1 | tail -n 1`
        if [ ! -z $lut ]; then
          #if [ $lut -gt $fdate ]; then
           echo "(note the last LUT for the frame is "$lut" )"
          #fi
        fi
      fi
         if [ $PROC == 1 ]; then
           if [ ! -z $postprocflag ]; then echo "WARNING, we would now process through the long gap - probably causing SD error";
              echo "well... on your responsibility... please run:"
              echo framebatch_postproc_coreg.sh $postprocflag $frame 1
              exit
           fi
           #if [ $slcdates -lt 5 ]; then
           #  batchcachedir_reprocess_from_slcs.sh $frame
           #else
           #  echo "quite a lot of not processed SLCs. performing through postproc_coreg only"
           # echo "TODO - make some more intelligent checks, e.g. on missing bursts, or way too far-in-time epochs"
             framebatch_postproc_coreg.sh $postprocflag $frame 1
             #~ echo "quite a lot of not processed SLCs. switching to licsar_make_frame.sh reprocessing"
             #~ mstr=`ls $frame/geo/*.hgt | head -n1`
             #~ ls $frame/SLC | sed '/'`basename $mstr .hgt`'/d' > $frame/tmp_reprocess.slc
             #~ startdate=`head -n1 $frame/tmp_reprocess.slc`
             #~ enddate=`tail -n1 $frame/tmp_reprocess.slc`
             #~ if [ `grep -c comet $frame/framebatch_02_coreg.nowait.sh` -gt 0 ]; then extral='-P'; fi
             #~ licsar_make_frame.sh -f $extral $frame 1 0 `date -d $startdate +'%Y-%m-%d'` `date -d $enddate +'%Y-%m-%d'`
             #~ rm $frame/tmp_reprocess.slc
           #fi
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
      ifgdates=`ls $frame/GEOC | grep ^20 | wc -l`
      let expifgdates=4*$rslcdates'-4-4-3-2-1-1'  # -4 due to ref epoch in RSLC folder, -4 for the last RSLC, etc., last -1 only to allow -lt
      if [ $ifgdates -lt $expifgdates ]; then
       echo "this frame needs ifg gapfilling: "$frame
         if [ $PROC == 1 ]; then
           #batchcachedir_reprocess_ifgs.sh $frame
           cd $frame; ./framebatch_05_gap_filling.nowait.sh; cd -
         fi
       exit
      else
        # what if unws are missing?
        unwdates=`ls $frame/GEOC/*/*.geo.unw.tif | wc -l`
        if [ $unwdates != $ifgdates ]; then
          echo "this frame has missing unws and needs gapfilling: "$frame
          if [ $PROC == 1 ]; then
           #batchcachedir_reprocess_ifgs.sh $frame
           cd $frame; ./framebatch_05_gap_filling.nowait.sh; cd -
          fi
          exit
        fi
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
         for r in `ls $frame/RSLC | grep ^20 | head -n-1`; do
           if [ `ls $frame/GEOC/$r* -d 2>/dev/null | wc -l` == 0 ]; then
             echo "missing "$r"_* interferograms"
             if [ $r == $m ]; then echo "(but this is ref epoch - perhaps ok)";
             else
                      if [ $PROC == 1 ]; then
                         cd $frame; ./framebatch_05_gap_filling.nowait.sh; cd -
                      fi
                exit
             fi
           fi
         done
         echo "this frame should be stored (and deleted): "$frame
         if [ $PROC == 1 ]; then
           store_to_curdir.sh $frame # 1 0 0  # 2025/10 - only store, as deletion will now be ruled by AUTODEL
           todel=1
         fi

        fi
       fi
      #fi
     #fi
   # fi
   fi
fi

if [ $AUTODEL == 1 ]; then
if [ $todel == 1 ]; then
  numbjobs=`bjobs | grep $frame | wc -l`
  if [ $numbjobs -gt 1 ]; then
    echo "there are LOTUS processes still running for this frame"
  elif [ $numbjobs -eq 1 ]; then
    # if there is only one job waiting and this is the one where we run batchcache checker, then just go on
    if [ `bjobs | grep $frame'_gapfill_out' | wc -l` -gt 0 ]; then
       echo "this frame dir will be deleted now: " $frame; rm -rf $frame
    fi
  else
    echo "this frame dir will be deleted now: " $frame; rm -rf $frame
  fi
fi
fi
