#!/bin/bash
# This function should fully update given frame by data from the last 3 months

if [ -z $1 ] || [ `echo $1 | grep -c '_'` -lt 1 ]; then
 echo "Usage: licsar_make_frame.sh FRAME_ID [full_scale] [autodownload] [startdate] [enddate]" #[geocode_to_public_website]"
 echo "e.g. licsar_make_frame.sh 124D_05278_081106 0 1 2017-06-30 2019-01-01" #1"
 echo "------"
# echo "Use geocode_to_public_website=1 if you want to update the public website geotiffs."
 echo "By default, only last 3 months of data are processed (full_scale=0) as they should exist in CEMS database."
 echo "If full_scale processing is 1, then all data are processed (unless startdate and/or enddate is specified)."
 echo "Please ensure that you run following command before:"
 echo "LiCSAR_0_getFiles.py -f \$FRAME -s \$startdate -e $(date +%Y-%m-%d) -r -b Y -n -z $BATCH_CACHE_DIR/\$FRAME/db_query.list"
 echo "Also, you should have BATCH_CACHE_DIR defined prior to use the function - all data will be processed and save to this directory"
 echo "The autodownload would attempt to download all related SLC files from internet if they are physically not available."
 echo "Note that this is slow and not recommended for full_scale without NLA."
 echo "------"
 echo "By default:"
 echo "full_scale=0"
 echo "autodownload=1 if full_scale, otherwise 0"
 #echo "geocode_to_public_website=0"
 exit;
fi

#getting to proper work directory
if [ -z $BATCH_CACHE_DIR ] || [ ! -d $BATCH_CACHE_DIR ]; then
 echo "There is no BATCH_CACHE_DIR existing. Did you define it properly?"
 exit
fi
# 03/2019 - we started to use scratch-nompiio disk as a possible solution for constant stuck job problems
# after JASMIN update to Phase 4
#if [ ! -d /work/scratch-nompiio/licsar/$USER ]; then mkdir /work/scratch-nompiio/licsar/$USER; fi
if [ ! -d /work/scratch/licsar/$USER ]; then mkdir /work/scratch/licsar/$USER; fi

basefolder=$BATCH_CACHE_DIR
#e.g. basefolder=/gws/nopw/j04/nceo_geohazards_vol2/LiCS/temp/volc
#informing user.. just to be sure
echo 'Processing in your BATCH_CACHE_DIR that is '$BATCH_CACHE_DIR

#startup variables
frame=$1
#settings of full_scale and extra_steps - by default 0
#these extra_steps are now just 'export to comet website'
if [ ! -z $2 ]; then full_scale=$2; else full_scale=0; fi
if [ ! -z $3 ]; then fillgaps=$3; else fillgaps=$full_scale; fi #ye, if only last 3 months then we should not need fillgaps
if [ ! -z $4 ]; then 
 startdate=$4; full_scale=1;
 if [ `echo $startdate | cut -c8` != '-' ]; then echo "You provided wrong startdate: "$startdate; exit; fi
 else startdate="2014-10-10";
fi
if [ ! -z $5 ]; then
 enddate=$5;
 if [ `echo $enddate | cut -c8` != '-' ]; then echo "You provided wrong enddate: "$enddate; exit; fi
fi
if [ ! -z $6 ]; then extra_steps=$6; else extra_steps=0; fi

#this was needed for the download workaround but it is not necessary anymore
#if [ $fillgaps -eq 1 ]; then
# ssh -q cems-login1.cems.rl.ac.uk exit
# test_conn=$?
# if [ $test_conn -gt 0 ]; then
#  echo "ERROR: No connection to your login server."
#  echo "The automatic SLC download will not work"
#  echo "(try log-out and log-in back to sci server, maybe you are in tmux since yesterday and ssh session expired?)"
#  echo "I will continue without it in 5 seconds (cancel me)"
#  sleep 5
#  fillgaps=0
# fi
#fi

if [ $full_scale -eq 1 ]; then
 echo "WARNING:"
 echo "You have chosen to process in full scale"
 echo "This makes sense only if you have already done (two days ago) the nla request, i.e."
 echo "LiCSAR_0_getFiles.py -f FRAME etc. -- see documentation"
 echo "If you didn't, please cancel it now (CTRL-C)"
 sleep 5
 echo "..waited 5 sec. Continuing"
 no_of_jobs=40
else
 no_of_jobs=5 #enough for last 3 months data
fi

#I may use $BATCH_CACHE_DIR/$frame/LOGS instead for logdir??
#logdir=~/logs
#decide for query based on user rights
if [ `bugroup | grep $USER | gawk {'print $1'} | grep -c cpom_comet` -eq 1 ]; then
  bsubquery='cpom-comet'
 else
  #bsubquery='par-single' #this one is for multinode.. let's keep it in one only
  bsubquery='short-serial'
fi

#testing.. but perhaps helps in getting proper num threads in CEMS environment
export OMP_NUM_THREADS=16

#getting access to database
mysqlhost=`grep ^Host $framebatch_config | cut -d ':' -f2 | sed 's/^\ //'`
mysqluser=`grep ^User $framebatch_config | cut -d ':' -f2 | sed 's/^\ //'`
mysqlpass=`grep ^Password $framebatch_config | cut -d ':' -f2 | sed 's/^\ //'`
mysqldbname=`grep ^DBName $framebatch_config | cut -d ':' -f2 | sed 's/^\ //'`
SQLPath=`grep ^SQLPath $framebatch_config | cut -d '=' -f2 | sed 's/^\ //'`
#i should test it here..


#startup check
if [ -z $LiCSAR_procdir ]; then
 echo "The procdir is not set. Did you 'module load licsar_proc'?"
 exit
else
 public=$LiCSAR_public
 current=$LiCSAR_procdir
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
#function wait {
 #this function has its flaws and it will not be used..
 #old waiting way
 #while [ `bjobs | grep -c $USER` -gt 0 ]; do sleep 10; done
# pom=0; jobno_start=$1; jobno_end=$2;
# echo "Waiting for the jobs to finish"
# while [ $pom -eq 0 ] ; do
#  bjobs -w -p -r -noheader | grep $USER | gawk {'print $7'} | rev | cut -d '_' -f1 | rev > tmp_running.txt
#  pom=1 #it means that if there is no unfinished process, we would continue
#  for A in `seq $jobno_start $jobno_end`; do if [ `grep -c $A tmp_running.txt` -gt 0 ]; then pom=0; fi; done
#  rm tmp_running.txt
#  sleep 60
# done
#}

function prepare_job_script {
 step=$1
 stepcmd=$2
 stepsql=$3
 stepprev=$4
 
 rm $step.sh 2>/dev/null
 rm $step'_nowait.sh' 2>/dev/null
 rm $step.list 2>/dev/null
 echo "mysql -h $mysqlhost -u $mysqluser -p$mysqlpass $mysqldbname < $SQLPath/$stepsql.sql | grep $USER | grep $frame | sort -n" > $step.sql
# mysql command is much faster, but it is not available in every server:
if [ ! -z `which mysql 2>/dev/null` ]; then
 mysql -h $mysqlhost -u $mysqluser -p$mysqlpass $mysqldbname < $SQLPath/$stepsql.sql | grep $USER | grep $frame | sort -n > $step.list
else
 cat << EOF > getit.py
import pandas as pd
from batchDBLib import engine
from configLib import config
sqlPath = config.get('Config','SQLPath')
QryFile = open(sqlPath+'/$stepsql.sql','r')
if QryFile:
    Qry = QryFile.read()
    DatFrm = pd.read_sql_query(Qry,engine)
    DatFrm.to_csv('$step.list', header=False, index=False, sep='\t', mode='a')
else:
    print('Could not open SQL query file')
EOF
 python getit.py
 rm getit.py
 #too quick to write to disk J
 #wow, 5 seconds waiting was not enough!!!!! 
 echo "waiting 15 seconds. Should be enough to synchronize data write from python"
 echo "(what a problem in the age of supercomputers..)"
 sleep 15
 cat $step.list | grep $USER | grep $frame | sort -n > $step.list 
fi
 #if [ $realjobno != `cat $step.list | wc -l` ]; then
 # echo "WARNING, THE NO OF JOBS DIFFER BETWEEN mk_img AND $step. This should NOT happen and will NOT work properly."
 #fi
 
# jline=0
 for jobid in `cat $step.list | gawk {'print $1'} | sort -un`; do
  #get connected images from previous step
  waitText=""
  waitcmd=""
  rm tmpText 2>/dev/null
  if [ ! -z $stepprev ]; then
   for image in `grep ^$jobid $step.list | gawk {'print $3'}`; do
    #get jobid from previous step that is connected to this image
    grep $image $stepprev.list | gawk {'print $1'} >> tmpText
   done
   for jobid_prev in `cat tmpText | sort -nu`; do
#   grep $image $stepprev.list | gawk {'print $1'}`; do
    waitText=$waitText" && ended("$stepprev"_"$jobid_prev")"
   done
   waitText=`echo $waitText | cut -c 4-`
   waitcmd='-w "'$waitText'"'
  fi
#  let jline=$jline+1
#  B=`sed -n $jline'p' $stepprev.list | gawk {'print $1'}`
  if [ $bsubquery == "short-serial" ]; then
  extrabsub=''
  if [ $step == "framebatch_02_coreg" ] || [ $step == "framebatch_04_unwrap" ]; then
   maxmem=25000
   extrabsub='-R "rusage[mem='$maxmem']" -M '$maxmem
  fi
  fi
  echo bsub -o "$logdir/$step"_"$jobid.out" -e "$logdir/$step"_"$jobid.err" -Ep \"ab_LiCSAR_lotus_cleanup.py $jobid\" -J "$step"_"$jobid" \
     -q $bsubquery -n 1 -W 23:59 $extrabsub $waitcmd $stepcmd $jobid >> $step.sh
  echo bsub -o "$logdir/$step"_"$jobid.out" -e "$logdir/$step"_"$jobid.err" -Ep \"ab_LiCSAR_lotus_cleanup.py $jobid\" -J "$step"_"$jobid" \
     -q $bsubquery -n 1 -W 23:59 $extrabsub $stepcmd $jobid >> $step'_nowait.sh'
 done
 
 rm tmpText 2>/dev/null
 chmod 770 $step.sh $step'_nowait.sh'
 #./$step.sh
}

## MAIN CODE
############### 
 #do not do if restarting - it will re-create the job IDs etc.
 date
 setFrameInactive.py $frame
 echo "Activating the frame"
 setFrameActive.py $frame
if [ $full_scale -eq 0 ]; then
#if we work only in last 3 months data
 if [ $fillgaps -eq 1 ]; then
  echo "Refilling the data gaps (should be ok for last 3 months data)"
  framebatch_data_refill.sh $frame `date -d "90 days ago" +'%Y-%m-%d'`
 fi
 echo "Preparing the frame cache (last 3 months)"
 echo "..may take some 5 minutes"
 #createFrameCache_last3months.py $frame $no_of_jobs > tmp_jobid.txt
 createFrameCache.py $frame $no_of_jobs `date -d "90 days ago" +'%Y-%m-%d'` > tmp_jobid.txt
else
#if we want to fill gaps throughout the whole time period
 if [ $fillgaps -eq 1 ]; then
  echo "Refilling the data gaps"
  framebatch_data_refill.sh $frame $startdate $enddate
 fi
 echo "Preparing the frame cache (full scale processing)"
 echo "..may take some 15 minutes or more"
 createFrameCache.py $frame $no_of_jobs $startdate $enddate > tmp_jobid.txt
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
 
 
 #logically good approach, but doesn't work always:
# jobno_start=`cat $logdir/job_start.txt`
# let jobno_end=$jobno_start+$no_of_jobs'-1' # oh... but sometimes there is less tasks... carramba
# 
 #getting jobIDs for mk_image:
 step=framebatch_01_mk_image
 stepcmd=ab_LiCSAR_mk_image.py
 stepsql=slcQry
 stepprev=''
 #rm $step.sh 2>/dev/null
 prepare_job_script $step $stepcmd $stepsql $stepprev
 ./$step.sh
 #mysql -h $mysqlhost -u $mysqluser -p$mysqlpass $mysqldbname < $SQLPath/slcQry.sql | grep $USER | grep $frame | sort -n > $step.list
 realjobno=`cat framebatch_01_mk_image.list | wc -l`

# for A in `seq $jobno_start $jobno_end`; do
#  echo bsub -o "$logdir/mk_image_$A.out" -e "$logdir/mk_image_$A.err" -Ep \"ab_LiCSAR_lotus_cleanup.py $A\" -J "mk_image_$A" \
#    -q $bsubquery -n 1 -W 12:00 ab_LiCSAR_mk_image.py $A >> framebatch_01_mk_image.sh
# done
 #chmod 770 $step.sh; ./$step.sh
 #wait $jobno_start $jobno_end

###################################################### Coregistering
 echo "..setting coregistration stage (RSLC)"

 step=framebatch_02_coreg
 stepcmd=ab_LiCSAR_coreg.py
 stepsql=rslcQry
 stepprev=framebatch_01_mk_image

 prepare_job_script $step $stepcmd $stepsql $stepprev
 
 ./$step.sh
###################################################### Make ifgs
 echo "..setting make_ifg job (IFG)"
 
 step=framebatch_03_mk_ifg
 stepcmd=ab_LiCSAR_mk_ifg.py
 stepsql=ifgQry
 stepprev=framebatch_02_coreg
 
 prepare_job_script $step $stepcmd $stepsql $stepprev
 ./$step.sh

###################################################### Unwrapping
 #date
 echo "..setting unwrapping (UNW)"
 #echo "updating jobno_start to unwrap"

 step=framebatch_04_unwrap
 stepcmd=ab_LiCSAR_unwrap.py
 stepsql=unwQry
 stepprev=framebatch_03_mk_ifg
 
 prepare_job_script $step $stepcmd $stepsql $stepprev
 ./$step.sh

echo "All bsub jobs are sent for processing."

###################################################### Gap Filling
echo "Preparing script for gap filling"
NBATCH=2
cat << EOF > framebatch_05_gap_filling.sh
echo "this is a preliminary version of gapfilling (but should work)"
framebatch_gapfill.sh $NBATCH
EOF
#LiCSAR_03_mk_ifgs_jw.py -f $frame -d `pwd` > trash
#sed 's/-//g' trash | awk '{print $1"_"$3}' | grep -v This > trash1
#for ifg in `cat trash1`; do ls -lh IFG/$ifg/$ifg.diff | grep cannot; done &>> trash2
#awk '{print $4}' trash2 | cut -c 5-21 | sed 's/_/ /g' > ifgs_missing.list
#rm trash*
chmod 770 framebatch_05_gap_filling.sh

###################################################### Geocoding to tiffs
echo "Preparing script for geocoding results"
cat << EOF > framebatch_06_geotiffs.sh
echo "You should better run this as: "
echo "bsub -q short-serial -n 1 ./framebatch_06_geotiffs.sh"
NOPAR=\`cat /proc/cpuinfo | awk '/^processor/{print \$3}' | wc -l\`
rm tmp_to_pub 2>/dev/null
rm tmp_to_pub.sh 2>/dev/null

for ifg in \`ls $BATCH_CACHE_DIR/$frame/IFG/*_* -d | rev | cut -d '/' -f1 | rev\`; do
 if [ -f $BATCH_CACHE_DIR/$frame/IFG/\$ifg/\$ifg.unw ]; then
  echo \$ifg >> $BATCH_CACHE_DIR/$frame/tmp_to_pub
 fi
done
echo "Generating geotiffs (parallelized)"
cat tmp_to_pub | parallel -j \$NOPAR create_geoctiffs_to_pub.sh $BATCH_CACHE_DIR/$frame
rm tmp_to_pub
EOF
chmod 770 framebatch_06_geotiffs.sh

###################################################### Baseline plot
echo "Preparing script for generating baseline plot"
#cat << EOF > framebatch_07_baseline_plot.sh
#queue=cpom-comet;t=12:00
#bsub -q $queue -W $t -o pix.out -e pix.err -J pix.txt 
#Jonathan's approach
#echo "Computing baselines"
#make_bperp_4_matlab.sh
#echo "Getting ratio of unwrapped pixels"
#echo "(has to be parallelized)"
#unwrapped_pixels_framebatch.sh > pix.out 2>pix.err
#paste ${frame}_bp.list unwrapped_pixel_percent.list > ${frame}_bp_unw.list
#echo "Generating baseline plot (takes time..)"
#parse_list.sh ${frame}_db_query.list > ${frame}_db.list
#baseline_qc_plot.sh ${frame}_bp_unw.list ${frame} 

cat << EOF > framebatch_07_baseline_plot.sh
make_bperp_4_matlab.sh
parse_list.sh ${frame}_scihub.list > ${frame}_scihub.dates
master=\`ls geo/*.lt | xargs -I XX basename XX .lt\`
ls RSLC/*/*.rslc.mli > base_calc.list.rslc
ls RSLC/*/*.rslc.mli.par > base_calc.list.rslc.par
paste base_calc.list.rslc base_calc.list.rslc.par > base_calc.list
rm base_calc.list.rslc base_calc.list.rslc.par
base_calc base_calc.list ./RSLC/\$master/\$master.rslc.mli.par bperp_aqs.list itab.list 0 0
rm base_calc.log base.out
bperp_framebatch.py -i bperp_aqs.list -f $frame -c 0
EOF
chmod 770 framebatch_07_baseline_plot.sh

# I disabled it since it wasn't really starting.. too complicated -w , I guess J
# bsub -o "$logdir/geotiffs.out" -e "$logdir/geotiffs.out" -J "geotiffs_$frame" \
# -q $bsubquery -n 1 -W 12:00 -w "$step5_wait" ./framebatch_05_geotiffs.sh
echo ""
echo ""
echo "...please check the results manually."
echo "You may be checking 'bjobs' or the spreadsheet:"
echo "https://docs.google.com/spreadsheets/d/1UcCmv8rqyMrDvjD0OAY2IT4HdSapvxXgWsKbbecXO9k"
echo "If everything is processed fine, including unwrapping,"
echo "you may run following to deactivate the frame from the spreadsheet:"
echo "module load licsar_framebatch"
echo setFrameInactive.py $frame
echo ".. and if not, try rerunning the framebatch_XX scripts in this folder:"
pwd
ls framebatch*.sh
echo ""
echo ""
#echo "Deactivating frame (will disappear from the spreadsheet)"
#echo "In order to activate it again, just do setFrameActive.py $frame"
#setFrameInactive.py $frame

exit

if [ $extra_steps -eq 1 ]; then
###################################################### Publishing tiffs
track=`echo $frame | cut -d '_' -f1 | rev | cut -c 2- | rev`
public=$LiCSAR_public
for geoifg in `ls $BATCH_CACHE_DIR/$frame/GEOC/2*_2* -d | rev | cut -d '/' -f1 | rev`; do
 if [ ! -d $public/$track/$frame/products/$geoifg ]; then
 echo "copying geocoded "$geoifg
 for toexp in cc.bmp cc.tif diff.bmp diff_mag.tif diff_pha.tif unw.bmp unw.tif disp.png; do
  if [ -f $BATCH_CACHE_DIR/$frame/GEOC/$geoifg/$geoifg.geo.$toexp ]; then
   mkdir -p $public/$track/$frame/products/$geoifg 2>/dev/null
   if [ ! -f $public/$track/$frame/products/$geoifg/$geoifg.geo.$toexp ]; then
    cp $BATCH_CACHE_DIR/$frame/GEOC/$geoifg/$geoifg.geo.$toexp $public/$track/$frame/products/$geoifg/.
   fi
  fi
 done
 else
  echo "geoifg "$geoifg" exists in public site. Skipping"
 fi
done

fi
