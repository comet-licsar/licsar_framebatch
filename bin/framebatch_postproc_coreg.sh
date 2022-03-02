#!/bin/bash
source $LiCSARpath/lib/LiCSAR_bash_lib.sh

if [ -z $1 ]; then 
 echo "set parameter: frame";
 echo "this script will prepare coreg jobs to help against iterations - it might get messy, do not use it routinely";
 exit; fi
frame=$1

autocont=0
if [ ! -z $2 ]; then 
  #this is a hidden switch. it means that after the last coreg job, we will run second iteration of licsar_make_frame. testing..
  autocont=1
fi

burstsnum=`get_burstsno_frame $frame`

maxmem=16384
T="02:45"  # 1.5h should be ok, but Sabrina had problems ...
if [ $burstsnum -gt 45 ]; then maxmem=25000; T="03:30"; fi
if [ $burstsnum -ge 90 ]; then maxmem=32000; T="04:30"; fi
if [ $burstsnum -ge 120 ]; then maxmem=48000; T="06:00"; fi

if [ ! -d $BATCH_CACHE_DIR/$frame ]; then echo "this frame is not in your processing, cancelling"; exit; fi
cd $BATCH_CACHE_DIR/$frame
if [ `ls SLC | wc -l` -lt 2 ]; then
 echo "nothing to process"
 if [ $autocont -eq 1 ]; then
  echo "running second iteration"
  ./framebatch_x_second_iteration.nowait.sh
 fi
 exit
fi
rm coreg_its/tmp* coreg_its/coreg* 2>/dev/null
mkdir -p coreg_its
if [ `grep -c comet framebatch_02_coreg.nowait.sh` -gt 0 ]; then que='comet'; else que='short-serial'; fi
mstr=`get_master`
ls SLC | sed '/'$mstr'/d' > coreg_its/tmp_reprocess.slc
#clean first
for x in `ls RSLC | sed '/'$mstr'/d'`; do 
 if [ -f RSLC/$x/$x.lock ] || [ `ls RSLC/$x | wc -l` -eq 0 ]; then rm -rf RSLC/$x; fi;
done

# check / fix mosaic
if [ ! -f RSLC/$mstr/$mstr.rslc ]; then
 if [ ! -f RSLC/$mstr/$mstr.rslc.lock ]; then
  echo "need to regenerate master mosaic, one moment please"
  touch RSLC/$mstr/$mstr.rslc.lock
  if [ -f local_config.py ]; then
   rg=`grep ^rglks local_config.py | cut -d '=' -f2 | sed 's/ //g'`
   az=`grep ^azlks local_config.py | cut -d '=' -f2 | sed 's/ //g'`
  fi
  if [ -z $rg ]; then rg=20; fi
  if [ -z $az ]; then az=4; fi
  rm ./tab/$mstr'_tab' 2>/dev/null
  for i in 1 2 3; do
   if [ -f SLC/$mstr/$mstr.IW$i.slc ]; then
     echo "./RSLC/"$mstr/$mstr.IW$i.rslc "./RSLC/"$mstr/$mstr.IW$i.rslc.par "./RSLC/"$mstr/$mstr.IW$i.rslc.TOPS_par >> tab/$mstr'_tab'
   fi
  done
  #createSLCtab ./RSLC/$mstr/$mstr rslc $miniw $maxiw > tab/$mstr'_tab'
  SLC_mosaic_S1_TOPS ./tab/$mstr'_tab' RSLC/$mstr/$mstr.rslc RSLC/$mstr/$mstr.rslc.par $rg $az 1
  rm RSLC/$mstr/$mstr.rslc.lock
 else
  echo "warning, lock file found, maybe in process, in parallel? that should not happen, exiting"
  echo "if you are sure all should go well, just remove file "RSLC/$mstr/$mstr.rslc.lock
  exit
 fi
fi

ls RSLC > coreg_its/tmp.rslc
extraw=''
lastslc=`grep 20 coreg_its/tmp_reprocess.slc | tail -n1`
diffprev=0
if [ -f coreg_its/noncoreg ]; then
 if [ ! -f coreg_its/noncoreg.prev ]; then
  mv coreg_its/noncoreg coreg_its/noncoreg.prev
  diffprev=`cat coreg_its/noncoreg | wc -l`
 else
  diffprev=`diff coreg_its/noncoreg coreg_its/noncoreg.prev | wc -l`
  mv coreg_its/noncoreg coreg_its/noncoreg.prev
 fi
fi

 if [ $autocont -eq 1 ]; then
# if [ $x == $lastslc ]; then
  echo "setting second iteration"
  if [ ! $diffprev == 0 ]; then
   echo "framebatch_postproc_coreg.sh "$frame" 1" > postproc_coreg.sh; 
   #extraw='-Ep ./postproc_coreg.sh'
  else
   echo "./framebatch_x_second_iteration.nowait.sh" > postproc_coreg.sh
   #extraw='-Ep ./framebatch_x_second_iteration.nowait.sh'
  fi
  chmod 777 postproc_coreg.sh
# fi
 fi

for x in `cat coreg_its/tmp_reprocess.slc`; do
 doit=0
 for y in `cat coreg_its/tmp.rslc`; do 
  if [ `datediff $x $y` -lt 180 ]; then
   doit=1
   break
  fi
 done
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
  echo "time OMP_NUM_THREADS=1 LiCSAR_02_coreg.py -f "$frame" -d . -m "$mstr" -i -k -l "`pwd`"/coreg_its/coreg."$x >> coreg_its/coreg.$x.sh
  echo "rm RSLC/"$x"/$x.lock 2>/dev/null" >> coreg_its/coreg.$x.sh
  echo "rmdir RSLC/"$x" 2>/dev/null" >> coreg_its/coreg.$x.sh
  echo "mv RSLC/"$x" "`pwd`"/RSLC/." >> coreg_its/coreg.$x.sh
  echo "if [ -d "`pwd`"/RSLC/"$x" ]; then rm -rf SLC/"$x"; fi" >> coreg_its/coreg.$x.sh
  echo "cd "`pwd`"; rm -rf coreg_its/tmpdir_coreg."$x >> coreg_its/coreg.$x.sh
  chmod 777 coreg_its/coreg.$x.sh
  jobname=coreg.$x.$frame
  echo "bsub2slurm.sh -o coreg_its/coreg."$x".out -e coreg_its/coreg."$x".err -J "$jobname" -q "$que" -n 1 -W "$T" -M "$maxmem" coreg_its/coreg."$x".sh" > coreg_its/coreg.$x.job.sh
  chmod 777 coreg_its/coreg.$x.job.sh
  #running the job
  coreg_its/coreg.$x.job.sh
  if [ $autocont -eq 1 ]; then
   if [ -z $waitTextFirst ]; then
     waitText="ended("$jobname")"; 
     waitTextFirst=100
    else
     waitText=$waitText" && ended("$jobname")";
   fi
  fi
 else
  echo $x >> coreg_its/noncoreg
 fi
done

if [ $autocont -eq 1 ]; then
 # add next iteration in waiting mode
 echo "bsub2slurm.sh -w '"$waitText"' -o coreg_its/coreg.wait.out -e coreg_its/coreg.wait.err -J coreg."$frame".wait -q "$que" -n 1 -W 00:30 ./postproc_coreg.sh" > postproc.coreg.wait.sh
 chmod 777 postproc.coreg.wait.sh
 ./postproc.coreg.wait.sh
fi

if [ `cat coreg_its/noncoreg 2>/dev/null | wc -l` -gt 0 ]; then
 echo "WARNING, this iteration should fix the frame only partially."
 echo "Please rerun this script after the coreg jobs finish, for a second iteration"
 echo "In total, "`cat coreg_its/noncoreg | wc -l`" SLCs will be left after this iteration, as they are temporally too far"
fi
