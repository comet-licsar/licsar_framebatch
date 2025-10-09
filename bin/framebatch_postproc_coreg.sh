#!/bin/bash
source $LiCSARpath/lib/LiCSAR_bash_lib.sh

if [ -z $1 ]; then 
 echo "set parameter: frame [1]";
 echo "this script will run jobs to coregister SLCs in the frame folder"  #prepare coreg jobs to help against iterations - it might get messy, do not use it routinely";
 echo "by running with the optional parameter 1, it would perform iterative processing to hopefully coregister all SLCs"
 echo "other parameters:"
 echo "-f ..... force override the 180 days gap limitation (that could cause wrong SD estimate)"
 echo "-F ..... full-force override (not recommended due to azimuth errors)"
 echo "-b ..... for force-override solution (best with the iterative processing) setting the first SLC backwards in time"
 exit; fi


force=0
autocont=0
extracoregparms=''
backfill=0
while getopts ":fFb" option; do
 case "${option}" in
  f) force=1;
     #autocont=1;
     extracoregparms='-E';
     #shift
     ;;
  F) extracoregparms='-E';
     #shift
     ;;
  b) backfill=1;
     ;;
 esac
done
shift $((OPTIND -1))

frame=$1
if [ `echo $frame | cut -d '_' -f2` == 'SM' ]; then
  echo "Stripmap - might not work ..better just rerun licsar_make_frame"
  force=1
  #exit
fi
if [ ! -z $2 ]; then 
  #this is a hidden switch. it means that after the last coreg job, we will run second iteration of licsar_make_frame. testing..
  autocont=1
fi

burstsnum=`get_burstsno_frame $frame 2>/dev/null`
if [ -z $burstsnum ]; then burstsnum=1; fi

maxmem=16384
T="02:45"  # 1.5h should be ok, but Sabrina had problems ...
# 06/2023: JASMIN got slow? 2:45 is not enough anymore!!!!
T="03:30"
if [ $burstsnum -gt 40 ]; then maxmem=32768; T="04:30"; fi
if [ $burstsnum -ge 90 ]; then maxmem=48000; T="05:30"; fi
if [ $burstsnum -ge 120 ]; then maxmem=65535; T="07:00"; fi

if [ ! -d $BATCH_CACHE_DIR/$frame ]; then echo "this frame is not in your processing, cancelling"; exit; fi
cd $BATCH_CACHE_DIR/$frame
if [ `ls SLC | wc -l` -lt 2 ]; then
 echo "nothing to process"
 if [ $autocont -eq 1 ]; then
  echo "running the post-coreg (second) iteration"
  ./framebatch_x_postcoreg_iteration.nowait.sh
 fi
 exit
fi
rm coreg_its/tmp* coreg_its/coreg* 2>/dev/null
if [ $force -eq 1 ]; then
 #cleaning full
 rm -rf coreg_its 2>/dev/null
fi

mkdir -p coreg_its
if [ `grep -c comet framebatch_02_coreg.nowait.sh` -gt 0 ]; then que='comet'; else que='short-serial'; fi
mstr=`get_master`
# fix empty slc file
m=$mstr
track=`track_from_frame $frame`
if [ -f $BATCH_CACHE_DIR/$frame/SLC/$m/$m.slc.par ]; then
 if [ `ls -al $BATCH_CACHE_DIR/$frame/SLC/$m/$m.slc.par | gawk {'print $5'}` -eq 0 ]; then
   echo "corrupted slc par file of reference epoch, fixing"
   cp $LiCSAR_procdir/$track/$frame/SLC/$m/$m.slc.par $BATCH_CACHE_DIR/$frame/SLC/$m/$m.slc.par
   cp $LiCSAR_procdir/$track/$frame/SLC/$m/$m.slc.par $BATCH_CACHE_DIR/$frame/RSLC/$m/$m.rslc.par
 fi
fi
ls SLC | sed '/'$mstr'/d' > coreg_its/tmp_reprocess.slc
#clean first
for x in `ls RSLC | sed '/'$mstr'/d'`; do 
 if [ -f RSLC/$x/$x.lock ] || [ `ls RSLC/$x | wc -l` -eq 0 ]; then rm -rf RSLC/$x; fi;
done

# get rg and azi looks
if [ -f local_config.py ]; then
   rg=`grep ^rglks local_config.py | cut -d '=' -f2 | sed 's/ //g'`
   az=`grep ^azlks local_config.py | cut -d '=' -f2 | sed 's/ //g'`
fi
if [ -z $rg ]; then rg=20; fi
if [ -z $az ]; then az=4; fi

if [ ! -f tab/$mstr'_tab' ]; then
 for i in 1 2 3; do
   if [ -f SLC/$mstr/$mstr.IW$i.slc ]; then
     echo "./RSLC/"$mstr/$mstr.IW$i.rslc "./RSLC/"$mstr/$mstr.IW$i.rslc.par "./RSLC/"$mstr/$mstr.IW$i.rslc.TOPS_par >> tab/$mstr'_tab'
   fi
  done
fi
# check / fix mosaic
if [ ! -f SLC/$mstr/$mstr.slc ]; then
 if [ ! -f SLC/$mstr/$mstr.slc.lock ]; then
  echo "need to regenerate master mosaic, one moment please"
  touch SLC/$mstr/$mstr.slc.lock
  rm ./tab/$mstr'_tab' 2>/dev/null
  for i in 1 2 3; do
   if [ -f SLC/$mstr/$mstr.IW$i.slc ]; then
     echo "./SLC/"$mstr/$mstr.IW$i.slc "./SLC/"$mstr/$mstr.IW$i.slc.par "./SLC/"$mstr/$mstr.IW$i.slc.TOPS_par >> tab/$mstr'_tab'
   fi
  done
  #createSLCtab ./RSLC/$mstr/$mstr rslc $miniw $maxiw > tab/$mstr'_tab'
  SLC_mosaic_S1_TOPS ./tab/$mstr'_tab' SLC/$mstr/$mstr.slc SLC/$mstr/$mstr.slc.par $rg $az 1
  rm SLC/$mstr/$mstr.slc.lock
 else
  echo "warning, lock file found, maybe in process, in parallel? that should not happen, exiting"
  echo "if you are sure all should go well, just remove file "RSLC/$mstr/$mstr.rslc.lock
  exit
 fi
fi
if [ ! -f RSLC/$mstr/$mstr.rslc ]; then
 ln -s `pwd`/SLC/$mstr/$mstr.slc `pwd`/RSLC/$mstr/$mstr.rslc
fi
if [ ! -f RSLC/$mstr/$mstr.rslc.par ]; then
 ln -s `pwd`/SLC/$mstr/$mstr.slc.par `pwd`/RSLC/$mstr/$mstr.rslc.par
fi

# checking and maybe regenerating master mli - otherwise it would get done in parallel! (not wanted)
mmli=SLC/$mstr/$mstr.slc.mli
if [ ! -f $mmli ]; then
 echo 'multilooking reference epoch SLC'
 multilookSLC $mstr $rg $az >/dev/null 2>/dev/null
fi
if [ ! -f RSLC/$mstr/$mstr.rslc.mli ]; then
 ln -s `pwd`/SLC/$mstr/$mstr.slc.mli `pwd`/RSLC/$mstr/$mstr.rslc.mli
fi
if [ ! -f RSLC/$mstr/$mstr.rslc.mli.par ]; then
 ln -s `pwd`/SLC/$mstr/$mstr.slc.mli.par `pwd`/RSLC/$mstr/$mstr.rslc.mli.par
fi

ls RSLC > coreg_its/tmp.rslc
extraw=''
lastslc=`grep 20 coreg_its/tmp_reprocess.slc | tail -n1`
diffprev=0
if [ -f coreg_its/noncoreg ]; then
 if [ ! -f coreg_its/noncoreg.prev ]; then
  mv coreg_its/noncoreg coreg_its/noncoreg.prev
  diffprev=`cat coreg_its/noncoreg.prev | wc -l`
 else
  diffprev=`diff coreg_its/noncoreg coreg_its/noncoreg.prev | wc -l`
  mv coreg_its/noncoreg coreg_its/noncoreg.prev
 fi
fi

largestiw=`du -c SLC/$mstr/$mstr.IW?.slc | grep slc | sort | tail -n 1 | rev | cut -d '.' -f 2 | rev`
# msize=`du -c SLC/$mstr/$mstr.IW?.slc | grep slc | gawk {'print $1'} | sort | tail -n 1`
msize=`ls -al SLC/$mstr/$mstr.$largestiw.slc | gawk {'print $5'}`

maxj=0
if [ $backfill -eq 0 ]; then
  cat coreg_its/tmp_reprocess.slc | sort > coreg_its/tmp_reprocess.slc.sorted
else
  cat coreg_its/tmp_reprocess.slc | sort -r > coreg_its/tmp_reprocess.slc.sorted
fi
for x in `cat coreg_its/tmp_reprocess.slc.sorted`; do
 doit=0
 if [ $force == 0 ]; then
  cp coreg_its/tmp.rslc coreg_its/tmp.rslc.tmp
  echo $x >> coreg_its/tmp.rslc.tmp
  for y in `sort coreg_its/tmp.rslc.tmp | grep -A 1 -B 1 $x | sed '/'$x'/d'`; do if [ `datediff $x $y | sed 's/-//'` -lt 180 ]; then doit=1; fi; done
  # this below was the bottleneck!!!
  #for y in `cat coreg_its/tmp.rslc`; do 
  # if [ `datediff $x $y` -lt 180 ]; then
  #  doit=1
  #  break
  # fi
  #done
 else
  if [ ! -f SLC/$x/forcecoreg_tried ]; then
   #ssize=`du -c SLC/$x/*IW?.slc | tail -n1 | gawk {'print $1'}`  # check if the slc has same size as master slc
   #if [ $ssize -eq $msize ]; then doit=1; touch SLC/$x/forcecoreg_tried; fi
   # avoiding the check as we may want to coregister also smaller (or bigger - happened as well) slcs:
   doit=1; touch SLC/$x/forcecoreg_tried
  fi
 fi
 if [ $doit -eq 1 ]; then
  echo $x > coreg_its/coreg.$x
  echo "mkdir coreg_its/tmpdir_coreg."$x"; cd coreg_its/tmpdir_coreg."$x > coreg_its/coreg.$x.sh
  echo "mkdir -p tab RSLC/"$mstr >> coreg_its/coreg.$x.sh
  echo "ln -s "`pwd`"/SLC" >> coreg_its/coreg.$x.sh
  echo "ln -s "`pwd`"/log" >> coreg_its/coreg.$x.sh
  ddir=`pwd`
  for aa in `ls $ddir/RSLC/$mstr/*.rslc $ddir/RSLC/$mstr/*.rslc.mli`; do
   basex=`basename $aa`
   echo "ln -s "$aa" RSLC/"$mstr"/"$basex >> coreg_its/coreg.$x.sh
  done
  echo "cd RSLC" >> coreg_its/coreg.$x.sh
  for aa in `ls $ddir/RSLC/* -d`; do
   basex=`basename $aa`
   if [ ! $basex == $mstr ]; then
     echo "ln -s "$aa >> coreg_its/coreg.$x.sh
   fi
  done
  echo "cd .." >> coreg_its/coreg.$x.sh
  echo "cp "`pwd`"/RSLC/"$mstr"/*par RSLC/"$mstr"/." >> coreg_its/coreg.$x.sh
  echo "ln -s RSLC/"$mstr"/"$mstr".rslc" >> coreg_its/coreg.$x.sh
  echo "ln -s RSLC/"$mstr"/"$mstr".rslc.par" >> coreg_its/coreg.$x.sh
  echo "ln -s RSLC/"$mstr"/"$mstr".rslc.mli "$mstr".rmli" >> coreg_its/coreg.$x.sh
  echo "ln -s RSLC/"$mstr"/"$mstr".rslc.mli.par "$mstr".rmli.par" >> coreg_its/coreg.$x.sh
  echo "ln -s "`pwd`"/geo" >> coreg_its/coreg.$x.sh
  echo "time OMP_NUM_THREADS=1 LiCSAR_02_coreg.py -f "$frame" -d . -m "$mstr" -i -k -l "`pwd`"/coreg_its/coreg."$x $extracoregparms >> coreg_its/coreg.$x.sh
  echo "rm RSLC/"$x"/$x.lock 2>/dev/null" >> coreg_its/coreg.$x.sh
  echo "rmdir RSLC/"$x" 2>/dev/null" >> coreg_its/coreg.$x.sh
  echo "mv RSLC/"$x" "`pwd`"/RSLC/." >> coreg_its/coreg.$x.sh
  echo "if [ -d "`pwd`"/RSLC/"$x" ]; then rm -rf SLC/"$x"; fi" >> coreg_its/coreg.$x.sh
  echo "cd "`pwd`"; rm -rf coreg_its/tmpdir_coreg."$x >> coreg_its/coreg.$x.sh
  chmod 777 coreg_its/coreg.$x.sh
  jobname=coreg.$x.$frame
  echo "bsub2slurm.sh -o coreg_its/coreg."$x".out -e coreg_its/coreg."$x".err -J "$jobname" -q "$que" -n 1 -W "$T" -M "$maxmem" coreg_its/coreg."$x".sh" > coreg_its/coreg.$x.job.sh
  chmod 777 coreg_its/coreg.$x.job.sh
  #running the job ... or not
  echo coreg_its/coreg.$x.job.sh
  let maxj=$maxj+1
  cp coreg_its/coreg.$x.sh coreg_its/coreg.job.$maxj.sh
  if [ $autocont -eq 1 ]; then
   if [ -z $waitTextFirst ]; then
     waitText="ended("$jobname")"; 
     waitTextFirst=100
    else
     waitText=$waitText" && ended("$jobname")";
   fi
  fi
  if [ $force == 1 ]; then
   echo "using only one SLC to force-coregister (avoid 180 days check): "$x
   cat coreg_its/tmp_reprocess.slc | sed '/'$x'/d' > coreg_its/noncoreg
   break  #we want to link only one such SLC for processing
  fi
 else  # if not 'doit'
  echo $x >> coreg_its/noncoreg
 fi
done

if [ $maxj -gt 0 ]; then
# prep the job array
cat << EOF > framebatch_postproc_coreg.lotus2.sh
#!/bin/bash
#SBATCH --job-name=$frame.coreg.$maxj
#SBATCH --time=$T:00
#SBATCH --account=nceo_geohazards
#SBATCH --partition=standard
#SBATCH --qos=standard
#SBATCH -o coreg_its/%A.%a.out
#SBATCH -e coreg_its/%A.%a.err
#SBATCH --array=1-$maxj
#SBATCH --mem-per-cpu=${maxmem}M

coreg_its/coreg.job.\${SLURM_ARRAY_TASK_ID}.sh

EOF

chmod 770 framebatch_postproc_coreg.lotus2.sh
# and run it
echo "Running postproc coreg scripts as job array"
PREVJID=$(sbatch --parsable framebatch_postproc_coreg.lotus2.sh)
echo $PREVJID
fi


# double-check here for the previous non coregs...
if [ $diffprev == 0 ]; then
if [ -f coreg_its/noncoreg ]; then
 if [ ! -f coreg_its/noncoreg.prev ]; then
  diffprev=`cat coreg_its/noncoreg | wc -l`
 else
  diffprev=`diff coreg_its/noncoreg coreg_its/noncoreg.prev | wc -l`
 fi
fi
fi

if [ $autocont -eq 1 ]; then
# if [ $x == $lastslc ]; then
  echo "setting the post-coreg iteration"
  if [ ! $diffprev == 0 ]; then   # so if there are still some SLCs left to coreg, run the iteration...
   echo "framebatch_postproc_coreg.sh "$frame" 1" > postproc_coreg.sh; 
   #extraw='-Ep ./postproc_coreg.sh'
  else
   echo "some SLCs could not be coregistered - finding ones with missing bursts and moving to SLC.missingbursts folder"
   mkdir -p SLC.missingbursts
   msizetol=`echo $msize-1024*1024*100 | bc` # tolerate 100 MB difference
   for x in `ls SLC`; do
      # check if the slc has similar size as master slc
      ssize=`ls -al SLC/$x/$x.$largestiw.slc 2>/dev/null | gawk {'print $5'}`
      if [ -z $ssize ]; then ssize=0; fi
      if [ $ssize -lt $msizetol ]; then
        echo $x" has missing bursts"
        mv SLC/$x SLC.missingbursts/$x
      fi
   done
   rmdir SLC.missingbursts 2>/dev/null
   echo "./framebatch_x_postcoreg_iteration.nowait.sh" > postproc_coreg.sh
   #extraw='-Ep ./framebatch_x_second_iteration.nowait.sh'
  fi
  chmod 777 postproc_coreg.sh
# fi
 fi
if [ $autocont -eq 1 ]; then
 # add next iteration in waiting mode
 echo "bsub2slurm.sh -w '"$waitText"' -o coreg_its/coreg.wait.out -e coreg_its/coreg.wait.err -J coreg."$frame".wait -q "$que" -n 1 -W 00:30 ./postproc_coreg.sh" > postproc.coreg.wait.sh
 echo "sbatch -d afterany:"$PREVJID" --account=nceo_geohazards --partition=standard --qos=standard --time=00:45:00 --job-name="$frame".waitcoreg --output=coreg_its/coreg.wait2.out --error=coreg_its/coreg.wait2.err --wrap='./postproc_coreg.sh'" > postproc.coreg.wait2.sh
 chmod 777 postproc.coreg.wait.sh postproc.coreg.wait2.sh
 ./postproc.coreg.wait2.sh
else

 if [ `cat coreg_its/noncoreg 2>/dev/null | wc -l` -gt 0 ]; then
  echo "WARNING, this iteration should fix the frame only partially."
  echo "Please rerun this script after the coreg jobs finish, for a second iteration"
  echo "In total, "`cat coreg_its/noncoreg | wc -l`" SLCs will be left after this iteration, as they are temporally too far"
 fi
fi
