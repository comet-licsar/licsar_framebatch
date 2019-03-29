#!/bin/bash
if [ -z $1 ]; then echo "please provide NBATCH parameter (how many images you want per job)"; exit; fi
#NBATCH=5
NBATCH=$1
SCRATCHDIR=/work/scratch/licsar
echo "Executing gap filling routine"
frame=`pwd | rev | cut -d '/' -f1 | rev`
if [ `echo $frame | cut -c 11` != '_' ]; then echo "ERROR, you are not in FRAME folder. Exiting"; exit; fi
if [ -z $BATCH_CACHE_DIR ]; then echo "BATCH_CACHE_DIR not set. Cancelling"; exit; fi

#decide for query based on user rights
if [ `bugroup | grep $USER | gawk {'print $1'} | grep -c cpom_comet` -eq 1 ]; then
  bsubquery='cpom-comet'
 else
  #bsubquery='par-single'
  bsubquery='short-serial'
fi
rm -r gapfill_job 2>/dev/null
mkdir gapfill_job

#correct case where unw ifgs were not generated
#for x in `ls IFG`; do if [ ! -f IFG/$x/$x.unw ]; then echo $x >> gapfill_job/unw_correct.txt; fi; done
#if [ `cat gapfill_job/unw_correct.txt 2>/dev/null | wc -l` -gt 0 ]; then
# echo "In total, "`cat gapfill_job/unw_correct.txt | wc -l`" missing unw files are to be regenerated (within 1 job)"
# echo "LiCSAR_04_unwrap.py -d . -f $frame -T gapfill_job/unw_correct.log -l gapfill_job/unw_correct.txt" > gapfill_job/unw_correct.sh
# chmod 770 gapfill_job/unw_correct.sh
# bsub -q $bsubquery  -n 1 -W 23:59 gapfill_job/unw_correct.sh
#fi
echo "getting list of ifg to fill"
ls RSLC/20??????/*rslc.mli | cut -d '/' -f2 > gapfill_job/tmp_rslcs
ls IFG/20*_20??????/*.cc | cut -d '/' -f2 > gapfill_job/tmp_ifg_existing
#rm gapfill_job/tmp_ifg_all2 2>/dev/null
for FIRST in `cat gapfill_job/tmp_rslcs`; do  
 SECOND=`grep -A1 $FIRST gapfill_job/tmp_rslcs | tail -n1`;
 THIRD=`grep -A2 $FIRST gapfill_job/tmp_rslcs | tail -n1`;
 FOURTH=`grep -A3 $FIRST gapfill_job/tmp_rslcs | tail -n1`;
 echo $FIRST'_'$SECOND >> gapfill_job/tmp_ifg_all2;
 echo $FIRST'_'$THIRD >> gapfill_job/tmp_ifg_all2; 
 echo $FIRST'_'$FOURTH >> gapfill_job/tmp_ifg_all2; 
done
cat gapfill_job/tmp_ifg_all2 | head -n-5 | sort -u > gapfill_job/tmp_ifg_all
for ifg in `cat gapfill_job/tmp_ifg_existing`; do  sed -i '/'$ifg'/d' gapfill_job/tmp_ifg_all; done
sed 's/_/ /' gapfill_job/tmp_ifg_all > gapfill_job/tmp_ifg_todo
rm gapfill_job/tmp_rslcs2copy 2>/dev/null
for x in `cat gapfill_job/tmp_ifg_todo`; do echo $x >> gapfill_job/tmp_rslcs2copy; done
sort -u gapfill_job/tmp_rslcs2copy -o gapfill_job/tmp_rslcs2copy 2>/dev/null
mv gapfill_job/tmp_ifg_all gapfill_job/tmp_unw_todo
for x in `ls IFG/*/*.cc | cut -d '/' -f2`; do if [ ! -f IFG/$x/$x.unw ]; then echo $x >> gapfill_job/tmp_unw_todo; fi; done

NOIFG=`cat gapfill_job/tmp_unw_todo | wc -l`
nojobs=`echo $NOIFG/$NBATCH | bc`
nojobs10=`echo $NOIFG*10/$NBATCH | bc | rev | cut -c 1 | rev`
if [ $nojobs10 -gt 0 ]; then let nojobs=$nojobs+1; fi

#distribute ifgs for processing jobs and run them
nifgmax=0; waitText="";
for job in `seq 1 $nojobs`; do
 let nifg=$nifgmax+1
 let nifgmax=$nifgmax+$NBATCH
 sed -n ''$nifg','$nifgmax'p' gapfill_job/tmp_unw_todo > gapfill_job/unwjob_$job
 sed -n ''$nifg','$nifgmax'p' gapfill_job/tmp_ifg_todo > gapfill_job/ifgjob_$job
 if [ `wc -l gapfill_job/ifgjob_$job | gawk {'print $1'}` -eq 0 ]; then rm gapfill_job/ifgjob_$job; else
  echo "LiCSAR_03_mk_ifgs.py -d . -f $frame -c 0 -T gapfill_job/ifgjob_$job.log  -i gapfill_job/ifgjob_$job" > gapfill_job/ifgjob_$job.sh
  chmod 770 gapfill_job/ifgjob_$job.sh
 fi
 echo "LiCSAR_04_unwrap.py -d . -f $frame -T gapfill_job/unwjob_$job.log -l gapfill_job/unwjob_$job" > gapfill_job/unwjob_$job.sh
 waitText=$waitText" && ended("$frame"_unw_"$job")"
 chmod 770 gapfill_job/unwjob_$job.sh
done
 #move it for processing in SCRATCHDIR
 echo "There are "`wc -l gapfill_job/tmp_ifg_todo | gawk {'print $1'}`" interferograms to process and "`wc -l gapfill_job/tmp_unw_todo | gawk {'print $1'}`" to unwrap."
 echo "Preparation phase: copying data to SCRATCH disk (may take long)"
 #if [ -d $SCRATCHDIR/$frame ]; then echo "..cleaning scratchdir"; rm -rf $SCRATCHDIR/$frame; fi
 mkdir -p $SCRATCHDIR/$frame/RSLC
 mkdir $SCRATCHDIR/$frame/IFG
 mkdir $SCRATCHDIR/$frame/SLC $SCRATCHDIR/$frame/log $SCRATCHDIR/$frame/LOGS
 if [ -f gapfill_job/tmp_rslcs2copy ]; then
  echo "..copying "`wc -l gapfill_job/tmp_rslcs2copy | gawk {'print $1'}`" needed rslcs"
  for rslc in `cat gapfill_job/tmp_rslcs2copy`; do if [ ! -d $SCRATCHDIR/$frame/RSLC/$rslc ]; then cp -r RSLC/$rslc $SCRATCHDIR/$frame/RSLC/.; fi; done
 fi
 master=`basename geo/20??????.hgt .hgt`
 echo "..copying master slc"
 cp -r SLC/$master $SCRATCHDIR/$frame/SLC/.
 echo "..copying geo and other files"
 cp -r tab geo log gapfill_job $SCRATCHDIR/$frame/.
 #sed 's/ /_/' gapfill_job/tmp_ifg_todo > gapfill_job/tmp_ifg_copy
 cat gapfill_job/tmp_unw_todo >> gapfill_job/tmp_ifg_copy
 echo "..copying ifgs to unwrap only"
 for ifg in `cat gapfill_job/tmp_unw_todo`; do 
  if [ -d IFG/$ifg ]; then cp -r IFG/$ifg $SCRATCHDIR/$frame/IFG/.; fi;
 done
##########################################################
 echo "running jobs"
 cd $SCRATCHDIR/$frame
 #weird error.. quick fix here:
 for x in `ls tab/20??????_tab`; do cp `echo $x | sed 's/_tab/R_tab/'` $x; done
for job in `seq 1 $nojobs`; do
 wait=''
 if [ -f gapfill_job/ifgjob_$job.sh ]; then
  bsub -q $bsubquery -n 1 -W 03:00 -J $frame'_ifg_'$job gapfill_job/ifgjob_$job.sh
  wait="-w \"ended('"$frame"_ifg_"$job"')\""
 fi
 #weird error in 'job not found'.. workaround:
 echo bsub -q $bsubquery -n 1 -W 12:00 -J $frame'_unw_'$job -e `pwd`/$frame'_unw_'$job.err -o `pwd`/$frame'_unw_'$job.out $wait gapfill_job/unwjob_$job.sh > tmptmp
 chmod 770 tmptmp; ./tmptmp
done
# copying and cleaning job
 waitcmd=''
 if [ `echo $waitText | wc -w` -gt 0 ]; then
  waitText=`echo $waitText | cut -c 4-`
  waitcmd='-w "'$waitText'"'
 fi
 echo "chmod -R 770 $SCRATCHDIR/$frame" > gapfill_job/copyjob.sh
 echo "rsync -r $SCRATCHDIR/$frame/IFG $BATCH_CACHE_DIR/$frame" >> gapfill_job/copyjob.sh
 echo "rsync -r $SCRATCHDIR/$frame/gapfill_job $BATCH_CACHE_DIR/$frame" >> gapfill_job/copyjob.sh
 echo "rm -r $SCRATCHDIR/$frame" >> gapfill_job/copyjob.sh
 chmod 770 gapfill_job/copyjob.sh
 #workaround for 'Empty job. Job not submitted'
 echo bsub -q short-serial -n 1 $waitcmd -J $frame'_gapfill_out' gapfill_job/copyjob.sh > tmptmp
 chmod 770 tmptmp; ./tmptmp
 rm tmptmp
 cd -
