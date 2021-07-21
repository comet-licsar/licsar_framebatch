#!/bin/bash
# This function should fully update given frame by data from the last 3 months

if [ -z $1 ]; then
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
 echo "------"
 echo "Additional parameters (must be put DIRECTLY AFTER the command, before other/main parameters):"
 echo "-n ............... norun (processing scripts are generated but they will not start automatically)"
 echo "-c ............... perform check if files are in neodc and ingested to licsar database (no download performed)"
 echo "-S ............... store to lics database - CAREFUL WITH THIS (only for admins)"
 #echo "-G ............... update GACOS data after store to lics database"
 echo "-f ............... force processing in case the frame is already running in framebatch"
 echo "-E ............... after resampling, move to an area for copying to ARC4 EIDP"
 echo "-N ............... check if there are new acquisitions since the last run. If not, will cancel the processing"
 echo "-P ............... prioritise... i.e. run on comet queue (default: use short-serial where needed)"
 #echo "-R ............... prioritise through comet_responder queue"
# echo "-k YYYY-MM-DD .... generate kml for the ifg pairs containing given date (e.g. earthquake..)"
 #echo "geocode_to_public_website=0"
 exit;
fi
#export BATCH_CACHE_DIR=/work/scratch-nopw/licsar/earmla

NORUN=0
neodc_check=0
only_new_rslc=0
STORE=0
#according to CEDA, it should be ncores=16, i.e. one process per core. I do not believe it though. So keeping ncores=1.
#bsubncores=16
bsubncores=1
prioritise_nrt=0
EQR=0
force=0
#this switch is only working together with auto-store
dogacos=0

if [ $USER == 'earmla' ] || [ $USER == 'yma' ]; then 
 prioritise=1
else
 echo "Note: your query will go through a general queue"
 echo "(but you may use -P parameter to run through comet queue..)"
 prioritise=0
fi

#while [ "$1" != "" ]; do
#options to be c,n,S
#option=`echo $1 | rev | cut -d '-' -f1 | rev`
#case $option in
while getopts ":cnSEfNPRG" option; do
 case "${option}" in
  c) neodc_check=1; echo "performing check if files exist in neodc and are ingested to licsar db";
     ;;
  n) NORUN=1; echo "No run option. Scripts will be generated but not start automatically";
     ;;
  S) STORE=1; echo "After the processing, data will be stored to db and public dir";
  if [ $USER == 'yma' ]; then deleteafterstore=0; echo "(not deleting it after store..";
  else
     deleteafterstore=1;
  fi
     NORUN=0;
     ;;
  G) dogacos=1; echo "after store-to-curdir, we will also update GACOS data";
     ;;
  E) EQR=1; echo "option to make it ready for Earthquake Responder";
     prioritise_nrt=1; #make it through comet_responder
     ;;
  f) force=1; echo "bypassing check of existing processing of the frame";
     ;;
  P) prioritise=1; echo "prioritising - using comet queue in all steps";
     ;;
  R) prioritise_nrt=1; echo "prioritising through comet_responder";
     ;;
  N) only_new_rslc=1; echo "Checking if new images appeared since the last processing";
     ;;
 esac
done
#shift
shift $((OPTIND -1))

#getting to proper work directory
if [ -z $BATCH_CACHE_DIR ] || [ ! -d $BATCH_CACHE_DIR ]; then
 echo "There is no BATCH_CACHE_DIR existing. Did you define it properly?"
 exit
fi

#2021/02 - fix to have batchdir at LiCSAR_temp
if [ -z $LiCSAR_temp ]; then
 echo "LiCSAR_temp not set - did you do module load licsar_framebatch?"
 exit
fi

#while [ -f $BATCH_CACHE_DIR'.lock' ]; do
# echo "batchdir locked by other sync process, wait"
# echo "or just do: rm "$BATCH_CACHE_DIR'.lock'
# sleep 1000
#done
#if [ ! -d $LiCSAR_temp/batchdir ] || [ ! -L $BATCH_CACHE_DIR ]; then
#if [ ! -d $LiCSAR_temp/batchdir ]; then
# echo "update 02/2021: moving your batchdir automatically to LiCSAR_temp - and linking so it would not do a change to you."
# echo "please wait - depending on the size, this operation can take 10s minutes"
# echo "(you can of course cancel anytime, but it will start again with licsar_make_frame.sh)"
# echo "... but also note that data in BATCH_CACHE_DIR will now be deleted in 3 (?) months"
# touch $BATCH_CACHE_DIR'.lock' 2>/dev/null
# mkdir $LiCSAR_temp/batchdir 2>/dev/null
# rsync -r -l $BATCH_CACHE_DIR/* $LiCSAR_temp/batchdir 2>/dev/null
# echo "data sync finished, updating the BATCH_CACHE_DIR now"
# mv $BATCH_CACHE_DIR $BATCH_CACHE_DIR'.temp'
# ln -s $LiCSAR_temp/batchdir $BATCH_CACHE_DIR
# rm $BATCH_CACHE_DIR'.lock' 2>/dev/null
#fi
#if [ -d $BATCH_CACHE_DIR'.temp' ]; then
# echo "rsyncing once again"
# rsync -r -l $BATCH_CACHE_DIR'.temp'/* $LiCSAR_temp/batchdir 2>/dev/null
# rm -rf $BATCH_CACHE_DIR'.temp'
# rm $BATCH_CACHE_DIR'.lock' 2>/dev/null
#fi

#export BATCH_CACHE_DIR=$LiCSAR_temp/batchdir

# 03/2019 - we started to use scratch-nopw disk as a possible solution for constant stuck job problems
# after JASMIN update to Phase 4
if [ ! -d /work/scratch-nopw/licsar/$USER ]; then mkdir /work/scratch-nopw/licsar/$USER; fi
if [ ! -d /work/scratch-pw/licsar/$USER ]; then mkdir /work/scratch-pw/licsar/$USER; fi
if [ ! -d $LiCSAR_temp ]; then mkdir -p $LiCSAR_temp; fi

#if [ ! -d /work/scratch/licsar/$USER ]; then mkdir /work/scratch/licsar/$USER; fi

basefolder=$BATCH_CACHE_DIR
echo 'Processing in your BATCH_CACHE_DIR that is '$BATCH_CACHE_DIR

#startup variables
frame=$1
if [ `echo $frame | cut -d '_' -f2` == "SM" ]; then SM=1; echo "processing stripmap frame - WARNING, EXPERIMENTAL FEATURE"; else SM=0; fi
track=`echo $frame | cut -c -3 | sed 's/^0//' | sed 's/^0//'`
if [ ! -d $LiCSAR_procdir/$track/$frame/geo ]; then echo "This frame has not been initialized. Please contact your LiCSAR admin (Milan)"; exit; fi
#some older frames would not have this folder
mkdir $LiCSAR_procdir/$track/$frame/LUT 2>/dev/null


#run only if the frame is not in active processing..
if [ $force -eq 0 ]; then
  framestatus=`getFrameStatus.py $frame 1`
  if [ ! $framestatus == 'inactive' ]; then 
    echo "this frame is already active in framebatch.";
    echo "you may either contact user "$framestatus
    echo "or cancel the processing using setFrameInactive.py "$frame
    exit;
  fi
fi

enddate=`date -d '22 days ago' +%Y-%m-%d`

#settings of full_scale and extra_steps - by default 0
#these extra_steps are now just 'export to comet website'
if [ ! -z $2 ]; then full_scale=$2; else full_scale=0; fi
if [ ! -z $3 ]; then fillgaps=$3; else fillgaps=$full_scale; fi #ye, if only last 3 months then we should not need fillgaps
if [ ! -z $4 ]; then 
 startdate=$4; full_scale=1;
 if [ `echo $startdate | cut -c8` != '-' ]; then echo "You provided wrong startdate: "$startdate; exit; fi
 else startdate="2014-10-01";
fi
if [ ! -z $5 ]; then
 enddate=$5;
 if [ `echo $enddate | cut -c8` != '-' ]; then echo "You provided wrong enddate: "$enddate; exit; fi
fi
if [ ! -z $6 ]; then extra_steps=$6; else extra_steps=0; fi

if [ $full_scale -eq 1 ]; then
 datespread=`datediff $startdate $enddate`
 maxepochs=`echo $datespread/6 | bc`
 #assuming this number of epochs per job:
 eperjob=9
 no_of_jobs=`echo 1+$maxepochs/$eperjob | bc`
 #if [ $startdate == "2014-10-01" ]; then
  echo "WARNING:"
  echo "You have chosen to process in full scale"
  echo "This makes sense only if you have already done (two days ago) the nla request, i.e."
  echo "LiCSAR_0_getFiles.py -f FRAME etc. -- see documentation"
  #this number was here before - but had to decrease since we use only 1 processor now, job time limit is 24h and coreg may take up to 2h (actually less) per image
  #no_of_jobs=40
  #no_of_jobs=20
 #else
 # no_of_jobs=12
 #fi
else
 no_of_jobs=8 #enough for last 3 months data
 startdate=`date -d '91 days ago' +%Y-%m-%d`
fi

#decide for query based on user rights
if [ $prioritise -eq 1 ]; then
  bsubquery='comet'
  bsubquery_multi='comet'
else
  bsubncores=1
  bsubquery='short-serial'
  bsubquery_multi='par-single'
fi
#but actually if this is for earthquake responder, put it to comet_responder:
if [ $prioritise_nrt -eq 1 ]; then
 bsubquery='comet_responder'
 bsubquery_multi='comet_responder'
fi

#if [ `bugroup | grep $USER | gawk {'print $1'} | grep -c cpom_comet` -eq 1 ]; then
#  bsubquery='cpom-comet'
# else
#  bsubquery='par-single'
  #this one is for multinode.. let's keep it in one only
  #bsubquery='short-serial'
#fi
#echo "debu 0"

#testing.. but perhaps helps in getting proper num threads in CEMS environment
#export OMP_NUM_THREADS=16
export OMP_NUM_THREADS=1

#getting access to database
mysqlhost=`grep ^Host $framebatch_config | cut -d ':' -f2 | sed 's/^\ //'`
mysqluser=`grep ^User $framebatch_config | cut -d ':' -f2 | sed 's/^\ //'`
mysqlpass=`grep ^Password $framebatch_config | cut -d ':' -f2 | sed 's/^\ //'`
mysqldbname=`grep ^DBName $framebatch_config | cut -d ':' -f2 | sed 's/^\ //'`
SQLPath=`grep ^SQLPath $framebatch_config | cut -d '=' -f2 | sed 's/^\ //'`
#i should test it here..

#echo "debu 1"
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
#echo "debu 2"

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

#echo "debu 3"

function prepare_job_script {
 step=$1
 stepcmd=$2
 stepsql=$3
 stepprev=$4
 
 rm $step.sh $step.wait.sh 2>/dev/null
 rm $step'.nowait.sh' 2>/dev/null
 rm $step.list 2>/dev/null
# mysql command is much faster, but it is not available in every server:
if [ ! -z `which mysql 2>/dev/null` ]; then
 mysql -h $mysqlhost -u $mysqluser -p$mysqlpass $mysqldbname < $SQLPath/$stepsql.sql | grep $USER | grep $frame | sort -n > $step.list
 echo "mysql -h $mysqlhost -u $mysqluser -p$mysqlpass $mysqldbname < $SQLPath/$stepsql.sql | grep $USER | grep $frame | sort -n" > $step.sql
else
 cat << EOF > getit.py
#!/usr/bin/env python
import pandas as pd
from batchDBLib import engine
from configLib import config
sqlPath = config.get('Config','SQLPath')
QryFile = open(sqlPath+'/$stepsql.sql','r')
if QryFile:
    Qry = QryFile.read()
    DatFrm = pd.read_sql_query(Qry,engine)
    DatFrm = DatFrm.query('Frame == "$frame" and User == "$USER"')
    try:
        DatFrm.to_csv('$step.list', header=False, index=False, sep='\t', mode='w')
    except:
        print('ERROR - the list is probably empty')
    QryFile.close()
else:
    print('Could not open SQL query file')
EOF
 python ./getit.py
 mv getit.py $step.sql
 #too quick to write to disk J
 #wow, 5 seconds waiting was not enough!!!!! 
 #echo "waiting 10 seconds. Should be enough to synchronize data write from python"
 #echo "(what a problem in the age of supercomputers..)"
 #sleep 10
 #wc -l $step.list
 cat $step.list | grep $USER | grep $frame | sort -n > $step.list2
 mv $step.list2 $step.list 
fi
chmod 777 $step.sql

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
   #need to wait for coreg and will wait also for ifg step
   #the waiting of unwrap to mk_ifg should be improved! this way is safer but will wait for more than necessary
   if [ $step == 'framebatch_03_mk_ifg' ] || [ $step == 'framebatch_04_unwrap' ]; then
    for image in `grep ^$jobid $step.list | gawk {'print $4'}`; do
     #get jobid from previous step that is connected to this image
     grep $image $stepprev.list | gawk {'print $1'} >> tmpText
    done
   fi
   for jobid_prev in `cat tmpText | sort -nu`; do
    waitText=$waitText" && ended("$jobid_prev"_"$stepprev")"
   done
   waitText=`echo $waitText | cut -c 4-`
   waitcmd='-w "'$waitText'"'
  fi

  #if [ $bsubquery == "short-serial" ]; then
  #this is an improvemet for cpom-comet queues - we can request additional RAM within this queue
  #if [ $bsubquery != "cpom-comet" ]; then
  #extrabsub='-x'
  #else
  if [ $bsubquery == "cpom-comet" ]; then
   if [ $step == "framebatch_02_coreg" ] || [ $step == "framebatch_04_unwrap" ]; then
    #maxmem=25000
    maxmem=16000
    extrabsub='-R "rusage[mem='$maxmem']" -M '$maxmem
   fi
  fi
  #get expected time
  notoprocess=`grep -c $jobid $step.list`
  if [ $step == 'framebatch_01_mk_image' ]; then hoursperone=0.9; fi
  if [ $step == 'framebatch_02_coreg' ]; then hoursperone=1.9; fi
  if [ $step == 'framebatch_03_mk_ifg' ]; then hoursperone=0.4; fi
  if [ $step == 'framebatch_04_unwrap' ]; then hoursperone=1.5; fi
  #to be included also number of bursts per frame...
  exptime=`echo $hoursperone*$notoprocess+1.5 | bc | cut -d '.' -f1`
  if [ $exptime -gt 23 ]; then exptime=23; fi
  if [ $exptime -lt 10 ]; then exptime=0$exptime; fi
  echo bsub2slurm.sh -o "$logdir/$step"_"$jobid.out" -e "$logdir/$step"_"$jobid.err" -Ep \"ab_LiCSAR_lotus_cleanup.py $jobid\" -J "$jobid"_"$step" \
     -q $bsubquery -n $bsubncores -W $exptime:59 $extrabsub $waitcmd $stepcmd $jobid >> $step.wait.sh
  echo bsub2slurm.sh -o "$logdir/$step"_"$jobid.out" -e "$logdir/$step"_"$jobid.err" -Ep \"ab_LiCSAR_lotus_cleanup.py $jobid\" -J "$jobid"_"$step" \
     -q $bsubquery -n $bsubncores -W $exptime:59 $extrabsub $stepcmd $jobid >> $step'.nowait.sh'
 done
 
 rm tmpText 2>/dev/null
 chmod 770 $step.wait.sh $step'.nowait.sh'
}

## MAIN CODE
############### 
 if [ $only_new_rslc -eq 1 ]; then
  newrslc=`checkNewRslc.py $frame`
  if [ $newrslc -eq 0 ]; then
   echo "No new image was acquired since last run - exiting"
   if [ `ls $BATCH_CACHE_DIR/$frame | wc -l` -eq 1 ]; then
    cd $BATCH_CACHE_DIR
    rm -rf $frame
   fi
   exit
  fi
  echo "There are "$newrslc" new images to process since the last run"
 fi

date
setFrameInactive.py $frame
echo "Activating the frame"
setFrameActive.py $frame

if [ $full_scale -eq 0 ]; then
#if we work only in last 3 months data
 if [ $fillgaps -eq 1 ]; then
  echo "Refilling the data gaps (should be ok for last 3 months data)"
  framebatch_data_refill.sh $frame `date -d "90 days ago" +'%Y-%m-%d'`
 elif [ $neodc_check -eq 1 ]; then
  echo "Checking if the files are ingested to licsar database"
  framebatch_data_refill.sh -c $frame `date -d "90 days ago" +'%Y-%m-%d'` `date +'%Y-%m-%d'`
 fi
 echo "Preparing the frame cache (last 3 months)"
 echo "..may take some 5 minutes"
 #createFrameCache_last3months.py $frame $no_of_jobs > tmp_jobid.txt
 createFrameCache.py $frame $no_of_jobs `date -d "90 days ago" +'%Y-%m-%d'` `date -d "22 days ago" +'%Y-%m-%d'` > tmp_jobid.txt
else
#if we want to fill gaps throughout the whole time period
 if [ $fillgaps -eq 1 ]; then
  echo "Refilling the data gaps"
  framebatch_data_refill.sh $frame $startdate $enddate
 elif [ $neodc_check -eq 1 ]; then
  echo "Checking if the files are ingested to licsar database"
  framebatch_data_refill.sh -c $frame $startdate $enddate
 fi
 echo "Preparing the frame cache (full scale processing)"
 echo "..may take some 15 minutes or (much) more"
 echo "(recommending using tmux or screen here..)"
 createFrameCache.py $frame $no_of_jobs $startdate $enddate > tmp_jobid.txt
 #ok, let's fix also the stuff already existing...
 if [ -d $LiCSAR_public/$track/$frame/interferograms ]; then
  mkdir GEOC 2>/dev/null
  for ifg in `ls $LiCSAR_public/$track/$frame/interferograms`; do
    if [ `echo $ifg | cut -d '_' -f1` -ge `echo $startdate | sed 's/-//g'` ]; then
    if [ `echo $ifg | cut -d '_' -f2` -le `echo $enddate | sed 's/-//g'` ]; then
     if [ -f $LiCSAR_public/$track/$frame/interferograms/$ifg/$ifg.geo.unw.tif ]; then
      if [ ! -d GEOC/$ifg ]; then 
       ln -s $LiCSAR_public/$track/$frame/interferograms/$ifg `pwd`/GEOC/$ifg
      fi
     fi
    fi
    fi
  done
 fi
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
 
 #getting jobIDs for mk_image:
 step=framebatch_01_mk_image
 stepcmd=ab_LiCSAR_mk_image.py
 stepsql=slcQry
 stepprev=''
 prepare_job_script $step $stepcmd $stepsql $stepprev
 rm $step.wait.sh
 if [ $NORUN -eq 0 ]; then
  ./$step.nowait.sh
 else
  echo "To run this step, use ./"$step".nowait.sh"
 fi
 
 realjobno=`cat framebatch_01_mk_image.list | wc -l`

###################################################### Coregistering
 echo "..setting coregistration stage (RSLC)"

 step=framebatch_02_coreg
 stepcmd=ab_LiCSAR_coreg.py
 stepsql=rslcQry
 stepprev=framebatch_01_mk_image

 prepare_job_script $step $stepcmd $stepsql $stepprev
 if [ $NORUN -eq 0 ]; then
  ./$step.wait.sh
 else
  echo "To run this step, use ./"$step".nowait.sh"
 fi


#add second iteration for coreg....
#cat << EOF > framebatch_x_second_iteration.sh
waiting_str=''
for jobid in `cat framebatch_02_coreg.wait.sh | rev | gawk {'print $1'} | rev`; do
  stringg=$jobid"_framebatch_02_coreg"
  waiting_str=$waiting_str" && ended("$stringg")"
done
waiting_string=`echo $waiting_str | cut -c 4-`
echo "./framebatch_02_coreg.nowait.sh; ./framebatch_03_mk_ifg.wait.sh; ./framebatch_04_unwrap.wait.sh" > ./framebatch_x_second_iteration.nowait.sh
echo "bsub2slurm.sh -w '"$waiting_string"' -q "$bsubquery" -W 00:30 -n 1 -J it2_"$frame" -o LOGS/it2.out -e LOGS/it2.err ./framebatch_x_second_iteration.nowait.sh" > framebatch_x_second_iteration.wait.sh
chmod 770 framebatch_x_second_iteration.wait.sh framebatch_x_second_iteration.nowait.sh
if [ $NORUN -eq 0 ]; then
 ./framebatch_x_second_iteration.wait.sh
fi

#~ if [ $NORUN -eq 0 ]; then
  #~ echo "setting second itera"
  #~ mkdir tmpbck
  #~ mv framebatch_02_coreg* tmpbck/.

 #~ step=framebatch_02_coreg
 #~ stepcmd=ab_LiCSAR_coreg.py
 #~ stepsql=rslcQry
 #~ stepprev=framebatch_02_coreg

 #~ prepare_job_script $step $stepcmd $stepsql $stepprev
 
 #~ waiting_str=''
 #~ for jobid in \`cat tmpbck/framebatch_02_coreg.sh | rev | gawk {'print \$1'} | rev\`; do
  #~ stringg="framebatch_02_coreg_"\$jobid
  #~ waiting_str=\$waiting_str" && ended("\$stringg")"
 #~ done
 #~ waiting_string=\`echo \$waiting_str | cut -c 4-\`
 #~ echo "bsub2slurm.sh -w '"\$waiting_string"' -q $bsubquery -W 08:00 -n 1 -J framebatch_02_coreg_$frame -o LOGS/framebatch_02_coreg_2.out -e LOGS/framebatch_02_coreg_2.err ./framebatch_02_coreg_nowait.sh" > framebatch_02_coreg_2.sh
 #~ chmod 770 framebatch_02_coreg_2.sh

 #~ ./framebatch_02_coreg_2.sh
  #~ ./$step.sh
 #~ #else
 #~ # echo "To run this step, use ./"$step".sh"
 #~ fi
#~ rm -r tmpbck

################################################# in case of EQR=1, prepare it:
if [ $EQR -eq 1 ]; then
cat << EOF > framebatch_eqr.nowait.sh
if [ ! -z \$1 ]; then
 waiting_str=''
 for jobid in \`cat framebatch_02_coreg.wait.sh | rev | gawk {'print \$1'} | rev\`; do
  stringg=\$jobid"_framebatch_02_coreg"
  waiting_str=\$waiting_str" && ended("\$stringg")"
 done
 waiting_string=\`echo \$waiting_str | cut -c 4-\`
 echo "bsub2slurm.sh -w '"\$waiting_string"' -q $bsubquery -W 02:00 -n 1 -J EQR_$frame -o LOGS/EQR.out -e LOGS/EQR.err ./framebatch_eqr.nowait.sh" > framebatch_eqr.wait.sh
 chmod 770 framebatch_eqr.wait.sh
 ./framebatch_eqr.wait.sh
else
 framebatch_eqr.sh $NBATCH
fi
EOF
chmod 770 framebatch_eqr.nowait.sh
if [ $NORUN -eq 0 ]; then
 #./framebatch_eqr.sh -w
 echo "./framebatch_eqr.nowait.sh -w" >> framebatch_x_second_iteration.wait.sh
else
 echo "To run this step, use ./framebatch_eqr.nowait.sh"
fi
fi
###################################################### Make ifgs
 echo "..setting make_ifg job (IFG)"
 
 step=framebatch_03_mk_ifg
 stepcmd=ab_LiCSAR_mk_ifg.py
 stepsql=ifgQry
 stepprev=framebatch_02_coreg
 
 prepare_job_script $step $stepcmd $stepsql $stepprev
 if [ $NORUN -eq 0 ]; then
   if [ -f $step.wait.sh ]; then
    ./$step.wait.sh
   else
    echo "ERROR: no mk_ifg script exists - perhaps not enough of input data. Exiting (keeping processing, so you may store at least coregistered files and their LUTs)"
    exit
   fi
 else
  echo "To run this step, use ./"$step".x.sh"
 fi

###################################################### Unwrapping
 echo "..setting unwrapping (UNW)"

 step=framebatch_04_unwrap
 stepcmd=ab_LiCSAR_unwrap.py
 stepsql=unwQry
 stepprev=framebatch_03_mk_ifg
 
 prepare_job_script $step $stepcmd $stepsql $stepprev
 if [ $NORUN -eq 0 ]; then
  ./$step.wait.sh
 echo "All bsub jobs are sent for processing."
 else
  echo "To run this step, use ./"$step".x.sh, where x=nowait would start immediately while wait will start after finishing the previous stage"
 fi



###################################################### Gap Filling
echo "Preparing script for gap filling"
NBATCH=2  #max number of ifgs per job. it was 4 originally..
gpextra=''
#added skipping of check for existing scratchdir/frame for gapfilling - just automatically delete it...
gpextra='-o '
#if [ $NORUN -eq 0 ]; then
 #update 04/2021 - use of geocoded products
# gpextra=$gpextra"-g "
#fi
if [ $NORUN -eq 0 ] && [ $STORE -eq 1 ]; then
 gpextra=$gpextra"-S "
 touch .processing_it1
fi
if [ $prioritise -eq 1 ]; then
 gpextra=$gpextra"-P "
fi

cat << EOF > framebatch_05_gap_filling.nowait.sh
echo "The gapfilling will use RSLCs in your work folder and update ifg or unw that were not generated (in background - check bjobs)"
if [ ! -z \$1 ]; then
 waiting_str=''
 for jobid in \`cat framebatch_04_unwrap.wait.sh | rev | gawk {'print \$1'} | rev\`; do
  stringg=\$jobid"_framebatch_04_unwrap"
  waiting_str=\$waiting_str" && ended("\$stringg")"
 done
 waiting_string=\`echo \$waiting_str | cut -c 4-\`
 echo "bsub2slurm.sh -w '"\$waiting_string"' -q $bsubquery -W 10:00 -n 1 -J framebatch_05_gap_filling_$frame -o LOGS/framebatch_05_gap_filling.out -e LOGS/framebatch_05_gap_filling.err ./framebatch_05_gap_filling.nowait.sh" > framebatch_05_gap_filling.wait.sh
 chmod 770 framebatch_05_gap_filling.wait.sh
 ./framebatch_05_gap_filling.wait.sh
else
 framebatch_gapfill.sh $gpextra $NBATCH
fi
EOF
chmod 770 framebatch_05_gap_filling.nowait.sh
#if [ $NORUN -eq 0 ] && [ $STORE -lt 1 ]; then
#this below option means that even in AUTOSTORE, the gapfilling will be performed...
#in this case, however, it will be sent to bsub together with geotiff generation script
#so.. more connections now depend on 'luck having to wait for bsub2slurm.sh -x'
#this definitely needs improvement, yet better 'than nothing'.. i suppose
if [ $NORUN -eq 0 ]; then
 ./framebatch_05_gap_filling.nowait.sh -w
else
 echo "To run gapfilling afterwards, use ./framebatch_gapfill.sh"
fi




###################################################### Geocoding to tiffs
echo "Preparing script for geocoding results (will be auto-run by gap_filling routine)"
cat << EOF > framebatch_06_geotiffs.wait.sh
NOPAR=1
MAXPAR=10
frame=$frame

#let's have 10 epochs per cpu
imgpercpu=10
noimgs=\`wc -l framebatch_01_mk_image.list | gawk {'print \$1'}\`
if [ \$noimgs -gt 0 ]; then
 let NOPAR=1+\$noimgs/\$imgpercpu
 if [ \$NOPAR -gt \$MAXPAR ]; then NOPAR=\$MAXPAR; fi
fi
EOF
cp framebatch_06_geotiffs.wait.sh framebatch_06_geotiffs.nowait.sh


#in case of EQR, do also full size previews - as these will be used for KML
if [ $EQR -eq 1 ]; then
 extracmdgeo=1
else
 extracmdgeo=''
fi

echo "bsub2slurm.sh -q $bsubquery_multi -W 07:00 -J $frame'_geo' -n \$NOPAR -o LOGS/framebatch_06_geotiffs.out -e LOGS/framebatch_06_geotiffs.err framebatch_LOTUS_geo.sh \$NOPAR $extracmdgeo" >> framebatch_06_geotiffs.nowait.sh
#echo "bsub2slurm.sh -q $bsubquery_multi -W 07:00 -J $frame'_geo' -n \$NOPAR -o LOGS/framebatch_06_geotiffs.out -e LOGS/framebatch_06_geotiffs.err framebatch_LOTUS_geo.sh \$NOPAR $extracmdgeo" >> framebatch_06_geotiffs.wait.sh
chmod 770 framebatch_06_geotiffs*.sh


#ok, but the core script will run only after unwrapping jobs are finished..
waiting_str=''
for jobid in `cat framebatch_04_unwrap.wait.sh | rev | gawk {'print $1'} | rev`; do
 stringg=$jobid"_framebatch_04_unwrap"
 waiting_str=$waiting_str" && ended("$stringg")"
done
waiting_string=`echo $waiting_str | cut -c 4-`
#echo "bsub2slurm.sh -w '"$waiting_string"' -J $frame'_geo' -n \$NOPAR -q $bsubquery_multi -W 08:00 -o LOGS/framebatch_06_geotiffs.out -e LOGS/framebatch_06_geotiffs.err framebatch_LOTUS_geo.sh \$NOPAR $extracmdgeo" >> framebatch_06_geotiffs.sh
#echo "bsub2slurm.sh -w '"$waiting_string"' -J $frame'_geo' -n \$NOPAR -q $bsubquery_multi -W 08:00 -o LOGS/framebatch_06_geotiffs.out -e LOGS/framebatch_06_geotiffs.err framebatch_LOTUS_geo.sh \$NOPAR $extracmdgeo" >> framebatch_06_geotiffs.sh

if [ $STORE -eq 1 ]; then
 echo "Making the system automatically store the generated data (for auto update of frames)"
 echo "cd $BATCH_CACHE_DIR" >> framebatch_06_geotiffs.nowait.sh
 #echo "echo 'waiting 60 seconds for jobs to synchronize'" >> framebatch_06_geotiffs_nowait.sh
 #echo "sleep 60" >> framebatch_06_geotiffs_nowait.sh
 echo "bsub2slurm.sh -q $bsubquery -n 1 -W 06:00 -o LOGS/framebatch_$frame'_store.out' -e LOGS/framebatch_$frame'_store.err' -J $frame'_ST' store_to_curdir.sh $frame $deleteafterstore 0 $dogacos" >> framebatch_06_geotiffs.nowait.sh #$frame
 echo "bsub2slurm.sh -w '"$waiting_string"' -q $bsubquery -n 1 -W 06:00 -o LOGS/framebatch_$frame'_store.out' -e LOGS/framebatch_$frame'_store.err' -J $frame'_ST' store_to_curdir.sh $frame $deleteafterstore 0 $dogacos" >> framebatch_06_geotiffs.wait.sh #$frame
 #echo "bsub2slurm.sh -w $frame'_geo' -q $bsubquery -n 1 -W 06:00 -o LOGS/framebatch_$frame'_store.out' -e LOGS/framebatch_$frame'_store.err' -J $frame'_ST' store_to_curdir.sh $frame $deleteafterstore" >> framebatch_06_geotiffs_nowait.sh #$frame
 #cd -
fi

#this is not wanted now as i use auto-geotiffing after framebatch_gapfill...
#if [ $NORUN -eq 0 ]; then
# echo "Sending geocoding script to the LOTUS job waitlist"
# ./framebatch_06_geotiffs.sh
#fi

###################################################### Baseline plot
echo "Preparing script for generating baseline plot"
#cat << EOF > framebatch_07_baseline_plot.sh
#queue=cpom-comet;t=12:00
#bsub2slurm.sh -q $queue -W $t -o pix.out -e pix.err -J pix.txt 
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


##################################################### auto-store to LiCSAR_procdir and LiCSAR_public
#if [ $STORE -eq 1 ]; then
# echo "Making the system automatically store the generated data (for auto update of frames)"
# cd $BATCH_CACHE_DIR
# bsub2slurm.sh -w $frame'_geo' -q cpom-comet -n 1 -W 08:00 -o LOGS/framebatch_$frame'_store.out' -e LOGS/framebatch_$frame'_store.err' -J $frame'_ST' store_to_curdir.sh $frame $deleteafterstore #$frame
# cd -
#fi


# I disabled it since it wasn't really starting.. too complicated -w , I guess J
# bsub2slurm.sh.sh -o "$logdir/geotiffs.out" -e "$logdir/geotiffs.out" -J "geotiffs_$frame" \
# -q $bsubquery -n 1 -W 12:00 -w "$step5_wait" ./framebatch_05_geotiffs.sh
echo ""
echo ""
echo "...please check the results manually."
echo "You may want checking 'bjobs.sh' "
#echo "https://docs.google.com/spreadsheets/d/1UcCmv8rqyMrDvjD0OAY2IT4HdSapvxXgWsKbbecXO9k"
echo "If everything is processed fine, including unwrapping,"
echo "you may run store_to_curdir.sh "$frame" - this will store and also deactivate the frame to be used by others"
#echo "module load licsar_framebatch"
#echo setFrameInactive.py $frame
echo ".. and if not, try rerunning the framebatch_XX scripts in this folder:"
pwd
ls framebatch*.sh
echo ""
echo ""



#some additional rather debug thingz
mkdir log tab 2>/dev/null
master=`ls geo/*.hgt | cut -d '/' -f2 | cut -d '.' -f1`
#if [ ! -f tab/$master'_tab' ]; then
cp $LiCSAR_procdir/$track/$frame/tab/$master'_tab' tab/.
#fi



exit

if [ $extra_steps -eq 1 ]; then
###################################################### Publishing tiffs
track=`echo $frame | cut -d '_' -f1 | rev | cut -c 2- | rev`
public=$LiCSAR_public
for geoifg in `ls $BATCH_CACHE_DIR/$frame/GEOC/2*_2* -d | rev | cut -d '/' -f1 | rev`; do
 if [ ! -d $public/$track/$frame/interferograms/$geoifg ]; then
 echo "copying geocoded "$geoifg
 for toexp in cc.bmp cc.tif diff.bmp diff_mag.tif diff_pha.tif unw.bmp unw.tif; do #disp.png; do
  if [ -f $BATCH_CACHE_DIR/$frame/GEOC/$geoifg/$geoifg.geo.$toexp ]; then
   mkdir -p $public/$track/$frame/interferograms/$geoifg 2>/dev/null
   if [ ! -f $public/$track/$frame/interferograms/$geoifg/$geoifg.geo.$toexp ]; then
    cp $BATCH_CACHE_DIR/$frame/GEOC/$geoifg/$geoifg.geo.$toexp $public/$track/$frame/interferograms/$geoifg/.
   fi
  fi
 done
 else
  echo "geoifg "$geoifg" exists in public site. Skipping"
 fi
done

fi
