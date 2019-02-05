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

#getting to proper work directory
if [ -z $BATCH_CACHE_DIR ] || [ ! -d $BATCH_CACHE_DIR ]; then
 echo "There is no BATCH_CACHE_DIR existing. Did you define it properly?"
 exit
fi
basefolder=$BATCH_CACHE_DIR
#e.g. basefolder=/gws/nopw/j04/nceo_geohazards_vol2/LiCS/temp/volc
#informing user.. just to be sure
echo 'Processing in your BATCH_CACHE_DIR that is '$BATCH_CACHE_DIR

#startup variables
frame=$1
#settings of full_scale and extra_steps - by default 0
#these extra_steps are now just 'export to comet website'
if [ ! -z $2 ]; then full_scale=$2; else full_scale=0; fi
if [ ! -z $3 ]; then extra_steps=$3; else extra_steps=0; fi

if [ $full_scale -eq 1 ]; then
 echo "WARNING:"
 echo "You have chosen to process in full scale"
 echo "This makes sense only if you have already done (two days ago) the nla request, i.e."
 echo "LiCSAR_0_getFiles.py -f FRAME etc. -- see documentation"
 echo "If you didn't, please cancel it now (CTRL-C)"
 sleep 5
 echo "..waited 5 sec. Continuing"
 no_of_jobs=20
else
 no_of_jobs=5 #enough for last 3 months data
fi

#I may use $BATCH_CACHE_DIR/$frame/LOGS instead for logdir??
#logdir=~/logs
#decide for query based on user rights
if [ `bugroup | grep $USER | gawk {'print $1'} | grep -c cpom_comet` -eq 1 ]; then
  bsubquery='cpom-comet'
 else
  bsubquery='par-single'
fi

#testing.. but perhaps helps in getting proper num threads in CEMS environment
export OMP_NUM_THREADS=16

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

#initializing the frame dir and LOGS dir
mkdir -p $BATCH_CACHE_DIR/$frame/LOGS
cd $BATCH_CACHE_DIR/$frame
logdir=$BATCH_CACHE_DIR/$frame/LOGS
if [ -d $logdir ]; then
 echo "All log files will be saved to "$logdir
else
 echo 'Some error occurred. Do you have write rights to your BATCH_CACHE_DIR?'
 exit
fi
#mkdir -p $logdir 2>/dev/null
#this is only to easy up the manual process..
#jobno_start=`cat $logdir/job_start.txt 2>/dev/null`
#let jobno_end=$jobno_start+$no_of_jobs'-1'


###functions
function wait {
 #this function has its flaws and it will not be used..
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
 #do not do if restarting - it will re-create the job IDs etc.
 echo "Activating the frame"
 date
 setFrameInactive.py $frame
 setFrameActive.py $frame
if [ $full_scale -eq 0 ]; then
 echo "Preparing the frame cache (last 3 months)"
 echo "..may take some 5 minutes"
 createFrameCache_last3months.py $frame $no_of_jobs > tmp_jobid.txt
else
 echo "Preparing the frame cache (full scale processing)"
 echo "..may take some 15 minutes or more"
 createFrameCache.py $frame $no_of_jobs > tmp_jobid.txt
fi
 grep first_job_id tmp_jobid.txt | gawk {'print $3'} > $logdir/job_start.txt
 if [ -z `cat $logdir/job_start.txt` ]; then echo "The frame "$frame "is erroneous and cannot be processed"; exit; fi
 rm tmp_jobid.txt
#################
 date
 echo "Done. Making the processing queries"
 
###################################################### Making images
## #to restart, begin here
 
 echo "..preparing the input images using existing data (SLC)"
 jobno_start=`cat $logdir/job_start.txt`
 let jobno_end=$jobno_start+$no_of_jobs'-1'
 rm framebatch_01_mk_image.sh 2>/dev/null
 for A in `seq $jobno_start $jobno_end`; do
  echo bsub -o "$logdir/mk_image_$A.out" -e "$logdir/mk_image_$A.err" -Ep \"ab_LiCSAR_lotus_cleanup.py $A\" -J "mk_image_$A" \
    -q $bsubquery -n 1 -W 12:00 ab_LiCSAR_mk_image.py $A >> framebatch_01_mk_image.sh
 done
 chmod 770 framebatch_01_mk_image.sh; ./framebatch_01_mk_image.sh
 #wait $jobno_start $jobno_end

###################################################### Coregistering
 #date
 echo "..setting coregistration stage (RSLC)"
 #echo "updating jobno_start to coreg"
 let jobno_start_coreg=$jobno_start+$no_of_jobs
 let jobno_end_coreg=$jobno_end+$no_of_jobs
 rm framebatch_02_coreg.sh 2>/dev/null
 for A in `seq $jobno_start_coreg $jobno_end_coreg`; do
  let B=$A-$no_of_jobs
  echo bsub -o "$logdir/coreg_$A.out" -e "$logdir/coreg_$A.err" -Ep \"ab_LiCSAR_lotus_cleanup.py $A\" -J "coreg_$A" \
            -q $bsubquery -n 4 -W 36:00 -w \""ended(mk_image_$B)"\" ab_LiCSAR_coreg.py $A >> framebatch_02_coreg.sh
 done
 chmod 770 framebatch_02_coreg.sh; ./framebatch_02_coreg.sh
 #wait $jobno_start_coreg $jobno_end_coreg
 
###################################################### Make ifgs
 #date
 echo "..setting make_ifg job (IFG)"
 #echo "updating jobno_start to make_ifg"
 let jobno_start_ifg=$jobno_start_coreg+$no_of_jobs
 let jobno_end_ifg=$jobno_end_coreg+$no_of_jobs
 rm framebatch_03_mk_ifg.sh 2>/dev/null
 for A in `seq $jobno_start_ifg $jobno_end_ifg`; do
  let B=$A-$no_of_jobs
  echo bsub -o "$logdir/mk_ifg_$A.out" -e "$logdir/mk_ifg_$A.err" -Ep \"ab_LiCSAR_lotus_cleanup.py $A\" -J "mk_ifg_$A" \
       -q $bsubquery -n 1 -W 24:00 -w \""ended(coreg_$B)"\" ab_LiCSAR_mk_ifg.py $A >> framebatch_03_mk_ifg.sh
 done
 chmod 770 framebatch_03_mk_ifg.sh; ./framebatch_03_mk_ifg.sh
 #wait $jobno_start_ifg $jobno_end_ifg
 
###################################################### Unwrapping
 #date
 echo "..setting unwrapping (UNW)"
 #echo "updating jobno_start to unwrap"
 let jobno_start_unw=$jobno_start_ifg+$no_of_jobs
 let jobno_end_unw=$jobno_end_ifg+$no_of_jobs
 rm framebatch_04_unwrap.sh 2>/dev/null
 #adding the waiting parameters for step 05 already here.. more mess but bit easier for me J
 step5_wait=""
 for A in `seq $jobno_start_unw $jobno_end_unw`; do
 # let A=$A+$no_of_jobs+$no_of_jobs+$no_of_jobs
  let B=$A-$no_of_jobs
  echo bsub -o "$logdir/unwrap_$A.out" -e "$logdir/unwrap_$A.err" -Ep \"ab_LiCSAR_lotus_cleanup.py $A\" -J "unwrap_$A" \
       -q $bsubquery -n 4 -W 36:00 -w \""mk_ifg_$B"\" ab_LiCSAR_unwrap.py $A >> framebatch_04_unwrap.sh
  step5_wait=$step5_wait" && ended(unwrap_"$A")"
 done
 step5_wait=`echo $step5_wait | cut -c 5-`
 chmod 770 framebatch_04_unwrap.sh; ./framebatch_04_unwrap.sh
 #wait $jobno_start_unw $jobno_end_unw

###################################################### Geocoding to tiffs
echo "All bsub jobs are sent for processing. Sending request to generate geotiffs after it all finishes"
cat << EOF > framebatch_05_geotiffs.sh
for ifg in \`ls $BATCH_CACHE_DIR/$frame/IFG/*_* -d | rev | cut -d '/' -f1 | rev\`; do
 if [ -f $BATCH_CACHE_DIR/$frame/IFG/\$ifg/\$ifg.unw ]; then
 echo "geocoding "\$ifg
 create_geoctiffs_to_pub.sh $BATCH_CACHE_DIR/$frame \$ifg > $logdir/geocode_\$ifg.log 2>$logdir/geocode_\$ifg.err
 fi
done
EOF
chmod 770 framebatch_05_geotiffs.sh

bsub -o "$logdir/geotiffs.out" -e "$logdir/geotiffs.out" -J "geotiffs_$frame" \
 -q $bsubquery -n 1 -W 12:00 -w "$step5_wait" ./framebatch_05_geotiffs.sh

echo "...please check the results manually."
echo "You may be checking 'bjobs' or the spreadsheet:"
echo "https://docs.google.com/spreadsheets/d/1Rbt_nd5nok-UZ7dfBXFHsZ66IqozrHwxiRj-TDnVDMY"
echo "If everything is processed fine, including unwrapping,"
echo "you may run following to deactivate the frame from the spreadsheet:"
echo "module load licsar_framebatch"
echo setFrameInactive.py $frame
echo ".. and if not, try rerunning the framebatch_XX scripts in this folder:"
pwd
ls framebatch*

#echo "Deactivating frame (will disappear from the spreadsheet)"
#echo "In order to activate it again, just do setFrameActive.py $frame"
#setFrameInactive.py $frame

exit

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
