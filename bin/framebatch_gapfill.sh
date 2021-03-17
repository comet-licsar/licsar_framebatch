#!/bin/bash
MAXBTEMP=181
orig_rlks=20
orig_azlks=4
bsubncores=16
#according to CEDA Support, we should keep 1 process per processor.
#but -n1 was working usually fine... so keeping -n1
bsubncores=1
geocode=0
waiting=0
store=0
ADD36M=1
CHECKSCRATCH=1
prioritise=1
checkrslc=1
#quality checker here is the basic one. but still it does problems! e.g. Iceland earthquake - took long to process due to tech complications
#and just after this was done, this auto-checker detected it as problematic and deleted those wonderful ifgs!!
#it is all the no-ESD test that is performed over whole image, and not only at the edges of bursts. so rather keep =0
qualcheck=0

if [ -z $1 ]; then echo "Usage: framebatch_gapfill.sh NBATCH [MAXBTEMP] [range_looks] [azimuth_looks]";
                   echo "NBATCH.... number of interferograms to generate per job (licsar defaults to 5)";
                   echo "MAXBTEMP.. max temporal baseline in days. Default is "$MAXBTEMP" [days]";
                   echo "range_looks and azimuth_looks - defaults are range_looks="$orig_rlks" and azimuth_looks="$orig_azlks;
#                  echo "parameter -w ... will wait for the unwrapping jobs to end (useful only if unwrap is running, see licsar_make_frame)";
                   echo "parameter -g ... will run further framebatch step, i.e. geocoding"
                   echo "parameter -S ... will run store and delete after geocoding.."
                   echo "parameter -P ... prioritise (run through cpom-comet)"
                   exit; fi

while getopts ":wgSaPo" option; do
 case "${option}" in
  w ) waiting=1; echo "parameter -w set: will wait for standard unwrapping before ifg gap filling";
#      shift
      ;;
  g ) geocode=1; echo "parameter -g set: will do post-processing step - geocoding after the finish";
#      shift
      ;;
  S ) store=1; echo "parameter -S set: will store after geocoding";
#      shift
      ;;
  P ) prioritise=1; echo "parameter -P set: prioritising through cpom-comet";
#      shift
      ;;
  o ) CHECKSCRATCH=0; echo "skipping check for existing frame on LiCSAR_temp";
      ;;
  esac
done
shift $((OPTIND-1))

if [ $checkrslc -eq 1 ]; then
 if [ -f .processing_it1 ]; then
  echo "performing check of SLCs"
  #removing the marker
  rm .processing_it1
  numslc=`ls SLC | wc -l`
  if [ $numslc -gt 1 ]; then
   echo "there are "$numslc" SLCs to be coregistered. trying second iteration"
   ./framebatch_02_coreg_nowait.sh; ./framebatch_03_mk_ifg.sh; ./framebatch_04_unwrap.sh; ./framebatch_05_gap_filling_wait.sh
   exit
  else
   echo "great - all data are coregistered, continuing"
  fi
 fi
fi


if [ -z $2 ]; then echo "using default value of MAXBtemp="$MAXBTEMP; else MAXBTEMP=$2; fi
if [ -z $3 ]; then echo "using default value of range_looks="$orig_rlks; rlks=$orig_rlks; else rlks=$3; fi
if [ -z $4 ]; then echo "using default value of azimuth_looks="$orig_azlks; azlks=$orig_azlks; else azlks=$4; fi

if [ $rlks != $orig_rlks ] || [ $azlks != $orig_azlks ]; then
 echo "You have chosen for custom multilooking"
 echo "please note that these will be generated from all rslcs here and only for ifgs that do not exist in IFG"
 echo ""
fi
#NBATCH=5
NBATCH=$1
WORKFRAMEDIR=`pwd`
frame=`pwd | rev | cut -d '/' -f1 | rev`
master=`basename geo/20??????.hgt .hgt`
SCRATCHDIR=$LiCSAR_temp/gapfill_temp
rmdir $SCRATCHDIR/$frame 2>/dev/null

if [ $CHECKSCRATCH -eq 1 ]; then
 if [ -d $SCRATCHDIR/$frame ]; then
  echo "ERROR: the gapfill directory already exists:"
  echo $SCRATCHDIR/$frame
  echo "please check it yourself and delete manually"
  exit
 fi
fi
mkdir -p $SCRATCHDIR/$frame


#SCRATCHDIR=/work/scratch-nopw/licsar

if [ $qualcheck -eq 1 ]; then
 echo "first performing a quality check"
 cd ..
 frame_ifg_quality_check.py -l -d $frame
 cd $frame
fi

echo "Executing gap filling routine (results will be saved in this folder: "$WORKFRAMEDIR" )."
if [ `echo $frame | cut -c 11` != '_' ]; then echo "ERROR, you are not in FRAME folder. Exiting"; exit; fi
#if [ -z $BATCH_CACHE_DIR ]; then echo "BATCH_CACHE_DIR not set. Cancelling"; exit; fi

#decide for query based on user rights
#if [ `bugroup | grep $USER | gawk {'print $1'} | grep -c cpom_comet` -eq 1 ]; then
#  bsubquery='cpom-comet'
# else
#  bsubquery='par-single'
#  #bsubquery='short-serial'
#fi

if [ $prioritise -eq 1 ]; then
  bsubquery='cpom-comet'
  #bsubquery_multi='cpom-comet'
else
  bsubncores=1
  bsubquery='short-serial'
  #bsubquery_multi='par-single'
fi

#let's keeping it only for the cpom-comet group...
#bsubquery='cpom-comet'

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

# prepare the 5 combinations in a row
for FIRST in `cat gapfill_job/tmp_rslcs`; do
 SECOND=`grep -A1 $FIRST gapfill_job/tmp_rslcs | tail -n1`;
 THIRD=`grep -A2 $FIRST gapfill_job/tmp_rslcs | tail -n1`;
 FOURTH=`grep -A3 $FIRST gapfill_job/tmp_rslcs | tail -n1`;
 FIFTH=`grep -A4 $FIRST gapfill_job/tmp_rslcs | tail -n1`;
 for LAST in $SECOND $THIRD $FOURTH $FIFTH; do
  if [ `datediff $FIRST $LAST` -lt $MAXBTEMP ] && [ ! $FIRST == $LAST ]; then
   echo $FIRST'_'$LAST >> gapfill_job/tmp_ifg_all2;
  fi
 done
done

if [ $ADD36M -eq 1 ]; then
    maxconn=5
    #now, add 3 and 6 months data
    first=`head -n2 gapfill_job/tmp_rslcs | tail -n1`
    last=`tail -n2 gapfill_job/tmp_rslcs | head -n1`
    if [ `datediff $first $last` -gt 89 ]; then
     sed '/'$master'/d' gapfill_job/tmp_rslcs | grep 0[3,6,9][0-3][0-9] > gapfill_job/long_rslcs
     if [ `cat gapfill_job/long_rslcs | wc -l` -gt 1 ]; then
      echo "preparing 3/6 months connections"
      for year in `cat gapfill_job/long_rslcs | cut -c -4 | sort -u`; do
       #march connections
       for secmon in 6 9; do
           rm gapfill_job/long_ifgs 2>/dev/null
           for march in `grep $year'03' gapfill_job/long_rslcs`; do
            #connections with june and sep
            for LAST in `grep $year'0'$secmon gapfill_job/long_rslcs`; do
             echo $march'_'$LAST >> gapfill_job/long_ifgs
            done
           done
           #do max connections per episode
           if [ -f gapfill_job/long_ifgs ]; then
            shuf gapfill_job/long_ifgs | head -n $maxconn >> gapfill_job/tmp_ifg_all2
           fi
       done
       #june connections with sep
       rm gapfill_job/long_ifgs 2>/dev/null
       for june in `grep $year'06' gapfill_job/long_rslcs`; do
            #connections with june and sep
            for LAST in `grep $year'09' gapfill_job/long_rslcs`; do
             echo $june'_'$LAST >> gapfill_job/long_ifgs
            done
       done
       if [ -f gapfill_job/long_ifgs ]; then
         shuf gapfill_job/long_ifgs | head -n $maxconn >> gapfill_job/tmp_ifg_all2
       fi

       #sep connections with march next year
       rm gapfill_job/long_ifgs 2>/dev/null
       let year2=$year+1
       for sep in `grep $year'09' gapfill_job/long_rslcs`; do
        for LAST in `grep $year2'03' gapfill_job/long_rslcs`; do
          echo $sep'_'$LAST >> gapfill_job/long_ifgs
        done
       done
       if [ -f gapfill_job/long_ifgs ]; then
        shuf gapfill_job/long_ifgs | head -n $maxconn >> gapfill_job/tmp_ifg_all2
       fi
      done
     fi
    fi
fi

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
nifgmax=0; waitText=""; waitTextmosaic="";
if [ -f gapfill_job/tmp_rslcs2mosaic ]; then
 rm gapfill_job/mosaic.sh 2>/dev/null
 mkdir tab  2>/dev/null
 iws=""
 for s in `ls SLC/$master/$master.IW?.slc | cut -d '.' -f2`; do
   iws=$iws"'"$s"',";
 done
 if [ ! -f tab/$master'R_tab' ]; then
   echo "python3 -c \"from gamma_functions import make_SLC_tab; make_SLC_tab('tab/${master}R_tab','RSLC/$master/$master.rslc',[$iws])\"" >> gapfill_job/mosaic.sh
   echo "python3 -c \"from gamma_functions import make_SLC_tab; make_SLC_tab('tab/${master}_tab','SLC/$master/$master.slc',[$iws])\"" >> gapfill_job/mosaic.sh
  fi
 for image in `sort -u gapfill_job/tmp_rslcs2mosaic`; do
  #fix nonexisting tabs:
  if [ ! -f tab/$image'R_tab' ]; then
   for f in `ls RSLC/$image/$image.IW?.rslc`; do
    echo "./"$f" ./"$f".par ./"$f".TOPS_par" >> tab/$image'R_tab'
   done
  fi
  if [ ! -f tab/$image'R_tab' ]; then
   echo "python3 -c \"from gamma_functions import make_SLC_tab; make_SLC_tab('tab/${image}R_tab','RSLC/$image/$image.rslc',[$iws])\"" >> gapfill_job/mosaic.sh
  fi
  echo "SLC_mosaic_S1_TOPS tab/$image'R_tab' RSLC/$image/$image.rslc RSLC/$image/$image.rslc.par $rlks $azlks 0 tab/$master'R_tab'" >> gapfill_job/mosaic.sh
 done
 chmod 770 gapfill_job/mosaic.sh
 waitTextmosaic="ended('"$frame"_mosaic')"
fi
if [ ! -f tab/$master'R_tab' ]; then cp tab/$master'_tab' tab/$master'R_tab'; fi
for job in `seq 1 $nojobs`; do
 let nifg=$nifgmax+1
 let nifgmax=$nifgmax+$NBATCH
 sed -n ''$nifg','$nifgmax'p' gapfill_job/tmp_unw_todo | sort -u > gapfill_job/unwjob_$job
 sed -n ''$nifg','$nifgmax'p' gapfill_job/tmp_ifg_todo | sort -u > gapfill_job/ifgjob_$job
 if [ `wc -l gapfill_job/ifgjob_$job | gawk {'print $1'}` -eq 0 ]; then rm gapfill_job/ifgjob_$job; else
  #rm gapfill_job/ifgjob_$job.sh 2>/dev/null #just to clean..
  #deal with mosaics here..
  #if [ ! -f tab/$master'R_tab' ]; then cp tab/$master'_tab' tab/$master'R_tab'; fi
  #for image in `cat gapfill_job/ifgjob_$job`; do
  # if [ `grep -c $image gapfill_job/tmp_rslcs2mosaic` -gt 0 ]; then
  #  sed -i '/'$image'/d' gapfill_job/tmp_rslcs2mosaic
  #  echo "SLC_mosaic_S1_TOPS tab/$image'R_tab' RSLC/$image/$image.rslc RSLC/$image/$image.rslc.par $rlks $azlks 0 tab/$master'R_tab'" >> gapfill_job/ifgjob_$job.sh
  # fi
  #done
  echo "LiCSAR_03_mk_ifgs.py -d . -r $rlks -a $azlks -f $frame -c 0 -T gapfill_job/ifgjob_$job.log  -i gapfill_job/ifgjob_$job" > gapfill_job/ifgjob_$job.sh
  chmod 770 gapfill_job/ifgjob_$job.sh
 fi
 #need to edit the unwrap script below to also accept range/azi looks!
 #hmm... actually it seems that unwrap will work anyway...
 echo "LiCSAR_04_unwrap.py -d . -f $frame -T gapfill_job/unwjob_$job.log -l gapfill_job/unwjob_$job" > gapfill_job/unwjob_$job.sh
 waitText=$waitText" && ended("$frame"_unw_"$job")"
 chmod 770 gapfill_job/unwjob_$job.sh
done

#check if there is nothing to process, then just ... finish
if [ `wc -l gapfill_job/tmp_ifg_todo | gawk {'print $1'}` == 0 ] && [ `wc -l gapfill_job/tmp_unw_todo | gawk {'print $1'}` == 0 ]; then
 echo "there is nothing else to process - gapfilling done"
 if [ $geocode == 1 ]; then
  echo "starting geocoding job now"
  cd $WORKFRAMEDIR
  ./framebatch_06_geotiffs_nowait.sh
 fi
 #cleaning
 rm -r gapfill_job
 exit
fi






 #move it for processing in SCRATCHDIR
 echo "There are "`wc -l gapfill_job/tmp_ifg_todo | gawk {'print $1'}`" interferograms to process and "`wc -l gapfill_job/tmp_unw_todo | gawk {'print $1'}`" to unwrap."
 echo "Preparation phase: copying data to SCRATCH disk (may take long)"
 #if [ -d $SCRATCHDIR/$frame ]; then echo "..cleaning scratchdir"; rm -rf $SCRATCHDIR/$frame; fi
 mkdir -p $SCRATCHDIR/$frame/RSLC
 chmod -R 777 $SCRATCHDIR/$frame
 mkdir $SCRATCHDIR/$frame/IFG 2>/dev/null
 mkdir $SCRATCHDIR/$frame/SLC $SCRATCHDIR/$frame/LOGS  2>/dev/null
 if [ -f gapfill_job/tmp_rslcs2copy ]; then
  echo "..copying "`wc -l gapfill_job/tmp_rslcs2copy | gawk {'print $1'}`" needed rslcs"
  for rslc in `cat gapfill_job/tmp_rslcs2copy`; do if [ ! -d $SCRATCHDIR/$frame/RSLC/$rslc ]; then echo "copying "$rslc; cp -r RSLC/$rslc $SCRATCHDIR/$frame/RSLC/.; fi; done
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
 if [ $rlks != $orig_rlks ] || [ $azlks != $orig_azlks ]; then
  echo "preparing MLI and DEM for the custom multilooking"
  echo "(nothing will get rewritten in your workfolder)"
  #mkdir $SCRATCHDIR/$frame/DEM
  cp -r DEM $SCRATCHDIR/$frame/.
  cd $SCRATCHDIR/$frame
  #doing MLI for given rlks and azlks over master image
  rm SLC/$master/$master.slc.mli SLC/$master/$master.slc.mli.par SLC/$master/$master.slc.mli.bmp 2>/dev/null
  echo "..generating custom multilooked master"
  #SLC_mosaic_S1_TOPS tab/$master'_tab' SLC/$master/$master.mli SLC/$master/$master.mli.par $rlks $azlks 0 2>/dev/null
  multilookSLC $master $rlks $azlks 1 $SCRATCHDIR/$frame/SLC/$master
  echo "..recreating geocoding tables"
  python -c "from LiCSAR_lib.coreg_lib import geocode_dem; geocode_dem('"$SCRATCHDIR/$frame/SLC/$master"','"$SCRATCHDIR/$frame/geo"','"$SCRATCHDIR/$frame/DEM"','"$SCRATCHDIR/$frame"','"$master"')"
  #echo "..generating custom multilooked hgt file"
  #ml_width=`grep range_samples SLC/$master/$master.slc.mli.par | gawk {'print $2'}`
  #demwidth=`grep width geo/EQA.dem_par | gawk {'print $2'}`
  #rm geo/$master.hgt
  #geocode geo/$master.lt_fine geo/EQA.dem $demwidth geo/$master.hgt $ml_width - 2 0 - - - - - >/dev/null 2>/dev/null
  #rashgt geo/$master.hgt SLC/$master/$master.slc.mli $ml_width
 fi
##########################################################
 echo "running jobs"
 cd $SCRATCHDIR/$frame
 #weird error - mk_ifg is reading SLC tabs instead of rslc?? (need debug).. quick fix here:
 #for x in `ls tab/20??????_tab`; do cp `echo $x | sed 's/_tab/R_tab/'` $x; done

#first run mosaicking
if [ `echo $waitTextmosaic | wc -w` -gt 0 ]; then
 waitcmdmosaic="-w \""$waitTextmosaic"\""
 echo "..running for missing mosaics"
 bsub2slurm.sh -q $bsubquery -n 1 -W 06:00 -M 8000 -J $frame"_mosaic" gapfill_job/mosaic.sh >/dev/null
 #bsub -q $bsubquery -n 1 -W 04:00 -J $frame"_mosaic" gapfill_job/mosaic.sh >/dev/null
else
 waitcmdmosaic='';
fi

#now we can start jobs..
echo "..running "$nojobs" jobs to generate ifgs/unws"
for job in `seq 1 $nojobs`; do
 wait=''
 if [ -f gapfill_job/ifgjob_$job.sh ]; then
  #weird error in 'job not found'.. workaround:
#  echo bsub -q $bsubquery -n $bsubncores -W 05:00 -J $frame'_ifg_'$job -e gapfill_job/ifgjob_$job.err -o gapfill_job/ifgjob_$job.out $waitcmdmosaic gapfill_job/ifgjob_$job.sh > tmptmp
  echo bsub2slurm.sh -q $bsubquery -n 1 -W 05:00 -M 8000 -J $frame'_ifg_'$job -e gapfill_job/ifgjob_$job.err -o gapfill_job/ifgjob_$job.out $waitcmdmosaic gapfill_job/ifgjob_$job.sh > tmptmp
  chmod 777 tmptmp; ./tmptmp #>/dev/null
  #this wait text would work for unwrapping to wait for the previous job:
  wait="-w \"ended('"$frame"_ifg_"$job"')\""
 fi
 if [ -f gapfill_job/unwjob_$job.sh ]; then
  #weird error in 'job not found'.. workaround:
#  echo bsub -q $bsubquery -n $bsubncores -W 08:00 -J $frame'_unw_'$job -e `pwd`/$frame'_unw_'$job.err -o `pwd`/$frame'_unw_'$job.out $wait gapfill_job/unwjob_$job.sh > tmptmp
  echo bsub2slurm.sh -q $bsubquery -n 1 -W 12:00 -M 25000 -R "rusage[mem=25000]" -J $frame'_unw_'$job -e `pwd`/$frame'_unw_'$job.err -o `pwd`/$frame'_unw_'$job.out $wait gapfill_job/unwjob_$job.sh > tmptmp
  #echo "debug:"
  #cat tmptmp
  chmod 777 tmptmp
  ./tmptmp #>/dev/null
 fi
done

# copying and cleaning job
echo "..running job that will copy outputs from TEMP to your WORKDIR"
waitcmd=''
if [ `echo $waitText | wc -w` -gt 0 ]; then
  waitText=`echo $waitText | cut -c 4-`
  waitcmd='-w "'$waitText'"'
fi
echo "chmod -R 777 $SCRATCHDIR/$frame" > $WORKFRAMEDIR/gapfill_job/copyjob.sh
echo "rsync -r $SCRATCHDIR/$frame/IFG $WORKFRAMEDIR" >> $WORKFRAMEDIR/gapfill_job/copyjob.sh
echo "rsync -r $SCRATCHDIR/$frame/gapfill_job $WORKFRAMEDIR" >> $WORKFRAMEDIR/gapfill_job/copyjob.sh
echo "echo 'sync done, deleting TEMP folder'" >> $WORKFRAMEDIR/gapfill_job/copyjob.sh
echo "cd $WORKFRAMEDIR" >> $WORKFRAMEDIR/gapfill_job/copyjob.sh
if [ $geocode == 1 ]; then
 echo "echo 'starting geocoding job'" >> $WORKFRAMEDIR/gapfill_job/copyjob.sh
 echo $WORKFRAMEDIR/framebatch_06_geotiffs_nowait.sh >> $WORKFRAMEDIR/gapfill_job/copyjob.sh
 echo "sleep 60" >> $WORKFRAMEDIR/gapfill_job/copyjob.sh
fi
echo "rm -rf $SCRATCHDIR/$frame" >> $WORKFRAMEDIR/gapfill_job/copyjob.sh
chmod 770 $WORKFRAMEDIR/gapfill_job/copyjob.sh
#workaround for 'Empty job. Job not submitted'
echo bsub2slurm.sh -q $bsubquery -n 1 $waitcmd -W 08:00 -M 8000 -J $frame'_gapfill_out' -e $WORKFRAMEDIR/LOGS/framebatch_gapfill_postproc.err -o $WORKFRAMEDIR/LOGS/framebatch_gapfill_postproc.out $WORKFRAMEDIR/gapfill_job/copyjob.sh > $WORKFRAMEDIR/gapfill_job/tmptmp
#echo bsub -q $bsubquery -n 1 $waitcmd -W 08:00 -J $frame'_gapfill_out' -e $WORKFRAMEDIR/LOGS/framebatch_gapfill_postproc.err -o $WORKFRAMEDIR/LOGS/framebatch_gapfill_postproc.out $WORKFRAMEDIR/gapfill_job/copyjob.sh > $WORKFRAMEDIR/gapfill_job/tmptmp
#echo "debug last:"
#cat $WORKFRAMEDIR/gapfill_job/tmptmp
chmod 777 $WORKFRAMEDIR/gapfill_job/tmptmp; $WORKFRAMEDIR/gapfill_job/tmptmp
#rm $WORKFRAMEDIR/gapfill_job/tmptmp
cd -
