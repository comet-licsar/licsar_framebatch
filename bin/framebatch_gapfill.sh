#!/bin/bash
MAXBTEMP=60
rlks=20
azlks=4
#waiting=0

if [ -z $1 ]; then echo "Usage: framebatch_gapfill.sh NBATCH [MAXBTEMP] [range_looks] [azimuth_looks]";
                   echo "NBATCH.... number of interferograms to generate per job (licsar defaults to 5)";
                   echo "MAXBTEMP.. max temporal baseline in days. Default is "$MAXBTEMP" [days]";
                   echo "range_looks and azimuth_looks - defaults are range_looks="$rlks" and azimuth_looks="$azlks;
#                  echo "parameter -w ... will wait for the unwrapping jobs to end (useful only if unwrap is running, see licsar_make_frame)";
                   exit; fi

#while getopts ":w" option; do
# case "${option}" in
#  w ) waiting=1; echo "parameter -w set: will wait for standard unwrapping before ifg gap filling"
#      shift
#      ;;
#esac
#done

if [ -z $2 ]; then echo "using default value of MAXBtemp="$MAXBTEMP; else MAXBTEMP=$2; fi
if [ -z $3 ]; then echo "using default value of range_looks="$rlks; else rlks=$3; fi
if [ -z $4 ]; then echo "using default value of azimuth_looks="$azlks; else azlks=$4; fi
#NBATCH=5
NBATCH=$1
master=`basename geo/20??????.hgt .hgt`
SCRATCHDIR=/work/scratch/licsar
WORKFRAMEDIR=`pwd`
frame=`pwd | rev | cut -d '/' -f1 | rev`
echo "Executing gap filling routine (results will be saved in this folder: "$WORKFRAMEDIR" )."
if [ `echo $frame | cut -c 11` != '_' ]; then echo "ERROR, you are not in FRAME folder. Exiting"; exit; fi
#if [ -z $BATCH_CACHE_DIR ]; then echo "BATCH_CACHE_DIR not set. Cancelling"; exit; fi

#decide for query based on user rights
if [ `bugroup | grep $USER | gawk {'print $1'} | grep -c cpom_comet` -eq 1 ]; then
  bsubquery='cpom-comet'
 else
  #bsubquery='par-single'
  bsubquery='short-serial'
fi
rm -r gapfill_job 2>/dev/null
mkdir gapfill_job

#waiting_str=''
#if [ $waiting -gt 0 ]; then
# for jobid in `cat framebatch_04_unwrap.sh | rev | gawk {'print $1'} | rev`; do
#  stringg="framebatch_04_unwrap_"$jobid
#  waiting_str=$waiting_str" && ended("$stringg")"
# done
# waiting_string=`echo $waiting_str | cut -c 5-`
#fi

#correct case where unw ifgs were not generated
#for x in `ls IFG`; do if [ ! -f IFG/$x/$x.unw ]; then echo $x >> gapfill_job/unw_correct.txt; fi; done
#if [ `cat gapfill_job/unw_correct.txt 2>/dev/null | wc -l` -gt 0 ]; then
# echo "In total, "`cat gapfill_job/unw_correct.txt | wc -l`" missing unw files are to be regenerated (within 1 job)"
# echo "LiCSAR_04_unwrap.py -d . -f $frame -T gapfill_job/unw_correct.log -l gapfill_job/unw_correct.txt" > gapfill_job/unw_correct.sh
# chmod 770 gapfill_job/unw_correct.sh
# bsub -q $bsubquery  -n 1 -W 23:59 gapfill_job/unw_correct.sh
#fi
echo "getting list of ifg to fill"
if [ ! -d IFG ]; then mkdir IFG; fi
ls RSLC/20??????/*rslc.mli | cut -d '/' -f2 > gapfill_job/tmp_rslcs
ls IFG/20*_20??????/*.cc 2>/dev/null | cut -d '/' -f2 > gapfill_job/tmp_ifg_existing
#rm gapfill_job/tmp_ifg_all2 2>/dev/null
for FIRST in `cat gapfill_job/tmp_rslcs`; do  
 SECOND=`grep -A1 $FIRST gapfill_job/tmp_rslcs | tail -n1`;
 THIRD=`grep -A2 $FIRST gapfill_job/tmp_rslcs | tail -n1`;
 FOURTH=`grep -A3 $FIRST gapfill_job/tmp_rslcs | tail -n1`;
 for LAST in $SECOND $THIRD $FOURTH; do
  if [ `datediff $FIRST $LAST` -lt $MAXBTEMP ] && [ ! $FIRST == $LAST ]; then
   echo $FIRST'_'$SECOND >> gapfill_job/tmp_ifg_all2; 
  fi
 done 
done
#cat gapfill_job/tmp_ifg_all2 | head -n-5 | sort -u > gapfill_job/tmp_ifg_all
cat gapfill_job/tmp_ifg_all2 | sort -u > gapfill_job/tmp_ifg_all
for ifg in `cat gapfill_job/tmp_ifg_existing`; do  sed -i '/'$ifg'/d' gapfill_job/tmp_ifg_all; done
sed 's/_/ /' gapfill_job/tmp_ifg_all > gapfill_job/tmp_ifg_todo
#rm gapfill_job/tmp_rslcs2copy 2>/dev/null
for x in `cat gapfill_job/tmp_ifg_todo`; do echo $x >> gapfill_job/tmp_rslcs2copy; done
sort -u gapfill_job/tmp_rslcs2copy -o gapfill_job/tmp_rslcs2copy 2>/dev/null
mv gapfill_job/tmp_ifg_all gapfill_job/tmp_unw_todo
for x in `ls IFG/*/*.cc 2>/dev/null | cut -d '/' -f2`; do if [ ! -f IFG/$x/$x.unw ]; then echo $x >> gapfill_job/tmp_unw_todo; fi; done

#check rslc mosaics
#rm gapfill_job/tmp_rslcs2mosaic 2>/dev/null
for x in `cat gapfill_job/tmp_rslcs2copy`; do
 if [ ! -f RSLC/$x/$x.rslc ] || [ `ls -l RSLC/$x/$x.rslc | gawk {'print $5'}` -eq 0 ]; then
  echo $x >> gapfill_job/tmp_rslcs2mosaic
 fi
done

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
  #rm gapfill_job/ifgjob_$job.sh 2>/dev/null #just to clean..
  #deal with mosaics here..
  if [ ! -f tab/$master'R_tab' ]; then cp tab/$master'_tab' tab/$master'R_tab'; fi
  for image in `cat gapfill_job/ifgjob_$job`; do 
   if [ `grep -c $image gapfill_job/tmp_rslcs2mosaic` -gt 0 ]; then
    sed -i '/'$image'/d' gapfill_job/tmp_rslcs2mosaic
    echo "SLC_mosaic_S1_TOPS tab/$image'R_tab' RSLC/$image/$image.rslc RSLC/$image/$image.rslc.par $rlks $azlks 0 tab/$master'R_tab'" >> gapfill_job/ifgjob_$job.sh
   fi
  done
  echo "LiCSAR_03_mk_ifgs.py -d . -f $frame -c 0 -T gapfill_job/ifgjob_$job.log  -i gapfill_job/ifgjob_$job" >> gapfill_job/ifgjob_$job.sh
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
 mkdir $SCRATCHDIR/$frame/IFG 2>/dev/null
 mkdir $SCRATCHDIR/$frame/SLC $SCRATCHDIR/$frame/LOGS  2>/dev/null
 if [ -f gapfill_job/tmp_rslcs2copy ]; then
  echo "..copying "`wc -l gapfill_job/tmp_rslcs2copy | gawk {'print $1'}`" needed rslcs"
  for rslc in `cat gapfill_job/tmp_rslcs2copy`; do if [ ! -d $SCRATCHDIR/$frame/RSLC/$rslc ]; then cp -r RSLC/$rslc $SCRATCHDIR/$frame/RSLC/.; fi; done
 fi
 echo "..copying master slc"
 cp -r SLC/$master $SCRATCHDIR/$frame/SLC/.
 rm -r $SCRATCHDIR/$frame/RSLC/$master 2>/dev/null
 mkdir $SCRATCHDIR/$frame/RSLC/$master
 for x in `ls $SCRATCHDIR/$frame/SLC/$master/*`; do ln -s $x $SCRATCHDIR/$frame/RSLC/$master/`basename $x | sed 's/slc/rslc/'`; done
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
 #weird error - mk_ifg is reading SLC tabs instead of rslc?? (need debug).. quick fix here:
 #for x in `ls tab/20??????_tab`; do cp `echo $x | sed 's/_tab/R_tab/'` $x; done
for job in `seq 1 $nojobs`; do
 wait=''
 if [ -f gapfill_job/ifgjob_$job.sh ]; then
  bsub -q $bsubquery -n 1 -W 03:00 -J $frame'_ifg_'$job -e gapfill_job/ifgjob_$job.err -o gapfill_job/ifgjob_$job.out gapfill_job/ifgjob_$job.sh
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
 echo "rsync -r $SCRATCHDIR/$frame/IFG $WORKFRAMEDIR" >> gapfill_job/copyjob.sh
 echo "rsync -r $SCRATCHDIR/$frame/gapfill_job $WORKFRAMEDIR" >> gapfill_job/copyjob.sh
 echo "rm -r $SCRATCHDIR/$frame" >> gapfill_job/copyjob.sh
 chmod 770 gapfill_job/copyjob.sh
 #workaround for 'Empty job. Job not submitted'
 echo bsub -q short-serial -n 1 $waitcmd -W 02:00 -J $frame'_gapfill_out' gapfill_job/copyjob.sh > tmptmp
 chmod 770 tmptmp; ./tmptmp
 rm tmptmp
 cd -
