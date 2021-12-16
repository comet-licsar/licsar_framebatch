#!/bin/bash
source $LiCSARpath/lib/LiCSAR_bash_lib.sh

if [ -z $1 ]; then 
 echo "set parameter: frame";
 echo "this script will prepare coreg jobs to help against iterations - it might get messy, do not use it routinely";
 exit; fi
frame=$1

burstsnum=`get_burstsno_frame $frame`

maxmem=16384
T="02:45"  # 1.5h should be ok, but Sabrina had problems ...
if [ $burstsnum -gt 45 ]; then maxmem=25000; T="03:30"; fi
if [ $burstsnum -ge 90 ]; then maxmem=32000; T="04:30"; fi
if [ $burstsnum -ge 120 ]; then maxmem=48000; T="06:00"; fi

if [ ! -d $BATCH_CACHE_DIR/$frame ]; then echo "this frame is not in your processing, cancelling"; exit; fi
cd $BATCH_CACHE_DIR/$frame
rm -rf coreg_its 2>/dev/null
mkdir -p coreg_its
if [ `grep -c comet framebatch_02_coreg.nowait.sh` -gt 0 ]; then que='comet'; else que='short-serial'; fi
mstr=`get_master`
ls SLC | sed '/'$mstr'/d' > coreg_its/tmp_reprocess.slc
#clean first
for x in `ls RSLC | sed '/'$mstr'/d'`; do 
 if [ -f RSLC/$x/$x.lock ] || [ `ls RSLC/$x | wc -l` -eq 0 ]; then rm -rf RSLC/$x; fi;
done

ls RSLC > coreg_its/tmp.rslc
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
  echo "time OMP_NUM_THREADS=1 LiCSAR_02_coreg.py -f "$frame" -d . -m "$mstr" -i -l coreg_its/coreg."$x > coreg_its/coreg.$x.sh
  echo "rm RSLC/"$x"/$x.lock 2>/dev/null" >> coreg_its/coreg.$x.sh
  echo "rmdir RSLC/"$x" 2>/dev/null" >> coreg_its/coreg.$x.sh
  chmod 777 coreg_its/coreg.$x.sh
  bsub2slurm.sh -o coreg_its/coreg.$x.out -e coreg_its/coreg.$x.err -J coreg.$x -q $que -n 1 -W $T -M $maxmem coreg_its/coreg.$x.sh
 else
  echo $x >> coreg_its/noncoreg
 fi
done

if [ `cat coreg_its/noncoreg 2>/dev/null | wc -l` -gt 0 ]; then
 echo "WARNING, this iteration should fix the frame only partially."
 echo "Please rerun this script after the coreg jobs finish, for a second iteration"
 echo "In total, "`cat coreg_its/noncoreg | wc -l`" SLCs will be left after this iteration, as they are temporally too far"
fi
