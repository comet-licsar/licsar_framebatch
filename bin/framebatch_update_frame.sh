#!/bin/bash
#this variable will be used to choose whether to download from ASF or use NLA..
PROCESSING=1
#should we process till now or use safe 21 days delay ?
tillnow=0
#tolerance of days to either only autodownload or use nla + waiting
DAYSTOLERANCE=61
#DAYSTOLERANCE=961
#STORE_AND_DELETE=1
if [ -z $2 ]; then echo "parameters are frame and code (code is either upfill or backfill.. or gapfill)"; 
    echo "running with parameter -k means Keep the frame in BATCH_CACHE_DIR (not delete it)";
    echo "parameter -u would process upfilling till today"
    exit; fi

storeparam='-S -G'
while getopts ":kEu" option; do
 case "${option}" in
  k) storeparam=' ';
     ;;
  E) tillnow=1;
     storeparam='-S -E -G';
     ;;
  u) tillnow=1;
     ;;
 esac
done
#shift
shift $((OPTIND -1))

frame=$1
code=$2
#if [ ! -z $2 ]; then PROCESSING=0; fi
extra=''
maxwaithours=168
batchesdir='/gws/nopw/j04/nceo_geohazards_vol1/projects/LiCS/proc/current/batches'

#check for writing rights
touch pokuspokus_$frame
if [ ! -f pokuspokus_$frame ]; then echo "you do not have writing rights here, cancelling"; exit; fi
rm pokuspokus_$frame

track=`echo $frame | cut -c -3 | sed 's/^0//' | sed 's/^0//'`
#lastepoch=`ls $LiCSAR_public/$track/$frame/interferograms/2*_2* -d 2>/dev/null | tail -n1 | rev | cut -d '_' -f1 | rev`
lastepoch=`ls $LiCSAR_procdir/$track/$frame/RSLC 2>/dev/null | tail -n1 | cut -d '.' -f1`
lastepoch2=`ls $LiCSAR_procdir/$track/$frame/LUT 2>/dev/null | tail -n1 | cut -d '.' -f1`
if [ $lastepoch2 -gt $lastepoch 2>/dev/null ]; then lastepoch=$lastepoch2; fi

#firstepoch=`ls $LiCSAR_public/$track/$frame/interferograms/2*_2* -d 2>/dev/null | head -n1 | rev | cut -d '_' -f1 | rev`
firstepoch=`ls $LiCSAR_procdir/$track/$frame/RSLC 2>/dev/null | head -n1 | cut -d '.' -f1`
firstepoch2=`ls $LiCSAR_procdir/$track/$frame/LUT 2>/dev/null | head -n1 | cut -d '.' -f1`
if [ $firstepoch2 -lt $firstepoch 2>/dev/null ]; then firstepoch=$firstepoch2; fi

if [ -z $lastepoch ]; then
 echo "you are using script for updating frames for a new frame"
# echo "well.. trying to satisfy your needs, good luck anyway"
 lastepoch=`ls $LiCSAR_procdir/$track/$frame/SLC`
 firstepoch=$lastepoch
fi

#if [ ! -z $2 ]; then
# echo "You have provided second parameter - here it means PROCESS FROM BEGINNING TILL THE END"
#lastepoch='20141001'
#fi

if [ $code == "upfill" ]; then
 startdate=`date -d $lastepoch"-25 days" +%Y-%m-%d`
 if [ $tillnow -eq 1 ]; then
  enddate=`date -d "+1 days" +%Y-%m-%d`
 else
  enddate=`date -d "-21 days" +%Y-%m-%d`
 fi
 
elif [ $code == "backfill" ]; then
 startdate='2014-10-01'
 enddate=`date -d $firstepoch"+25 days" +%Y-%m-%d`

elif [ $code == "gapfill" ]; then
 if [ -z $4 ]; then echo "for gapfilling, provide start and end dates, e.g. 2017-05-08 2019-07-05"; exit; fi
 startdate=$3
 enddate=$4
 #so normally we would add 25 days to both date borders, unless there is 5th parameter (e.g. number 1)
 if [ -z $5 ]; then
  startdate=`date -d $3"-25 days" +%Y-%m-%d`
  enddate=`date -d $4"+25 days" +%Y-%m-%d`
 fi
 #nlamaxdate=$enddate
else
 echo "you have provided wrong code: "$code
 echo "currently working codes: upfill, backfill, in testing: gapfill"
 exit
fi

echo "first epoch: "$firstepoch
echo "last epoch: "$lastepoch

if [ ! -z $4 ]; then
 echo "for gapfilling: "
 echo "startdate = "$startdate
 echo "enddate = "$enddate
fi


#check if to start nla or just use autodownload
nla_start=0
nlamaxdate=`date -d "-89 days" +%Y-%m-%d`
nlamaxdateshort=`date -d "-89 days" +%Y%m%d`

if [ $code == "upfill" ]; then
 #in case of upfilling, we should request only files older than 3 months
 #this request will however include also files that are already processed..
 if [ $nlamaxdateshort -gt $lastepoch ]; then
  if [ `datediff $nlamaxdateshort $lastepoch` -gt $DAYSTOLERANCE ]; then
   nla_start=1
  fi
 fi
elif [ $code == "backfill" ]; then
 if [ `datediff 20141001 $firstepoch` -gt $DAYSTOLERANCE ]; then
  nla_start=1
  nlamaxdate=$enddate
 fi
elif [ $code == "gapfill" ]; then
 #assuming all gapfilling will be performed through nla requests..
 nla_start=1
 nlamaxdate=$enddate
fi


#check the time of the last epoch - use NLA or just download?
#if [ $nlamaxdateshort -gt $lastepoch ]; then
#  if [ `datediff $nlamaxdateshort $lastepoch` -gt $DAYSTOLERANCE ]; then
   #in this option we will do NLA first

if [ $nla_start == 1 ]; then
   echo "starting NLA request"
   LiCSAR_0_getFiles.py -f $frame -s $startdate -e $nlamaxdate -r > $batchesdir/temp/temp_nla.$frame
   if [ $PROCESSING -eq 0 ]; then
     echo "indicated NLA only - exiting";
     echo "you may start the processing itself manually using: "
     echo licsar_make_frame.sh -S -G -f $extra $frame 1 1 $startdate $enddate
     exit;
   fi
   #hourly checking of NLA requests status...
   if [ `grep -c "Created request" $batchesdir/temp/temp_nla.$frame` -gt 0 ]; then
    pom=0
    hours=0
    while [ $pom == 0 ]; do
      let hours=$hours+1
      echo "waiting for NLA to finish: "$hours" hours"
      sleep 3600
      pom=1
      for request in `grep "Created request" $batchesdir/temp/temp_nla.$frame | gawk {'print $3'}`; do
        if [ `nla.py req $request | grep Status | grep -c "On disk"` -eq 0 ];
          then pom=0
        fi
      done
      if [ $hours -gt $maxwaithours ]; then
           echo "enough waiting, NLA didnt work fully"
           pom=1
      fi
    done
    #
    extra=$extra" -c"
    autodown=0
   else
    echo "no data from this space and time are available on NLA"
    echo "will check on scihub/ASF"
    autodown=1
   fi
   rm $batchesdir/temp/temp_nla.$frame
   #after couple of hours, autodownload is not working. so setting to zero
else
   echo "autodownload will be used"
   autodown=1
fi

echo licsar_make_frame.sh $storeparam -f $extra $frame 1 $autodown $startdate $enddate
licsar_make_frame.sh $storeparam -f $extra $frame 1 $autodown $startdate $enddate

