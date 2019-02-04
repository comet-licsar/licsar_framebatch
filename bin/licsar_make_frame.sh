#!/bin/bash
# This function should fully update given frame by data from the last 3 months

if [ -z $1 ] || [ `echo $1 | grep -c '_'` -lt 1 ]; then
 echo "Usage: licsar_make_frame.sh FRAME_ID [full_scale] [geocode_to_public_website]"
 echo "e.g. licsar_make_frame.sh 124D_05278_081106 0 1"
 echo "------"
 echo "Use geocode_to_public_website=1 if you want to update the public website geotiffs."
 echo "By default, only last 3 months of data are processed (full_scale=0) as they should exist in CEMS database."
 echo "If full_scale processing is 1, then all data are processed. Please ensure that you run following command before:"
 echo "LiCSAR_0_getFiles.py -f \$FRAME -s \$startdate -e $(date +%Y-%m-%d) -r -b Y -n -z $BATCH_CACHE_DIR/\$FRAME/db_query.list"
 echo "Also, you should have BATCH_CACHE_DIR defined prior to use the function - all data will be processed and save to this directory"
 echo "------"
 echo "By default:"
 echo "full_scale=0"
 echo "geocode_to_public_website=0"
 exit;
fi

#startup variables
frame=$1
if [ -z $BATCH_CACHE_DIR ] || [ ! -d $BATCH_CACHE_DIR ]; then
 echo "There is no BATCH_CACHE_DIR existing. Did you define it properly?"
 exit
fi
basefolder=$BATCH_CACHE_DIR
#basefolder=/gws/nopw/j04/nceo_geohazards_vol2/LiCS/temp/volc
cd $basefolder
if [ ! -z $2 ]; then full_scale=$2; else full_scale=0; fi
if [ ! -z $3 ]; then extra_steps=$3; else extra_steps=0; fi

if [ $full_scale -eq 1 ]; then
 no_of_jobs=20
else
 no_of_jobs=5 #enough for last 3 months data
fi

logdir=~/logs
#decide for query based on user rights
if [ `bugroup | grep $USER | gawk {'print $1'} | grep -c cpom_comet` -eq 1 ]; then
  bsubquery='cpom-comet'
 else
  bsubquery='par-single'
fi

#these extra_steps are now just 'export to comet website'
extra_steps=0

#startup check
if [ -z $LiCSAR_procdir ]; then
 echo "The procdir is not set. Did you 'module load licsar_proc'?"
 exit
else
 public=$LiCSAR_procdir
fi
if [ ! -d $basefolder ]; then
 echo "The directory "$basefolder" does not exist. Create it first";
 exit;
fi

mkdir -p $BATCH_CACHE_DIR/$frame
cd $BATCH_CACHE_DIR/$frame
echo "All log files will be saved to "$logdir/$frame
mkdir -p $logdir/$frame 2>/dev/null
#this is only to easy up the manual process..
#jobno_start=`cat $logdir/$frame/job_start.txt 2>/dev/null`
#let jobno_end=$jobno_start+$no_of_jobs'-1'


###functions
function wait {
 #old waiting way
 #while [ `bjobs | grep -c $USER` -gt 0 ]; do sleep 10; done
 pom=0; jobno_start=$1; jobno_end=$2;
 echo "Waiting for the jobs to finish"
 while [ $pom -eq 0 ] ; do
  bjobs -w -p -r -noheader | grep $USER | gawk {'print $7'} | rev | cut -d '_' -f1 | rev > tmp_running.txt
  pom=1 #it means that if there is no unfinished process, we would continue
  for A in `seq $jobno_start $jobno_end`; do if [ `grep -c $A tmp_running.txt` -gt 0 ]; then pom=0; fi; done
  rm tmp_running.txt
  sleep 60
 done
}


## MAIN CODE
############### 
 #do not do if restarting
 echo "Activating the frame"
 date
 setFrameInactive.py $frame
 setFrameActive.py $frame
if [ $full_scale -eq 0 ]; then
 echo "Preparing the frame cache (last 3 months)"
 createFrameCache_last3months.py $frame $no_of_jobs > tmp_jobid.txt
else
 echo "Preparing the frame cache (full scale processing)"
 createFrameCache.py $frame $no_of_jobs > tmp_jobid.txt
fi
 grep first_job_id tmp_jobid.txt | gawk {'print $3'} > $logdir/$frame/job_start.txt
 if [ -z `cat $logdir/$frame/job_start.txt` ]; then echo "The frame "$frame "is erroneous and cannot be processed"; exit; fi
 rm tmp_jobid.txt
#################
 
###################################################### Making images
## #to restart, begin here
 date
 echo "ok, preparing the images using existing data"
 jobno_start=`cat $logdir/$frame/job_start.txt`
 let jobno_end=$jobno_start+$no_of_jobs'-1'
 rm mk_image.sh 2>/dev/null
 for A in `seq $jobno_start $jobno_end`; do
  echo bsub -o "$logdir/$frame/mk_image_$A.out" -e "$logdir/$frame/mk_image_$A.err" -Ep \"ab_LiCSAR_lotus_cleanup.py $A\" -J "mk_image_$A" \
    -q $bsubquery -n 1 -W 12:00 ab_LiCSAR_mk_image.py $A >> mk_image.sh
 done
 chmod 770 mk_image.sh; ./mk_image.sh
 wait $jobno_start $jobno_end

###################################################### Coregistering
 date
 echo "ok, processing the next stage - coreg"
 echo "updating jobno_start to coreg"
 let jobno_start_coreg=$jobno_start+$no_of_jobs
 let jobno_end_coreg=$jobno_end+$no_of_jobs
 rm coreg.sh 2>/dev/null
 for A in `seq $jobno_start_coreg $jobno_end_coreg`; do
  echo bsub -o "$logdir/$frame/coreg_$A.out" -e "$logdir/$frame/coreg_$A.err" -Ep \"ab_LiCSAR_lotus_cleanup.py $A\" -J "coreg_$A" \
            -q $bsubquery -n 4 -W 36:00 ab_LiCSAR_coreg.py $A >> coreg.sh
 done
 chmod 770 coreg.sh; ./coreg.sh
 wait $jobno_start_coreg $jobno_end_coreg
 
###################################################### Make ifgs
 date
 echo "ok, processing the next stage - make_ifg"
 echo "updating jobno_start to make_ifg"
 let jobno_start_ifg=$jobno_start+$no_of_jobs+$no_of_jobs
 let jobno_end_ifg=$jobno_end+$no_of_jobs+$no_of_jobs
 rm mk_ifg.sh 2>/dev/null
 for A in `seq $jobno_start_ifg $jobno_end_ifg`; do
  echo bsub -o "$logdir/$frame/mk_ifg_$A.out" -e "$logdir/$frame/mk_ifg_$A.err" -Ep \"ab_LiCSAR_lotus_cleanup.py $A\" -J "mk_ifg_$A" \
       -q $bsubquery -n 1 -W 24:00 ab_LiCSAR_mk_ifg.py $A >> mk_ifg.sh
 done
 chmod 770 mk_ifg.sh; ./mk_ifg.sh
 wait $jobno_start_ifg $jobno_end_ifg
 
###################################################### Unwrapping
 date
 echo "ok, processing the next stage - unwrap"
 echo "updating jobno_start to unwrap"
 let jobno_start_unw=$jobno_start+$no_of_jobs+$no_of_jobs+$no_of_jobs
 let jobno_end_unw=$jobno_end+$no_of_jobs+$no_of_jobs+$no_of_jobs
 rm unwrap.sh 2>/dev/null
 for A in `seq $jobno_start_unw $jobno_end_unw`; do
 # let A=$A+$no_of_jobs+$no_of_jobs+$no_of_jobs
  echo bsub -o "$logdir/$frame/unwrap_$A.out" -e "$logdir/$frame/unwrap_$A.err" -Ep \"ab_LiCSAR_lotus_cleanup.py $A\" -J "unwrap_$A" \
       -q $bsubquery -n 4 -W 36:00 ab_LiCSAR_unwrap.py $A >> unwrap.sh
 done
 chmod 770 unwrap.sh; ./unwrap.sh
 wait $jobno_start_unw $jobno_end_unw

echo "...please check the results manually. If everything is processed fine, including unwrapping,"
echo "you may run following to deactivate the frame from the spreadsheet:"
echo setFrameInactive.py $frame

#echo "Deactivating frame (will disappear from the spreadsheet)"
#echo "In order to activate it again, just do setFrameActive.py $frame"
#setFrameInactive.py $frame

echo "Processing finished, now generating geotiffs"
###################################################### Geocoding to tiffs
for ifg in `ls $BATCH_CACHE_DIR/$frame/IFG/*_* -d | rev | cut -d '/' -f1 | rev`; do
 if [ -f $BATCH_CACHE_DIR/$frame/IFG/$ifg/$ifg.unw ]; then
 echo "geocoding "$ifg
 create_geoctiffs_to_pub.sh $BATCH_CACHE_DIR/$frame $ifg > $logdir/$frame/geocode_$ifg.log 2>$logdir/$frame/geocode_$ifg.err
 fi
done

if [ $extra_steps -eq 1 ]; then
###################################################### Publishing tiffs
track=`echo $frame | cut -d '_' -f1 | rev | cut -c 2- | rev`
for geoifg in `ls $BATCH_CACHE_DIR/$frame/GEOC/2*_2* -d | rev | cut -d '/' -f1 | rev`; do
 echo "copying geocoded "$geoifg
 for toexp in cc.bmp cc.tif diff.bmp diff_mag.tif diff_pha.tif unw.bmp unw.tif disp.png; do
  if [ -f $BATCH_CACHE_DIR/$frame/GEOC/$geoifg/$geoifg.geo.$toexp ]; then
   mkdir -p $public/$track/$frame/products/$geoifg 2>/dev/null
   if [ ! -f $public/$track/$frame/products/$geoifg/$geoifg.geo.$toexp ]; then
    cp $BATCH_CACHE_DIR/$frame/GEOC/$geoifg/$geoifg.geo.$toexp $public/$track/$frame/products/$geoifg/.
   fi
  fi
 done
done

fi
