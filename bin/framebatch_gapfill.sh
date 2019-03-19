#!/bin/bash
if [ -z $1 ]; then echo "please provide NBATCH parameter"; exit; fi
#NBATCH=5
NBATCH=$1
echo "Executing gap filling routine"
frame=`pwd | rev | cut -d '/' -f1 | rev`
if [ `echo $frame | cut -c 11` != '_' ]; then echo "ERROR, you are not in FRAME folder. Exiting"; exit; fi

#decide for query based on user rights
if [ `bugroup | grep $USER | gawk {'print $1'} | grep -c cpom_comet` -eq 1 ]; then
  bsubquery='cpom-comet'
 else
  #bsubquery='par-single'
  bsubquery='short-serial'
fi
mkdir gapfill_job 2>/dev/null

#correct case where unw ifgs were not generated
rm gapfill_job/unw_correct.txt 2>/dev/null
for x in `ls IFG`; do if [ ! -f IFG/$x/$x.unw ]; then echo $x >> gapfill_job/unw_correct.txt; fi; done
if [ `cat gapfill_job/unw_correct.txt 2>/dev/null | wc -l` -gt 0 ]; then
 echo "In total, "`cat gapfill_job/unw_correct.txt | wc -l`" missing unw files are to be regenerated (within 1 job)"
 echo "LiCSAR_04_unwrap.py -d . -f $frame -T gapfill_job/unw_correct.log -l gapfill_job/unw_correct.txt" > gapfill_job/unw_correct.sh
 chmod 770 gapfill_job/unw_correct.sh
 bsub -q $bsubquery  -n 1 -W 23:59 gapfill_job/unw_correct.sh
fi

ls RSLC/20?????? -d | cut -d '/' -f2 > gapfill_job/tmp_rslcs
ls IFG/20*_20?????? -d | cut -d '/' -f2 > gapfill_job/tmp_ifg_existing
rm gapfill_job/tmp_ifg_all2 2>/dev/null
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
mv gapfill_job/tmp_ifg_all gapfill_job/tmp_unw_todo

NOIFG=`cat gapfill_job/tmp_ifg_todo | wc -l`
nojobs=`echo $NOIFG/$NBATCH | bc`
nojobs10=`echo $NOIFG*10/$NBATCH | bc | rev | cut -c 1 | rev`
if [ $nojobs10 -gt 0 ]; then let nojobs=$nojobs+1; fi

#distribute ifgs for processing jobs and run them
nifgmax=0;
for job in `seq 1 $nojobs`; do
 let nifg=$nifgmax+1
 let nifgmax=$nifgmax+$NBATCH
 sed -n ''$nifg','$nifgmax'p' gapfill_job/tmp_ifg_todo > gapfill_job/ifgjob_$job
 sed -n ''$nifg','$nifgmax'p' gapfill_job/tmp_unw_todo > gapfill_job/unwjob_$job
 echo "LiCSAR_03_mk_ifgs.py -d . -f $frame -c 0 -T gapfill_job/ifgjob_$job.log  -i gapfill_job/ifgjob_$job" > gapfill_job/ifgjob_$job.sh
 echo "LiCSAR_04_unwrap.py -d . -f $frame -T gapfill_job/unwjob_$job.log -l gapfill_job/unwjob_$job" > gapfill_job/unwjob_$job.sh
 chmod 770 gapfill_job/ifgjob_$job.sh
 chmod 770 gapfill_job/unwjob_$job.sh
 if [ $job -gt 2 ]; then 
  bsub -q $bsubquery -n 1 -W 23:59 -J $frame'_ifgjob_'$job gapfill_job/ifgjob_$job.sh
  bsub -q $bsubquery -n 1 -W 23:59 -J $frame'_unwjob_'$job -w "ended("$frame"_ifgjob_"$job")" gapfill_job/unwjob_$job.sh
 fi
done
