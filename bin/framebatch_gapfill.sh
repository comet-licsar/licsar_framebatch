#!/bin/bash
MAXBTEMP=181
orig_rlks=20
orig_azlks=4
rlks=$orig_rlks
azlks=$orig_azlks
#bsubncores=16
#according to CEDA Support, we should keep 1 process per processor.
#but -n1 was working usually fine... so keeping -n1
bsubncores=1
geocode=0
waiting=0
store=0
ADD36M=1
CHECKSCRATCH=1
prioritise=0
checkrslc=1
ifg_combinations=4
tienshan=0
volcs_south=0
checkMosaic=1
locl=0
dobovl=0
dounw=1
# for S1A or S1B only
A=0
B=0
ifglist=''

source $LiCSARpath/lib/LiCSAR_bash_lib.sh
#quality checker here is the basic one. but still it does problems! e.g. Iceland earthquake - took long to process due to tech complications
#and just after this was done, this auto-checker detected it as problematic and deleted those wonderful ifgs!!
#it is all the no-ESD test that is performed over whole image, and not only at the edges of bursts. so rather keep =0
qualcheck=0
shscript=''

if [ -z $1 ]; then echo "Usage: framebatch_gapfill.sh NBATCH [MAXBTEMP] [range_looks] [azimuth_looks]";
                   echo "NBATCH.... number of interferograms to generate per computing job (licsar defaults to 5)";
                   echo "MAXBTEMP.. max temporal baseline in days. Default is "$MAXBTEMP" [days]";
                   echo "range_looks and azimuth_looks - defaults are range_looks="$orig_rlks" and azimuth_looks="$orig_azlks;
#                  echo "parameter -w ... will wait for the unwrapping jobs to end (useful only if unwrap is running, see licsar_make_frame)";
                   echo "parameter -n ... set custom number of max ifg combinations. default is -n 4"
                   echo "parameter -g ... will run further framebatch step, i.e. geocoding"
                   echo "parameter -S ... will run store after geocoding.."
                   echo "parameter -P ... prioritise (run through cpom-comet)"
                   echo "parameter -i ifg.list ... add ifg pairs from the given ifg.list file"
                   echo "parameter -o ... no check if gapfill dir exists - DO NOT USE IF NOT SURE WHETHER ANOTHER GAPFILL IN PROGRESS"
                   echo "parameter -T ... Tien Shan strategy - do connections starting May etc."
                   echo "parameter -A or -B .. do only S1A/S1B combinations"
                   echo "parameter -l ... use local processing strategy - e.g. volc responder 2.0"
                   echo "parameter -b ... will do burst overlap ddiff ifgs AND SBOVLS (added by M. Nergizci)"
                   echo "parameter -s foo.sh ... run a shell script foo.sh automatically after ifg-gapfilling"
                   echo "parameter -N ... this will SKIP unwrapping (useful if you plan using LiCSBAS02to05_unwrap)"
                   exit; fi

while getopts ":wn:gSaABi:Pos:lbTN" option; do
 case "${option}" in
  A) A=1; echo "S1A only";
      ;;
  B) B=1; echo "S1B only";
      ;;
  b) dobovl=1; echo "will generate (filtered) bovl ifgs";
      ;;
  l) locl=1; checkrslc=0; tienshan=0; checkMosaic=0;
      ;;
  w ) waiting=1; echo "parameter -w set: will wait for standard unwrapping before ifg gap filling";
#      shift
      ;;
  n ) ifg_combinations=$OPTARG; echo "setting number of ifg combinations per epoch to "$OPTARG;
#      shift
      ;;
  g ) geocode=1; echo "parameter -g set: will do post-processing step - geocoding after the finish";
      echo "WARNING, this parameter is obsolete (since all data should be already geocoded during mk_ifg/mk_unw)";
#      shift
      ;;
  S ) store=1; echo "parameter -S set: will store after the processing";
#      shift
      ;;
  P ) prioritise=1; echo "parameter -P set: prioritising through cpom-comet";
#      shift
      ;;
  o ) CHECKSCRATCH=0; echo "skipping check for existing frame on LiCSAR_temp";
      ;;
  T ) tienshan=1; echo "arranging ifg connections strategy for Tien Shan";
      ;;
  i ) ifglist=$OPTARG; echo "adding ifgs from the text file "$ifglist;
#      shift
      ;;
  s ) shscript=$OPTARG; echo "will run this script afterwards: "$shscript;
#      shift
      ;;
  N ) dounw=0; echo "skipping standard unwrapping";
      ;;
  esac
done
shift $((OPTIND-1))


if [ ! -z $2 ]; then MAXBTEMP=$2; fi
if [ ! -z $3 ]; then rlks=$3; fi
if [ ! -z $4 ]; then azlks=$4; fi


# read local config parameters
if [ -f local_config.py ]; then
  if [ `grep ^tienshan local_config.py | cut -d '=' -f2 | sed 's/ //g'` -eq 1 ] 2>/dev/null; then
   echo "setting to Tien Shan frames processing"
   tienshan=1
  fi
  if [ `grep ^volcs_south local_config.py | cut -d '=' -f2 | sed 's/ //g'` -eq 1 ] 2>/dev/null; then
   echo "setting to S American volcanoes strategy"
   volcs_south=1
   if [ $tienshan == 1 ]; then echo "disabling the Tien Shan strategy"; fi
   tienshan=0
  fi
  if [ `grep ^bovl local_config.py | cut -d '=' -f2 | sed 's/ //g'` -eq 1 ] 2>/dev/null; then
   echo "do bovl ifgs";
   dobovl=1;
  fi
  max_ifg_comb=`grep ^max_ifg_comb local_config.py | cut -d '=' -f2 | sed 's/ //g'`
  if [ $max_ifg_comb -gt 0 ] 2>/dev/null; then
   ifg_combinations=$max_ifg_comb
  fi
  max_ifg_btemp=`grep ^max_ifg_btemp local_config.py | cut -d '=' -f2 | sed 's/ //g'`
  if [ $max_ifg_btemp -gt 0 ] 2>/dev/null; then
   MAXBTEMP=$max_ifg_btemp
  fi
  rglkstemp=`grep ^rglks local_config.py | cut -d '=' -f2 | sed 's/ //g'`
  if [ $rglkstemp -gt 0 ] 2>/dev/null; then
   rlks=$rglkstemp
   orig_rlks=$rglkstemp
  fi
  azlkstemp=`grep ^azlks local_config.py | cut -d '=' -f2 | sed 's/ //g'`
  if [ $azlkstemp -gt 0 ] 2>/dev/null; then
   azlks=$azlkstemp
   orig_azlks=$azlkstemp
  fi
fi

#NBATCH=5
NBATCH=$1
WORKFRAMEDIR=`pwd`
mkdir -p $WORKFRAMEDIR/LOGS
#if [ -f local_config.py ]; then
# noifg=`grep '^ifg_connections' local_config.py | cut -d '=' -f2`
# if [ ! -z $noifg ]; then
#  ifg_combinations=$noifg
#  echo "setting custom ifg combination number to "$ifg_combinations
# fi
#fi
# ifg_combinations=
#fi
frame=`pwd | rev | cut -d '/' -f1 | rev`

if [ $locl == 1 ]; then
 frame=local_`pwd | rev | cut -d '/' -f2 | rev`_$frame
fi


if [ $checkrslc -eq 1 ]; then
 #to fix situation when RSLCs already exist...
 master=`ls geo/????????.hgt | cut -d '/' -f2 | cut -d '.' -f1`
 for slc in `ls SLC`; do
  if [ ! $master == $slc ]; then
    if [ -d RSLC/$slc ]; then
      #echo "to remove: "$slc
      rm -rf SLC/$slc
    fi
  fi
 done
 if [ -f .processing_it1 ]; then
  echo "performing check of SLCs"
  #removing the marker
  rm .processing_it1
  numslc=`ls SLC | wc -l` 
  if [ $numslc -gt 1 ]; then
   echo "there are "$numslc" SLCs to be coregistered. trying second iteration"
   framebatch_postproc_coreg.sh $frame 1
   #./framebatch_02_coreg.nowait.sh; ./framebatch_03_mk_ifg.wait.sh; ./framebatch_04_unwrap.wait.sh; ./framebatch_05_gap_filling.wait.sh
   exit
  else
   echo "great - all data are coregistered, continuing"
  fi
 fi
fi


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

rm -rf $SCRATCHDIR/$frame 2>/dev/null
mkdir -p $SCRATCHDIR/$frame


#SCRATCHDIR=/work/scratch-nopw/licsar

if [ $qualcheck -eq 1 ]; then
 echo "first performing a quality check"
 cd ..
 frame_ifg_quality_check.py -l -d $frame
 cd $frame
fi

if [ $locl == 0 ]; then
 echo "Executing gap filling routine (results will be saved in this folder: "$WORKFRAMEDIR" )."
 if [ `echo $frame | cut -c 5` != '_' ]; then echo "ERROR, you are not in FRAME folder. Exiting"; exit; fi
fi
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

# sometimes the GEOC/* dirs are empty!! not sure why, but let us fix this:
rm GEOC/*/gmt.history 2>/dev/null
rm GEOC/????????_???????? 2>/dev/null
rmdir GEOC/????????_???????? 2>/dev/null

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

if [ $locl == 0 ]; then
echo "fixing missing geocoded MLIs (should be fast)"
track=`track_from_frame $frame`
if [ ! -d GEOC.MLI ]; then mkdir GEOC.MLI; fi
for x in `ls RSLC`; do
 if [ ! -d GEOC.MLI/$x ]; then
  if [ ! -f $LiCSAR_public/$track/$frame/epochs/$x/$x.geo.mli.tif ]; then
   echo "generating MLI for "$x
   create_geoctiffs_to_pub.sh -M `pwd` $x >/dev/null
  fi
 fi
done
else
echo "doing local proc - skipping check for GEOC.MLI - only ifgs"
fi

if [ ! -f SLC/$master/$master.slc.mli ]; then
  echo "multilooking master SLC"
  multilookSLC $master $rlks $azlks 1 SLC/$master
fi

if [ ! -f RSLC/$master/$master.rslc.mli ]; then
  ln -s `pwd`/SLC/$master/$master.slc.mli `pwd`/RSLC/$master/$master.rslc.mli
fi

echo "check for MLIs/regenerating if needed"
for x in `ls RSLC`; do
 if [ ! -f RSLC/$x/$x.rslc.mli ]; then
  #echo "multilooking "$x
  multilookRSLC $x $rlks $azlks 1 RSLC/$x
 fi
done

echo "getting list of ifg to fill"
if [ ! -d IFG ]; then mkdir IFG; fi
if [ ! -d GEOC ]; then mkdir GEOC; fi
# for S1A/B only:
if [ $A == 1 ]; then
 rm gapfill_job/tmp_rslcs 2>/dev/null
 for mp in `ls RSLC/20??????/*rslc.mli.par`; do
   if [ `grep ^sensor $mp | gawk {'print $2'}` == 'S1A' ]; then
     echo $mp | cut -d '/' -f2 >> gapfill_job/tmp_rslcs
   fi
 done
elif [ $B == 1 ]; then
 rm gapfill_job/tmp_rslcs 2>/dev/null
 for mp in `ls RSLC/20??????/*rslc.mli.par`; do
   if [ `grep ^sensor $mp | gawk {'print $2'}` == 'S1B' ]; then
     echo $mp | cut -d '/' -f2 >> gapfill_job/tmp_rslcs
   fi
 done
else
 ls RSLC/20??????/*rslc.mli | cut -d '/' -f2 > gapfill_job/tmp_rslcs
fi
#ls IFG/20*_20??????/*.cc 2>/dev/null | cut -d '/' -f2 > gapfill_job/tmp_ifg_existing
ls GEOC/20*_20??????/*.cc.tif 2>/dev/null | cut -d '/' -f2 > gapfill_job/tmp_ifg_existing
#rm gapfill_job/tmp_ifg_all2 2>/dev/null

# prepare the 5 combinations in a row
for FIRST in `cat gapfill_job/tmp_rslcs`; do 
 for i in `seq 1 $ifg_combinations`; do
  last=`grep -A$i $FIRST gapfill_job/tmp_rslcs | tail -n1`;
  if [ `datediff $FIRST $last` -lt $MAXBTEMP ] && [ ! $FIRST == $last ]; then
   echo $FIRST'_'$last >> gapfill_job/tmp_ifg_all2;
  fi
 done 
done


if [ $volcs_south -eq 1 ]; then
  echo "preparing S American volcs connections (all Dec-Feb up to 1 yr)"
  rm gapfill_job/tmp_selrslcs 2>/dev/null
  for rslc in `cat gapfill_job/tmp_rslcs`; do
    if [ ${rslc:4:2} == '11' ] || [ ${rslc:4:2} == '12' ] || [ ${rslc:4:2} == '01' ] || [ ${rslc:4:2} == '02' ]; then
      echo $rslc >> gapfill_job/tmp_selrslcs
    fi
  done
  for rslc in `cat gapfill_job/tmp_selrslcs`; do
    for rslc2 in `cat gapfill_job/tmp_selrslcs`; do
      if [ $rslc2 -gt $rslc ]; then
       if [ `datediff $rslc $rslc2` -lt 90 ]; then
        echo $rslc'_'$rslc2 >> gapfill_job/tmp_ifg_all2
       elif [ `datediff $rslc $rslc2` -lt 456 ]; then
        echo $rslc'_'$rslc2 >> gapfill_job/tmp_ifg_all2
       fi
      fi
    done
  done
fi


if [ $tienshan -eq 1 ]; then
    echo "preparing Tien Shan connections"
    # Pick month to start connections from. Default to May unless stated
    if [ `grep -c startmonth $LiCSAR_procdir/$track/$frame/local_config.py 2>/dev/null` -gt 0 ]; then
       startmonth=`grep ^startmonth $LiCSAR_procdir/$track/$frame/local_config.py | cut -d '=' -f2 | sed 's/ //g'`
    else
       startmonth=5
    fi
    MONTHS=(ZERO Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)
    echo 'Start Month:' ${MONTHS[$startmonth]}
    
    maxconn=100
    first=`head -n2 gapfill_job/tmp_rslcs | tail -n1`
    last=`tail -n2 gapfill_job/tmp_rslcs | head -n1`
    if [ `datediff $first $last` -gt 89 ]; then
      cp gapfill_job/tmp_rslcs gapfill_job/long_rslcs
    fi
    #do 
    for year in `cat gapfill_job/long_rslcs | cut -c -4 | sort -u`; do
       let year1=$year
       let year2=$year+1
       #let year3=$year+2
       #3 months connections
       rm gapfill_job/long_ifgs 2>/dev/null
       #for month1 in 5 6 7 8; do
       for month1 in `seq $startmonth $(expr $startmonth + 3)`; do
         let month2=$month1+3
         # Reformat months to be 01-12
         if [ $month1 -gt 12 ]; then let month1=$month1-12; let year1=$year+1; fi 
         if [ $month1 -lt 10 ]; then month1='0'$month1; fi
         if [ $month2 -gt 12 ]; then let month2=$month2-12; let year2=$year+1; fi
         if [ $month2 -lt 10 ]; then month2='0'$month2; fi
         for firstdate in `grep ^$year1$month1 gapfill_job/long_rslcs`; do
           for lastdate in `grep ^$year2$month2 gapfill_job/long_rslcs`; do
             echo $firstdate'_'$lastdate >> gapfill_job/long_ifgs
           done
         done
       done
       if [ -f gapfill_job/long_ifgs ]; then
        shuf gapfill_job/long_ifgs | head -n $maxconn >> gapfill_job/tmp_ifg_all2
       fi
       
       
       #6 months connections: May, Nov
       rm gapfill_job/long_ifgs 2>/dev/null
       #for month1 in 5 11; do
       for month1 in $startmonth $(expr $startmonth + 6); do 
         let month2=$month1+6
         let year1=$year
	 let year2=$year
	 if [ $month1 -gt 12 ]; then let month1=$month1-12; let year1=$year+1; fi 
         if [ $month2 -gt 12 ]; then let month2=$month2-12; let year2=$year+1; fi
         if [ $month1 -lt 10 ]; then month1='0'$month1; fi
         if [ $month2 -lt 10 ]; then month2='0'$month2; fi
         for firstdate in `grep ^$year1$month1 gapfill_job/long_rslcs`; do
           for lastdate in `grep ^$year2$month2 gapfill_job/long_rslcs`; do
             echo $firstdate'_'$lastdate >> gapfill_job/long_ifgs
           done
         done
       done
       if [ -f gapfill_job/long_ifgs ]; then
        shuf gapfill_job/long_ifgs | head -n $maxconn >> gapfill_job/tmp_ifg_all2
       fi
       
       
       #9 months connections: Aug, Sep, Oct, Nov
       rm gapfill_job/long_ifgs 2>/dev/null
       #for month1 in 8 9 10 11; do
       for month1 in `seq $(expr $startmonth + 3) $(expr $startmonth + 6)`; do
         let month2=$month1+9
         let year1=$year
         let year2=$year
         if [ $month1 -gt 12 ]; then let month1=$month1-12; let year1=$year+1; fi
         if [ $month2 -gt 12 ]; then let month2=$month2-12; let year2=$year+1; fi
         if [ $month1 -lt 10 ]; then month1='0'$month1; fi
         if [ $month2 -lt 10 ]; then month2='0'$month2; fi
         for firstdate in `grep ^$year1$month1 gapfill_job/long_rslcs`; do
           for lastdate in `grep ^$year2$month2 gapfill_job/long_rslcs`; do
             echo $firstdate'_'$lastdate >> gapfill_job/long_ifgs
           done
         done
       done
       if [ -f gapfill_job/long_ifgs ]; then
        shuf gapfill_job/long_ifgs | head -n $maxconn >> gapfill_job/tmp_ifg_all2
       fi

       #12 months connections: May, Jun, Jul, Aug, Sep, Oct, Nov
       rm gapfill_job/long_ifgs 2>/dev/null
       #for month1 in 5 6 7 8 9 10 11; do
       for month1 in `seq $startmonth $(expr $startmonth + 6)`; do
	 let year1=$year
         if [ $month1 -gt 12 ]; then let month1=$month1-12; let year1=$year+1; fi
         let year2=$year1+1 
         let month2=$month1
         if [ $month1 -lt 10 ]; then month1='0'$month1; fi

#         let month2=$month1
#         let year2=$year+1
#         if [ $month1 -lt 10 ]; then month1='0'$month1; fi
#         if [ $month2 -lt 10 ]; then month2='0'$month2; fi
         for firstdate in `grep ^$year1$month1 gapfill_job/long_rslcs`; do
           for lastdate in `grep ^$year2$month2 gapfill_job/long_rslcs`; do
             echo $firstdate'_'$lastdate >> gapfill_job/long_ifgs
           done
         done
       done
       if [ -f gapfill_job/long_ifgs ]; then
        shuf gapfill_job/long_ifgs | head -n $maxconn >> gapfill_job/tmp_ifg_all2
       fi
    done;

else
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

       #sep connections with june next year
       rm gapfill_job/long_ifgs 2>/dev/null
       let year2=$year+1
       for sep in `grep $year'09' gapfill_job/long_rslcs`; do
        for LAST in `grep $year2'06' gapfill_job/long_rslcs`; do
          echo $sep'_'$LAST >> gapfill_job/long_ifgs
        done
       done
       if [ -f gapfill_job/long_ifgs ]; then
        shuf gapfill_job/long_ifgs | head -n $maxconn >> gapfill_job/tmp_ifg_all2
       fi
       
       # added in 07/2021 - also 12 month connections..
       #sep connections with sep next year
       rm gapfill_job/long_ifgs 2>/dev/null
       let year2=$year+1
       for sep in `grep $year'09' gapfill_job/long_rslcs`; do
        for LAST in `grep $year2'09' gapfill_job/long_rslcs`; do
          echo $sep'_'$LAST >> gapfill_job/long_ifgs
        done
       done
       if [ -f gapfill_job/long_ifgs ]; then
        shuf gapfill_job/long_ifgs | head -n $maxconn >> gapfill_job/tmp_ifg_all2
       fi
       #mar connections with mar next year
       rm gapfill_job/long_ifgs 2>/dev/null
       let year2=$year+1
       for sep in `grep $year'03' gapfill_job/long_rslcs`; do
        for LAST in `grep $year2'03' gapfill_job/long_rslcs`; do
          echo $sep'_'$LAST >> gapfill_job/long_ifgs
        done
       done
       if [ -f gapfill_job/long_ifgs ]; then
        shuf gapfill_job/long_ifgs | head -n $maxconn >> gapfill_job/tmp_ifg_all2
       fi
       #june connections with mar next year
       rm gapfill_job/long_ifgs 2>/dev/null
       let year2=$year+1
       for sep in `grep $year'06' gapfill_job/long_rslcs`; do
        for LAST in `grep $year2'03' gapfill_job/long_rslcs`; do
          echo $sep'_'$LAST >> gapfill_job/long_ifgs
        done
       done
       if [ -f gapfill_job/long_ifgs ]; then
        shuf gapfill_job/long_ifgs | head -n $maxconn >> gapfill_job/tmp_ifg_all2
       fi
       
        #june connections with june next year
       rm gapfill_job/long_ifgs 2>/dev/null
       let year2=$year+1
       for sep in `grep $year'06' gapfill_job/long_rslcs`; do
        for LAST in `grep $year2'06' gapfill_job/long_rslcs`; do
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
fi

# adding from the txt file here:
if [ ! -z $ifglist ]; then
 cat $ifglist >> gapfill_job/tmp_ifg_all2
fi

#cat gapfill_job/tmp_ifg_all2 | head -n-5 | sort -u > gapfill_job/tmp_ifg_all
cat gapfill_job/tmp_ifg_all2 | sort -u > gapfill_job/tmp_ifg_all # this is the important file with ALL ifgs..
if [ $dobovl -eq 1 ]; then
 cp gapfill_job/tmp_ifg_all gapfill_job/tmp_bovl_todo
 for x in `ls GEOC/*/*.cc.tif 2>/dev/null | cut -d '/' -f2`; do
  if [ -f GEOC/$x/$x.geo.sbovldiff.adf.mm.tif ]; then
   sed -i '/'$x'/d' gapfill_job/tmp_bovl_todo
  fi
 done
 for x in `cat gapfill_job/tmp_bovl_todo | sed 's/_/ /'`; do echo $x >> gapfill_job/tmp_rslcs2copy; done
fi

for ifg in `cat gapfill_job/tmp_ifg_existing`; do  sed -i '/'$ifg'/d' gapfill_job/tmp_ifg_all; done
sed 's/_/ /' gapfill_job/tmp_ifg_all > gapfill_job/tmp_ifg_todo
#rm gapfill_job/tmp_rslcs2copy 2>/dev/null
for x in `cat gapfill_job/tmp_ifg_todo`; do echo $x >> gapfill_job/tmp_rslcs2copy; done
sort -u gapfill_job/tmp_rslcs2copy -o gapfill_job/tmp_rslcs2copy 2>/dev/null
mv gapfill_job/tmp_ifg_all gapfill_job/tmp_unw_todo
#for x in `ls IFG/*/*.cc 2>/dev/null | cut -d '/' -f2`; do if [ ! -f IFG/$x/$x.unw ]; then echo $x >> gapfill_job/tmp_unw_todo; fi; done
for x in `ls GEOC/*/*.cc.tif 2>/dev/null | cut -d '/' -f2`; do if [ ! -f GEOC/$x/$x.geo.unw.tif ]; then echo $x >> gapfill_job/tmp_unw_todo; fi; done
#if [ $dobovl -eq 1 ]; then
# for x in `ls GEOC/*/*.cc.tif 2>/dev/null | cut -d '/' -f2`; do if [ ! -f GEOC/$x/$x.geo.bovldiff.tif ]; then echo $x >> gapfill_job/tmp_bovl_todo; fi; done
#fi

#check rslc mosaics
#rm gapfill_job/tmp_rslcs2mosaic 2>/dev/null
for x in `cat gapfill_job/tmp_rslcs2copy` $master; do
 if [ ! -f RSLC/$x/$x.rslc ]; then
  echo $x >> gapfill_job/tmp_rslcs2mosaic
 fi
done

cat gapfill_job/tmp_unw_todo gapfill_job/tmp_bovl_todo | sort | uniq > gapfill_job/tmp_combined_todo
NOIFG=`cat gapfill_job/tmp_combined_todo | wc -l`
nojobs=`echo $NOIFG/$NBATCH | bc`
nojobs10=`echo $NOIFG*10/$NBATCH | bc | rev | cut -c 1 | rev`
if [ $nojobs10 -gt 0 ]; then let nojobs=$nojobs+1; fi

#distribute ifgs for processing jobs and run them
nifgmax=0; waitText=""; waitTextmosaic="";
if [ $checkMosaic -eq 1 ]; then
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
 chmod 777 gapfill_job/mosaic.sh
 waitTextmosaic="ended('"$frame"_mosaic')"
fi
if [ ! -f tab/$master'R_tab' ]; then cp tab/$master'_tab' tab/$master'R_tab'; fi
fi

if [ $locl == 0 ]; then
l03extra=' -f '$frame
else l03extra='';
fi


for job in `seq 1 $nojobs`; do
    let nifg=$nifgmax+1
    let nifgmax=$nifgmax+$NBATCH
    
    # Create job files by selecting lines from the to-do lists
    sed -n ''$nifg','$nifgmax'p' gapfill_job/tmp_unw_todo | sort -u > gapfill_job/unwjob_$job
    sed -n ''$nifg','$nifgmax'p' gapfill_job/tmp_ifg_todo | sort -u > gapfill_job/ifgjob_$job

    # Check if dobovl is enabled to create bovljob files
    if [ $dobovl == 1 ]; then
        sed -n ''$nifg','$nifgmax'p' gapfill_job/tmp_bovl_todo | sort -u > gapfill_job/bovljob_$job
        
        # Check if bovljob file is empty, if so, remove it; otherwise, prepare the job script
        if [ `wc -l < gapfill_job/bovljob_$job` -eq 0 ]; then
            rm gapfill_job/bovljob_$job
        else
            # Add commands to the bovljob script
            echo "cat gapfill_job/bovljob_$job | sed 's/ /_/' | parallel -j 1 create_soi.py -p " >> gapfill_job/bovljob_$job.sh
            echo "cat gapfill_job/bovljob_$job | sed 's/ /_/' | parallel -j 1 create_bovl_ifg.sh " >> gapfill_job/bovljob_$job.sh
            echo "cat gapfill_job/bovljob_$job | sed 's/ /_/' | parallel -j 1 create_sbovl_ifg.py " >> gapfill_job/bovljob_$job.sh
            chmod 777 gapfill_job/bovljob_$job.sh
            waitText=$waitText" && ended('"$frame"_bovl_"$job"')"
        fi
    fi

    # Check if ifgjob file is empty, if so, remove it; otherwise, prepare the job script
    if [ `wc -l < gapfill_job/ifgjob_$job` -eq 0 ]; then
        rm gapfill_job/ifgjob_$job
    else
        echo "LiCSAR_03_mk_ifgs.py -d . -r $rlks -a $azlks"$l03extra" -c 0 -T gapfill_job/ifgjob_$job.log  -i gapfill_job/ifgjob_$job" > gapfill_job/ifgjob_$job.sh
        chmod 777 gapfill_job/ifgjob_$job.sh
    fi

    # Check if unwjob file is empty, if so, remove it; otherwise, prepare the job script
    if [ `wc -l < gapfill_job/unwjob_$job` -eq 0 ]; then
        rm gapfill_job/unwjob_$job
    else
        echo "cat gapfill_job/unwjob_$job | parallel -j 1 create_geoctiffs_to_pub.sh -I "`pwd`" " > gapfill_job/unwjob_$job.sh
        echo "cat gapfill_job/unwjob_$job | parallel -j 1 create_geoctiffs_to_pub.sh -C "`pwd`" " >> gapfill_job/unwjob_$job.sh
        if [ $dounw == 1 ]; then
            echo "cat gapfill_job/unwjob_$job | parallel -j 1 unwrap_geo.sh $frame" >> gapfill_job/unwjob_$job.sh
        fi
        waitText=$waitText" && ended('"$frame"_unw_"$job"')"
        chmod 777 gapfill_job/unwjob_$job.sh
    fi
done


#check if there is nothing to process, then just ... finish
cancel=0
if [ ! -f gapfill_job/tmp_ifg_todo ]; then cancel=1; fi
if [ ! -f gapfill_job/tmp_unw_todo ]; then cancel=1; fi
if [ `wc -l gapfill_job/tmp_ifg_todo | gawk {'print $1'}` == 0 ] && [ `wc -l gapfill_job/tmp_unw_todo | gawk {'print $1'}` == 0 ]; then
 cancel=1
 if [ $dobovl == 1 ]; then
  if [ `wc -l gapfill_job/tmp_bovl_todo | gawk {'print $1'}` -gt 0 ]; then
   cancel=0
  fi
 fi
fi



if [ $cancel == 1 ]; then
 echo "there is nothing else to process - gapfilling done"
 rm -r gapfill_job
 if [ $store == 1 ]; then
  echo "now storing back to LiCSAR base"
  cd ..
  store_to_curdir.sh $frame
 fi
 exit
fi


 #move it for processing in SCRATCHDIR
 #if [ `echo $BATCH_CACHE_DIR | grep -c scratch` -eq 1 ]; then 
 if [ `echo $WORKFRAMEDIR | cut -d '/' -f3` == `echo $SCRATCHDIR | cut -d '/' -f3` ]; then
  echo "BATCH_CACHE_DIR is in scratch - making only links (faster)"
  links=1
 else
  links=0
  echo "Preparation phase: copying data to SCRATCH disk (may take long)"
 fi
 echo "There are "`wc -l gapfill_job/tmp_ifg_todo | gawk {'print $1'}`" interferograms to process and "`wc -l gapfill_job/tmp_unw_todo | gawk {'print $1'}`" to unwrap."
 if [ $dobovl == 1 ]; then
  echo "(and "`wc -l gapfill_job/tmp_bovl_todo | gawk {'print $1'}`" subswath+burst overlap ifgs (sbovls) to generate)"
 fi
 #if [ -d $SCRATCHDIR/$frame ]; then echo "..cleaning scratchdir"; rm -rf $SCRATCHDIR/$frame; fi
 mkdir -p $SCRATCHDIR/$frame/RSLC
 chmod 777 $SCRATCHDIR/$frame
 mkdir $SCRATCHDIR/$frame/IFG 2>/dev/null
 if [ $links == 1 ]; then
   cd $SCRATCHDIR/$frame;
   ln -s $WORKFRAMEDIR/GEOC; mkdir -p $WORKFRAMEDIR/GEOC;
   ln -s $WORKFRAMEDIR/GEOC.MLI; mkdir -p $WORKFRAMEDIR/GEOC.MLI;
   cd -
 else
   mkdir $SCRATCHDIR/$frame/GEOC $SCRATCHDIR/$frame/GEOC.MLI 2>/dev/null
 fi
 mkdir $SCRATCHDIR/$frame/SLC $SCRATCHDIR/$frame/LOGS  2>/dev/null
 if [ -f gapfill_job/tmp_rslcs2copy ]; then
  if [ $links == 1 ]; then
   for rslc in `cat gapfill_job/tmp_rslcs2copy`; do
    if [ ! -d $SCRATCHDIR/$frame/RSLC/$rslc ]; then ln -s `pwd`/RSLC/$rslc $SCRATCHDIR/$frame/RSLC/$rslc; fi;
   done
  else
   echo "..copying "`wc -l gapfill_job/tmp_rslcs2copy | gawk {'print $1'}`" needed rslcs"
   for rslc in `cat gapfill_job/tmp_rslcs2copy`; do
    if [ ! -d $SCRATCHDIR/$frame/RSLC/$rslc ]; then echo "copying "$rslc; cp -r RSLC/$rslc $SCRATCHDIR/$frame/RSLC/.; fi;
   done
  fi
 fi
 echo "..copying master slc"
 cp -r SLC/$master $SCRATCHDIR/$frame/SLC/.
 rm -r $SCRATCHDIR/$frame/RSLC/$master 2>/dev/null
 mkdir $SCRATCHDIR/$frame/RSLC/$master
 for x in `ls $SCRATCHDIR/$frame/SLC/$master/*`; do ln -s $x $SCRATCHDIR/$frame/RSLC/$master/`basename $x | sed 's/slc/rslc/'`; done
 if [ $links == 1 ]; then
  for aa in tab geo log ; do ln -s `pwd`/$aa $SCRATCHDIR/$frame/$aa; done
 else
  echo "..copying geo and other files"
  cp -r tab geo log $SCRATCHDIR/$frame/.
 fi
 
 cp -r gapfill_job $SCRATCHDIR/$frame/.
 #sed 's/ /_/' gapfill_job/tmp_ifg_todo > gapfill_job/tmp_ifg_copy
 cat gapfill_job/tmp_unw_todo >> gapfill_job/tmp_ifg_copy
 echo "..copying (or linking) ifgs to unwrap only"
 for ifg in `cat gapfill_job/tmp_unw_todo`; do 
  #if [ -d IFG/$ifg ]; then cp -r IFG/$ifg $SCRATCHDIR/$frame/IFG/.; fi;
  if [ -d GEOC/$ifg ]; then
   #if [ $links == 1 ]; then
   # ln -s `pwd`/GEOC/$ifg $SCRATCHDIR/$frame/GEOC/$ifg
   #else
   if [ $links == 0 ]; then
    cp -r GEOC/$ifg $SCRATCHDIR/$frame/GEOC/.; 
   fi
  elif [ -d IFG/$ifg ]; then
   if [ $links == 1 ]; then
    ln -s `pwd`/IFG/$ifg $SCRATCHDIR/$frame/IFG/$ifg;
   else
    cp -r IFG/$ifg $SCRATCHDIR/$frame/IFG/.;
   fi
  fi;
 done
 if [ $locl == 0 ]; then  # expecting geo ready
 #rglkstmp=`get_value SLC/$master/$master.slc.mli.par range_looks`
 #azlkstmp=`get_value SLC/$master/$master.slc.mli.par azimuth_looks`
 #if [ ! -z $rglkstmp ]; then orig_rlks=$rglkstmp; orig_azlks=$azlkstmp; fi
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
  echo "WARNING - NEED TO FIX THIS - JUST ADD OUTPUT RESOLUTION AND IT WILL WORK - PLEASE ASK EARMLA IF NEEDED"
  python -c "from LiCSAR_lib.coreg_lib import geocode_dem; geocode_dem('"$SCRATCHDIR/$frame/SLC/$master"','"$SCRATCHDIR/$frame/geo"','"$SCRATCHDIR/$frame/DEM"','"$SCRATCHDIR/$frame"','"$master"')"
  #echo "..generating custom multilooked hgt file"
  #ml_width=`grep range_samples SLC/$master/$master.slc.mli.par | gawk {'print $2'}`
  #demwidth=`grep width geo/EQA.dem_par | gawk {'print $2'}`
  #rm geo/$master.hgt
  #geocode geo/$master.lt_fine geo/EQA.dem $demwidth geo/$master.hgt $ml_width - 2 0 - - - - - >/dev/null 2>/dev/null
  #rashgt geo/$master.hgt SLC/$master/$master.slc.mli $ml_width
 fi
 else
  # check/copy GEOC/geo
  if [ -d GEOC/geo ]; then
   mkdir -p $SCRATCHDIR/$frame/GEOC
   cp -r GEOC/geo $SCRATCHDIR/$frame/GEOC/.
  fi
 fi
###############################################
#now we can start jobs..
 echo "running jobs"
 cd $SCRATCHDIR/$frame
 #weird error - mk_ifg is reading SLC tabs instead of rslc?? (need debug).. quick fix here:
 #for x in `ls tab/20??????_tab`; do cp `echo $x | sed 's/_tab/R_tab/'` $x; done

if [ $checkMosaic == 1 ]; then
#first run mosaicking
if [ `echo $waitTextmosaic | wc -w` -gt 0 ]; then
 waitcmdmosaic="-w \""$waitTextmosaic"\""
 echo "..running for missing mosaics"
 bsub2slurm.sh -q $bsubquery -n 1 -W 06:00 -J $frame"_mosaic" gapfill_job/mosaic.sh >/dev/null
 #bsub -q $bsubquery -n 1 -W 04:00 -J $frame"_mosaic" gapfill_job/mosaic.sh >/dev/null
else
 waitcmdmosaic='';
fi
fi

##adding sboi mosaiciking steps
if [ $dobovl == 1 ]; then
#first run mosaicking
 waitTextcreate_soi="ended('"$frame"_soi_00')"
 waitcmdcreate_soi="-w \""$waitTextcreate_soi"\""
 bsub2slurm.sh -q $bsubquery -n 1 -W 24:00 -M 16000 -J $frame"_soi_00" create_soi_00.py >/dev/null
else
 waitcmdcreate_soi='';
fi

#now we can start jobs..
echo "..running "$nojobs" jobs to generate ifgs/unws"
rm bjobs.sh 2>/dev/null
for job in `seq 1 $nojobs`; do
 wait=''
 if [ -f gapfill_job/ifgjob_$job.sh ]; then
  #weird error in 'job not found'.. workaround:
#  echo bsub -q $bsubquery -n $bsubncores -W 05:00 -J $frame'_ifg_'$job -e gapfill_job/ifgjob_$job.err -o gapfill_job/ifgjob_$job.out $waitcmdmosaic gapfill_job/ifgjob_$job.sh > tmptmp
  echo bsub2slurm.sh -q $bsubquery -n $bsubncores -W 05:00 -M 8192 -J $frame'_ifg_'$job -e gapfill_job/ifgjob_$job.err -o gapfill_job/ifgjob_$job.out $waitcmdmosaic gapfill_job/ifgjob_$job.sh >> bjobs.sh
  #this wait text would work for unwrapping to wait for the previous job:
  wait="-w \"ended('"$frame"_ifg_"$job"')\""
 fi
 if [ -f gapfill_job/unwjob_$job.sh ]; then
  #weird error in 'job not found'.. workaround:
#  echo bsub -q $bsubquery -n $bsubncores -W 08:00 -J $frame'_unw_'$job -e `pwd`/$frame'_unw_'$job.err -o `pwd`/$frame'_unw_'$job.out $wait gapfill_job/unwjob_$job.sh > tmptmp
  #echo bsub2slurm.sh -q $bsubquery -n 1 -W 12:00 -M 25000 -R "rusage[mem=25000]" -J $frame'_unw_'$job -e `pwd`/$frame'_unw_'$job.err -o `pwd`/$frame'_unw_'$job.out $wait gapfill_job/unwjob_$job.sh > tmptmp
  echo bsub2slurm.sh -q $bsubquery -n $bsubncores -W 08:00 -M 16000 -J $frame'_unw_'$job -e gapfill_job/$frame'_unw_'$job.err -o gapfill_job/$frame'_unw_'$job.out $wait gapfill_job/unwjob_$job.sh >> bjobs.sh
 fi
 if [ -f gapfill_job/bovljob_$job.sh ]; then
  echo bsub2slurm.sh -q $bsubquery -n 1 -W 08:00 -M 16000 -J $frame'_bovl_'$job -e gapfill_job/$frame'_bovl_'$job.err -o gapfill_job/$frame'_bovl_'$job.out $waitcmdcreate_soi gapfill_job/bovljob_$job.sh >> bjobs.sh
 fi
done
chmod 777 bjobs.sh
./bjobs.sh

# copying and cleaning job
echo "..running job that will copy outputs from TEMP to your WORKDIR"
waitcmd=''
if [ `echo $waitText | wc -w` -gt 0 ]; then
  waitText=`echo $waitText | cut -c 4-`
  waitcmd='-w "'$waitText'"'
fi
#echo "chmod -R 777 $SCRATCHDIR/$frame" > $WORKFRAMEDIR/gapfill_job/copyjob.sh
#if [ $links == 1 ]; then
# echo "mv -n $SCRATCHDIR/$frame/GEOC/* $WORKFRAMEDIR/GEOC/." >> $WORKFRAMEDIR/gapfill_job/copyjob.sh # for fully new ifgs
# echo "for x in \`ls $SCRATCHDIR/$frame/GEOC\`; do mv -n $SCRATCHDIR/$frame/GEOC/\$x/*.??? $WORKFRAMEDIR/GEOC/\$x/.; done" >> $WORKFRAMEDIR/gapfill_job/copyjob.sh
#else
if [ $links == 0 ]; then
 echo "rsync -r $SCRATCHDIR/$frame/GEOC $WORKFRAMEDIR" >> $WORKFRAMEDIR/gapfill_job/copyjob.sh
fi
echo "rsync -r $SCRATCHDIR/$frame/gapfill_job $WORKFRAMEDIR" >> $WORKFRAMEDIR/gapfill_job/copyjob.sh
echo "cd $WORKFRAMEDIR" >> $WORKFRAMEDIR/gapfill_job/copyjob.sh
#if [ $geocode == 1 ]; then
# echo "echo 'starting geocoding job'" >> $WORKFRAMEDIR/gapfill_job/copyjob.sh
# echo $WORKFRAMEDIR/framebatch_06_geotiffs.nowait.sh >> $WORKFRAMEDIR/gapfill_job/copyjob.sh
# echo "sleep 60" >> $WORKFRAMEDIR/gapfill_job/copyjob.sh
#fi
if [ $store == 1 ]; then
  echo "echo 'storing to LiCSAR base'" >> $WORKFRAMEDIR/gapfill_job/copyjob.sh
  echo "cd ..; store_to_curdir.sh $frame" >> $WORKFRAMEDIR/gapfill_job/copyjob.sh
fi
#echo "rsync -r $SCRATCHDIR/$frame/IFG $WORKFRAMEDIR" >> $WORKFRAMEDIR/gapfill_job/copyjob.sh
echo "echo 'sync done, deleting TEMP folder'" >> $WORKFRAMEDIR/gapfill_job/copyjob.sh
echo "rm -rf $SCRATCHDIR/$frame" >> $WORKFRAMEDIR/gapfill_job/copyjob.sh
if [ ! -z $shscript ]; then
  chmod 777 $shscript 2>/dev/null
  echo "sh "$shscript >> $WORKFRAMEDIR/gapfill_job/copyjob.sh
fi
echo "chmod -R 777 "$WORKFRAMEDIR >> $WORKFRAMEDIR/gapfill_job/copyjob.sh
chmod 777 $WORKFRAMEDIR/gapfill_job/copyjob.sh
#workaround for 'Empty job. Job not submitted'
echo bsub2slurm.sh -q $bsubquery -n 1 $waitcmd -W 08:00 -J $frame'_gapfill_out' -e $WORKFRAMEDIR/LOGS/framebatch_gapfill_postproc.err -o $WORKFRAMEDIR/LOGS/framebatch_gapfill_postproc.out $WORKFRAMEDIR/gapfill_job/copyjob.sh > $WORKFRAMEDIR/gapfill_job/tmptmp
#echo bsub -q $bsubquery -n 1 $waitcmd -W 08:00 -J $frame'_gapfill_out' -e $WORKFRAMEDIR/LOGS/framebatch_gapfill_postproc.err -o $WORKFRAMEDIR/LOGS/framebatch_gapfill_postproc.out $WORKFRAMEDIR/gapfill_job/copyjob.sh > $WORKFRAMEDIR/gapfill_job/tmptmp
#echo "debug last:"
#cat $WORKFRAMEDIR/gapfill_job/tmptmp
echo "starting copyjob - may take few minutes if the number of ifg jobs is large"
chmod 777 $WORKFRAMEDIR/gapfill_job/tmptmp; $WORKFRAMEDIR/gapfill_job/tmptmp
echo "changing permissions (so admins can store and delete the frame in work directory if needed)"
chmod -R 777 $WORKFRAMEDIR
#rm $WORKFRAMEDIR/gapfill_job/tmptmp
cd -
