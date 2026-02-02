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
 echo "-S ............... store to lics database - only for users in gws_lics_admin"
 echo "-S -d ............ set autodelete if everything went fine (careful..)"
 #echo "-G ............... update GACOS data after store to lics database"
 echo "-f ............... force processing in case the frame is already running in framebatch"
 #echo "-E ............... after resampling, move to an area for copying to ARC4 EIDP"
 echo "-N ............... check if there are new acquisitions since the last run. If not, will cancel the processing"
 #echo "-P ............... prioritise... i.e. run on comet queue (default: use short-serial where needed)"
 echo "-A or -B ......... perform ifg gapfill (4 ifgs + extras) for only S1A/S1B"
 echo "-b ............... also do burst overlaps"
 echo "-R ............... also do rg (and azi) offsets"
 echo "-T ............... will run PROCESSING on terminal - workaround for LOTUS2 issues in Mar-Apr 2025"
 echo "-D .............. ignore autodownload limit - careful..."
 #echo "-R ............... prioritise through comet_responder queue"
# echo "-k YYYY-MM-DD .... generate kml for the ifg pairs containing given date (e.g. earthquake..)"
 #echo "geocode_to_public_website=0"
 exit;
fi
#export BATCH_CACHE_DIR=/work/scratch-nopw/licsar/earmla
source $LiCSARpath/lib/LiCSAR_bash_lib.sh

revisittime=5 # just to speed up the procedure, although some S1A/C might be only one day ... (may need to set 0 to avoid this check)
sensorgapfill=''
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
dogacos=1  # will do this now
tienshan=0
bovls=1
echo "warning: setting bovls ON by default"
terminal=0
deleteafterstore=0
#
#if [ $USER == 'earmla' ]; then
# prioritise=1
#else
# echo "Note: your query will go through a general queue"
# echo "(but you may use -P parameter to run through comet queue..)"
prioritise=0
extradatarefill=''
rgoff=0
# fi

while getopts ":cnSEfNPRGAbBDTd" option; do
 case "${option}" in
  D) extradatarefill='-A';
     ;;
  A) sensorgapfill="-A";
     ;;
  B) sensorgapfill="-B";
     ;;
  c) neodc_check=1; echo "performing check if files exist in neodc and are ingested to licsar db";
     ;;
  n) NORUN=1; echo "No run option. Scripts will be generated but not start automatically";
     ;;
  S) STORE=1; echo "After the processing, data will be stored to db and public dir - but not deleted";
  #if [ $USER == 'yma' ]; then deleteafterstore=0; echo "(not deleting it after store..";
  #else
     # deleteafterstore=0;
  #fi
     NORUN=0;
     ;;
  d) deleteafterstore=1; STORE=1; NORUN=0;
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
  R) rgoff=1;
     #prioritise_nrt=1; echo "prioritising through comet_responder";
     #force=1;
     #;;
     echo "will generate also rg offsets";
     ;;
  N) only_new_rslc=1; echo "Checking if new images appeared since the last processing";
     ;;
  b) bovls=1;
     ;;
  T) terminal=1; echo "will set things and run in terminal";
     NORUN=1;
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

if [ `echo $BATCH_CACHE_DIR | cut -d '-' -f 2 | cut -c -2` == 'pw' ]; then
  if [ `echo $BATCH_CACHE_DIR | cut -d '-' -f 2 | cut -c 3` -lt 4 ]; then
    echo "ERROR - you use old path in your BATCH_CACHE_DIR - you need to change it to the new scratch-pw4 or 5 disk in your ~/.bashrc"
    echo "you should then re-source the bashrc file, or re-log to JASMIN "
    exit
  fi
fi

#2021/02 - fix to have batchdir at LiCSAR_temp
if [ -z $LiCSAR_temp ]; then
 echo "LiCSAR_temp not set - did you do module load licsar_framebatch?"
 exit
else
  if [ `echo $LiCSAR_temp | cut -d '-' -f 2 | cut -c -2` == 'pw' ]; then
  if [ `echo $LiCSAR_temp | cut -d '-' -f 2 | cut -c 3` -lt 4 ]; then
    echo "ERROR - you have set some old LiCSAR_temp - please remove it from your ~/.bashrc (just comment out the line starting export LiCSAR_temp)"
    echo "you should then re-source the bashrc file, or re-log to JASMIN "
    exit
  fi
  fi
fi

# 03/2019 - we started to use scratch-nopw disk as a possible solution for constant stuck job problems
# after JASMIN update to Phase 4
#if [ ! -d /work/scratch-nopw/licsar/$USER ]; then mkdir /work/scratch-nopw/licsar/$USER; fi
#if [ ! -d /work/scratch-pw/licsar/$USER ]; then mkdir /work/scratch-pw/licsar/$USER; fi
# 11/2022 - new disk relocation to /work/scratch-pw3 - ok, let's keep this through module only
#if [ ! -d /work/scratch-pw3/licsar/$USER ]; then mkdir /work/scratch-pw3/licsar/$USER; fi
if [ ! -d $LiCSAR_temp ]; then mkdir -p $LiCSAR_temp; fi

#if [ ! -d /work/scratch/licsar/$USER ]; then mkdir /work/scratch/licsar/$USER; fi


#echo "DEBUG - COMET QUEUE IS NOW DOWN (2023-11-06). Setting to only standard queue"
#prioritise=0
#prioritise_nrt=0

#startup variables
frame=$1

# priority check for the possibly new data
if [ $only_new_rslc -gt 0 ]; then
if [ `get_frame_days_since_last_done_epoch $frame` -lt $revisittime ]; then
  echo "the frame "$frame" is fully up-to-date. Skipping"; exit
fi
fi



basefolder=$BATCH_CACHE_DIR
echo 'Processing in your BATCH_CACHE_DIR that is '$BATCH_CACHE_DIR


if [ -f $BATCH_CACHE_DIR/$frame/lmf_locked ]; then echo "the frame is locked - cancelling (delete lmf_locked file)"; exit; fi

mkdir -p $LiCSAR_temp/$frame'_envs' # need for step 01
if [ `echo $frame | cut -d '_' -f2` == "SM" ]; then SM=1; echo "processing stripmap frame - WARNING, EXPERIMENTAL FEATURE"; else SM=0; fi
track=`echo $frame | cut -c -3 | sed 's/^0//' | sed 's/^0//'`
if [ ! -d $LiCSAR_procdir/$track/$frame/geo ]; then echo "This frame has not been initialized. Please contact your LiCSAR admin (Milan)"; exit; fi
# fix empty slc file
m=`ls $LiCSAR_procdir/$track/$frame/SLC | head -n 1`
if [ -f $BATCH_CACHE_DIR/$frame/SLC/$m/$m.slc.par ]; then
 if [ `ls -al $BATCH_CACHE_DIR/$frame/SLC/$m/$m.slc.par | gawk {'print $5'}` -eq 0 ]; then
   echo "corrupted slc par file of reference epoch, fixing"
   cp $LiCSAR_procdir/$track/$frame/SLC/$m/$m.slc.par $BATCH_CACHE_DIR/$frame/SLC/$m/$m.slc.par
   cp $LiCSAR_procdir/$track/$frame/SLC/$m/$m.slc.par $BATCH_CACHE_DIR/$frame/RSLC/$m/$m.rslc.par
 fi
fi
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

# get some extra info from local_config.py - e.g. tienshan = 1
if [ -f $LiCSAR_procdir/$track/$frame/local_config.py ]; then
 #check tien shan
 if [ `grep -c tienshan $LiCSAR_procdir/$track/$frame/local_config.py` -gt 0 ]; then
   tienshan=`grep ^tienshan $LiCSAR_procdir/$track/$frame/local_config.py | cut -d '=' -f2 | sed 's/ //g'`
 fi
 # check bovls
 if [ `grep -c bovl $LiCSAR_procdir/$track/$frame/local_config.py` -gt 0 ]; then
   bovls=`grep ^bovl $LiCSAR_procdir/$track/$frame/local_config.py | cut -d '=' -f2 | sed 's/ //g'`
 fi
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
if [ -d $BATCH_CACHE_DIR/$frame ]; then
  touchscratch $BATCH_CACHE_DIR/$frame &
fi
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
# 12/2023: on LOTUS nodes, the mysql is now in different version and it does not work -- so, switching fully to python solution
#if [ ! -z `which mysql 2>/dev/null` ]; then
# mysql -h $mysqlhost -u $mysqluser -p$mysqlpass $mysqldbname < $SQLPath/$stepsql.sql | grep $USER | grep $frame | sort -n > $step.list
# echo "mysql -h $mysqlhost -u $mysqluser -p$mysqlpass $mysqldbname < $SQLPath/$stepsql.sql | grep $USER | grep $frame | sort -n" > $step.sql
#else
cat << EOF > getit.py
#!/usr/bin/env python
import pandas as pd
from batchDBLib import engine
from configLib import config
from sqlalchemy import text
sqlPath = config.get('Config','SQLPath')
QryFile = open(sqlPath+'/$stepsql.sql','r')
if QryFile:
    Qry = QryFile.read()
    Qry = Qry.split('WHERE')[0]+'WHERE polygs.polyid_name = "$frame" and jobs.user = "$USER" and polygs.active = TRUE;'
    with engine.connect() as conn:
        DatFrm = pd.read_sql_query(text(Qry),conn)
    #
    # DatFrm = DatFrm.query('Frame == "$frame" and User == "$USER"')
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
#fi
chmod 777 $step.sql
 exptimemax=1
 maxmaxmem=1024
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
  #if [ $bsubquery == "cpom-comet" ]; then
  burstsnum=`get_burstsno_frame $frame 2>/dev/null`
  if [ -z $burstsnum ]; then burstsnum=1; fi  # for SM
   if [ $step == "framebatch_02_coreg" ]; then # || [ $step == "framebatch_04_unwrap" ]; then
    #maxmem=25000
    maxmem=16384
    if [ $burstsnum -gt 45 ]; then maxmem=25000; fi
    if [ $burstsnum -ge 90 ]; then maxmem=32000; fi
    if [ $burstsnum -ge 120 ]; then maxmem=48000; fi
   elif [ $step == "framebatch_03_mk_ifg" ]; then
    maxmem=4096   # 4 GB should be ok for mk_ifg
    if [ $burstsnum -gt 45 ]; then maxmem=8192; fi
    if [ $burstsnum -ge 90 ]; then maxmem=16384; fi
    if [ $burstsnum -ge 120 ]; then maxmem=25000; fi
   elif [ $step == "framebatch_04_unwrap" ]; then
    maxmem=8192   # 8 GB for the unwrap_geo... should be ok
    if [ $burstsnum -gt 45 ]; then maxmem=16384; fi
    if [ $burstsnum -ge 90 ]; then maxmem=25000; fi
    if [ $burstsnum -ge 120 ]; then maxmem=32000; fi
   else
    #maxmem=4096  # 4 GB RAM should be enough for mk_imag, mk_ifg
    maxmem=12288  # but we still saw errors in applying orbits! errors removed using 8 GB RAM. so setting 12 GB RAM..
    if [ $burstsnum -gt 45 ]; then maxmem=16384; fi
    if [ $burstsnum -ge 90 ]; then maxmem=25000; fi
    if [ $burstsnum -ge 120 ]; then maxmem=32000; fi
   fi
   # update of JASMIN - they somehow decreased default memory... fixing this here for all jobs..
   #extrabsub='-R "rusage[mem='$maxmem']" -M '$maxmem
   extrabsub='-M '$maxmem
   if [ $maxmem -gt $maxmaxmem ]; then maxmaxmem=$maxmem; fi
   #fi
  #fi
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
  if [ $exptime -gt $exptimemax ]; then exptimemax=$exptime; fi
  echo bsub2slurm.sh -o "$logdir/$step"_"$jobid.out" -e "$logdir/$step"_"$jobid.err" -Ep \"ab_LiCSAR_lotus_cleanup.py $jobid\" -J "$jobid"_"$step" \
     -q $bsubquery -n $bsubncores -W $exptime:59 $extrabsub $waitcmd $stepcmd $jobid >> $step.wait.sh
  echo bsub2slurm.sh -o "$logdir/$step"_"$jobid.out" -e "$logdir/$step"_"$jobid.err" -Ep \"ab_LiCSAR_lotus_cleanup.py $jobid\" -J "$jobid"_"$step" \
     -q $bsubquery -n $bsubncores -W $exptime:59 $extrabsub $stepcmd $jobid >> $step'.nowait.sh'
 done
 
 rm tmpText 2>/dev/null
 
 # 06/2025: arrange as job array for LOTUS2:
 maxj=`cat $step.nowait.sh | wc -l`
 if [ $exptimemax -gt 23 ]; then qos='long'; echo "setting long qos"; else qos='standard'; fi
 if [ $bsubncores -gt 1 ]; then qos='high'; echo "setting high qos"; fi
 
 cat << EOF > $step.lotus2.sh
#!/bin/bash
#SBATCH --job-name=$frame.`echo $step | cut -c 12-`
#SBATCH --time=$exptimemax:59:00
#SBATCH --account=nceo_geohazards
#SBATCH --partition=standard
#SBATCH --qos=$qos
#SBATCH -o $logdir/%A.%a.out
#SBATCH -e $logdir/%A.%a.err
#SBATCH --array=1-$maxj
#SBATCH --mem-per-cpu=${maxmaxmem}M

CID=\`gawk 'NR=='\${SLURM_ARRAY_TASK_ID} $step.nowait.sh | gawk 'END {print \$NF}'\`
$stepcmd \$CID
ab_LiCSAR_lotus_cleanup.py \$CID
EOF
 chmod 770 $step.wait.sh $step'.nowait.sh' $step.lotus2.sh
}

## MAIN CODE
############### 
 if [ $only_new_rslc -eq 1 ]; then
  newrslc=`checkNewRslc.py $frame | tail -n1`
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

 #doing refill/db check
 if [ $fillgaps -eq 1 ]; then
  echo "Refilling the data gaps"
  framebatch_data_refill.sh $extradatarefill $frame $startdate $enddate
 elif [ $neodc_check -eq 1 ]; then
  echo "Checking if the files are ingested to licsar database"
  framebatch_data_refill.sh -c $frame $startdate $enddate
 fi

 echo "Preparing the frame cache (full scale processing)"
 echo "..may take some 15 minutes or (much) more"
 echo "(recommending using tmux or screen here..)"
 createFrameCache.py $frame $no_of_jobs $startdate $enddate > tmp_jobid.txt
 
 # 2021-11-15: createFrameCache will now output also updated startdate and enddate to tmp_jobid.txt
 if [ `grep -c ^updated tmp_jobid.txt` -gt 0 ]; then
if [ $neodc_check -gt 0 ] || [ $fillgaps -eq 1 ]; then
  echo "updated dates to make coregistration possible"
  if [ `grep ^updated tmp_jobid.txt | gawk {'print $2'}` == 'enddate' ]; then
   enddate=`grep ^updated tmp_jobid.txt | gawk {'print $4'}`
  else
   startdate=`grep ^updated tmp_jobid.txt | gawk {'print $4'}`
  fi
   #doing refill/db check
  if [ $fillgaps -eq 1 ]; then
   echo "Re-refilling the data gaps"
   framebatch_data_refill.sh $extradatarefill $frame $startdate $enddate
  else
   echo "Re-checking if the files are ingested to licsar database"
   framebatch_data_refill.sh -c $frame $startdate $enddate
  fi
  echo "re-caching the frame"
  setFrameInactive.py $frame
  setFrameActive.py $frame
  createFrameCache.py $frame $no_of_jobs $startdate $enddate > tmp_jobid.txt
 #fi
 if [ `grep -c ^updated tmp_jobid.txt` -gt 0 ]; then
  echo "ERROR - either data missing or another problem"
  echo "please recheck your input parameters, or contact Milan"
  echo "the tmp_jobid.txt content is:"
  cat tmp_jobid.txt
  exit
 fi
else
  echo "Warning, your data are out of temporal limit for standard SD estimation. Either you know what you are doing, or you better add either -c or enable autodownload"
fi
fi

 #ok, let's fix also the stuff already existing...
 if [ -d $LiCSAR_public/$track/$frame/interferograms ]; then
  mkdir GEOC 2>/dev/null
  #sometimes EIDP keeps mess
  rm -r $LiCSAR_public/$track/$frame/interferograms/geo 2>/dev/null
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
  #./$step.nowait.sh
  # 2025/06: running as Job Array:
  echo "Running step 1 as job array"
  PREVJID=$(sbatch --parsable $step.lotus2.sh)
  echo $PREVJID
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
  # ./$step.wait.sh
  echo "Running step 2 as job array"
  PREVJID=$(sbatch -d afterany:$PREVJID --parsable $step.lotus2.sh)
  echo $PREVJID
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
#echo "./framebatch_01_mk_image.nowait.sh; ./framebatch_02_coreg.wait.sh; ./framebatch_03_mk_ifg.wait.sh; ./framebatch_04_unwrap.wait.sh" > ./framebatch_x_second_iteration.nowait.sh
#echo "./framebatch_05_gap_filling.wait.sh" >> framebatch_x_second_iteration.nowait.sh
# 2023/06: but this might fail / jobs not found if they finish too early. so adding only nowait gapfill
echo "setFrameInactive.py "$frame"; ./framebatch_05_gap_filling.nowait.sh" > framebatch_x_postcoreg_iteration.nowait.sh
echo "bsub2slurm.sh -w '"$waiting_string"' -q "$bsubquery" -W 00:30 -n 1 -J postcoreg."$frame" -o LOGS/postcoreg.out -e LOGS/postcoreg.err ./framebatch_x_postcoreg_iteration.nowait.sh" > framebatch_x_postcoreg_iteration.wait.sh
echo "bsub2slurm.sh -w '"$waiting_string"' -q "$bsubquery" -W 00:45 -n 1 -J it2_coreg."$frame" -o LOGS/it2_coreg.out -e LOGS/it2_coreg.err framebatch_postproc_coreg.sh "$frame" 1" > framebatch_x_coreg_iteration.wait.sh
chmod 770 framebatch_x_postcoreg_iteration.wait.sh framebatch_x_postcoreg_iteration.nowait.sh framebatch_x_coreg_iteration.wait.sh


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
 ./framebatch_eqr.nowait.sh -w #this would store only RSLCs after 1st iteration
 # this would generate waiting script for the EQR, and start it after the second coreg iteration
 #echo "./framebatch_eqr.nowait.sh -w" >> framebatch_x_second_iteration.wait.sh
 #echo "./framebatch_eqr.nowait.sh -w" >> framebatch_x_second_iteration.nowait.sh
else
 echo "To run this step, use ./framebatch_eqr.nowait.sh"
fi
fi


if [ $NORUN -eq 0 ]; then
 #./framebatch_x_second_iteration.wait.sh
 echo 'setting post-proc coreg' # (new functionality - this will also auto inactivate the frame and run gapfilling afterwards. store script is run through gapfilling)'
 # ./framebatch_x_coreg_iteration.wait.sh
 sbatch -d afterany:$PREVJID --account=nceo_geohazards --time=00:45:00 --job-name=$frame.it2_coreg --output=LOGS/it2_coreg.out --error=LOGS/it2_coreg.err --wrap=" framebatch_postproc_coreg.sh "$frame" 1 " --mem=16384 --partition=standard --qos=standard
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
    #./$step.wait.sh
    echo "Running step 3 as job array"
    PREVJID=$(sbatch -d afterany:$PREVJID --parsable $step.lotus2.sh)
    echo $PREVJID
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
  #./$step.wait.sh
  echo "Running step 4 as job array"
  PREVJID=$(sbatch -d afterany:$PREVJID --parsable $step.lotus2.sh)
  echo $PREVJID
  echo "All jobs are sent for processing."
 else
  echo "To run this step, use ./"$step".x.sh, where x=nowait would start immediately while wait will start after finishing the previous stage"
 fi



###################################################### Gap Filling
echo "Preparing script for gap filling"
NBATCH=2  #max number of ifgs per job. it was 4 originally..
NBATCH=1 # 2025/02 using no. 1 as some jobs get stuck indefinitely!
gpextra=''
#added skipping of check for existing scratchdir/frame for gapfilling - just automatically delete it...
# gpextra='-o '
#if [ $NORUN -eq 0 ]; then
 #update 04/2021 - use of geocoded products
# gpextra=$gpextra"-g "
#fi
if [ $NORUN -eq 0 ] && [ $STORE -eq 1 ]; then
 gpextra=$gpextra"-S "
 #touch .processing_it1
fi
if [ $prioritise -eq 1 ]; then
 gpextra=$gpextra"-P "
fi
if [ $tienshan -eq 1 ]; then
 gpextra=$gpextra"-T "
fi
if [ $bovls -eq 1 ]; then
 gpextra=$gpextra"-b "
fi
if [ $rgoff -eq 1 ]; then
 gpextra=$gpextra"-R "
fi
if [ $deleteafterstore -eq 1 ]; then
  gpextra=$gpextra"-d "
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
 framebatch_gapfill.sh $sensorgapfill $gpextra $NBATCH
fi
EOF
chmod 770 framebatch_05_gap_filling.nowait.sh

#somehow got the wait gapfill script lost?
#redo here:
waiting_str=''
for jobid in `cat framebatch_04_unwrap.wait.sh | rev | gawk {'print $1'} | rev`; do
  stringg=$jobid"_framebatch_04_unwrap"
  waiting_str=$waiting_str" && ended("$stringg")"
done
waiting_string=`echo $waiting_str | cut -c 4-`
echo "bsub2slurm.sh -w '"$waiting_string"' -q $bsubquery -W 10:00 -n 1 -J framebatch_05_gap_filling_$frame -o LOGS/framebatch_05_gap_filling.out -e LOGS/framebatch_05_gap_filling.err ./framebatch_05_gap_filling.nowait.sh" > framebatch_05_gap_filling.wait.sh
chmod 777 framebatch_05_gap_filling.wait.sh

#if [ $NORUN -eq 0 ] && [ $STORE -lt 1 ]; then
#this below option means that even in AUTOSTORE, the gapfilling will be performed...
#in this case, however, it will be sent to bsub together with geotiff generation script
#so.. more connections now depend on 'luck having to wait for bsub2slurm.sh -x'
#this definitely needs improvement, yet better 'than nothing'.. i suppose
if [ $NORUN -eq 0 ]; then
 echo "gapfilling should be auto-started within framebatch.postproc (coreg) script"
 #./framebatch_05_gap_filling.nowait.sh -w
else
 echo "To run gapfilling afterwards, use ./framebatch_gapfill.nowait.sh"
fi




###################################################### Geocoding to tiffs
echo "Preparing script for geocoding results (2023/06: probably not needed anymore)"
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


# 2023/06 we will now run store script through gapfilling procedure. thus, no need to store here - anyway we may not need this step anymore at all
#if [ $STORE -eq 1 ]; then
# echo "Making the system automatically store the generated data (for auto update of frames)"
# echo "cd $BATCH_CACHE_DIR" >> framebatch_06_geotiffs.nowait.sh
# #echo "echo 'waiting 60 seconds for jobs to synchronize'" >> framebatch_06_geotiffs_nowait.sh
# #echo "sleep 60" >> framebatch_06_geotiffs_nowait.sh
# echo "bsub2slurm.sh -q $bsubquery -n 1 -W 06:00 -o LOGS/framebatch_$frame'_store.out' -e LOGS/framebatch_$frame'_store.err' -J $frame'_ST' store_to_curdir.sh $frame $deleteafterstore 0 $dogacos" >> framebatch_06_geotiffs.nowait.sh #$frame
# echo "bsub2slurm.sh -w '"$waiting_string"' -q $bsubquery -n 1 -W 06:00 -o LOGS/framebatch_$frame'_store.out' -e LOGS/framebatch_$frame'_store.err' -J $frame'_ST' store_to_curdir.sh $frame $deleteafterstore 0 $dogacos" >> framebatch_06_geotiffs.wait.sh #$frame
# #echo "bsub2slurm.sh -w $frame'_geo' -q $bsubquery -n 1 -W 06:00 -o LOGS/framebatch_$frame'_store.out' -e LOGS/framebatch_$frame'_store.err' -J $frame'_ST' store_to_curdir.sh $frame $deleteafterstore" >> framebatch_06_geotiffs_nowait.sh #$frame
# #cd -
#fi

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
#master=`ls geo/*.hgt | cut -d '/' -f2 | cut -d '.' -f1`
#if [ ! -f tab/$master'_tab' ]; then
# update 2022 - often wrong tab files. trying without it, see if it is not missing anywhere
#cp $LiCSAR_procdir/$track/$frame/tab/$master'_tab' tab/. 2>/dev/null
#fi


# only now, the updated way:
if [ $terminal -gt 0 ]; then
echo "---------------------"
echo "---------------------"
echo "TERMINAL PROCESSING"
echo "---------------------"
echo "---------------------"
echo " the following commands will now be performed: "
echo ""
m=`get_master $frame`
grep 'Not Built' framebatch_01_mk_image.list | gawk {'print $3'} | sed 's/\-//g' > list.ep
cat framebatch_03_mk_ifg.list | sed 's/\-//g' | gawk '{nn=$3"_"$4; print nn}' > list.ifg

echo "LiCSAR_01_mk_images.py -n -m $m -l list.ep -f $frame -d . -a 4 -r 20  > lmf_step1.out 2> lmf_step1.err"
echo "LiCSAR_02_coreg.py -f $frame -d . -m $m -l list.ep -i  > lmf_step2.out 2> lmf_step2.err"
echo "LiCSAR_03_mk_ifgs.py -d . -r 20 -a 4 -f $frame -c 0 -T ifgs.log -i list.ifg  > lmf_step3.out 2> lmf_step3.err"
#echo "cat list.ifg | parallel -j 2 create_geoctiffs_to_pub.sh -I .  >> lmf_step3.out 2>> lmf_step3.err"
#echo "cat list.ifg | parallel -j 2 create_geoctiffs_to_pub.sh -C . >> lmf_step3.out 2>> lmf_step3.err"
#echo "cat list.ifg | parallel -j 1 unwrap_geo.sh $frame  > lmf_step4.out 2> lmf_step4.err"
echo "./framebatch_05_gap_filling.nowait.sh"
echo ""
#echo "you may want to use them later for e.g. more ifgs - just update list.ifgs then "
#echo "(you can now CTRL-C them if you want to edit anything beforehand)"
echo "please be patient (will run for hours...)"
#sleep 5
#echo "ok, continuing: "

echo ".. running step 1: mk SLCs (15+ min per one epoch)"
LiCSAR_01_mk_images.py -n -m $m -l list.ep -f $frame -d . -a 4 -r 20 > lmf_step1.out 2> lmf_step1.err
echo ".. running step 2: mk RSLCs (30+ min per epoch)"
LiCSAR_02_coreg.py -f $frame -d . -m $m -l list.ep -i > lmf_step2.out 2> lmf_step2.err
echo ".. running step 3: mk ifgs (less than 10 min per ifg)"
LiCSAR_03_mk_ifgs.py -d . -r 20 -a 4 -f $frame -c 0 -T ifgs.log -i list.ifg > lmf_step3.out 2> lmf_step3.err
for x in `cat list.ifg`; do create_geoctiffs_to_pub.sh -I . $x; create_geoctiffs_to_pub.sh -C . $x; done
echo ".. running step 4: already sending to LOTUS2 (check bjobs)"
#cat list.ifg | parallel.perl -j 1 unwrap_geo.sh $frame
./framebatch_05_gap_filling.nowait.sh
echo "done"

fi

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
