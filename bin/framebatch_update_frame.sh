#!/bin/bash
#this variable will be used to choose whether to download from ASF or use NLA..
PROCESSING=1
DAYSTOLERANCE=61
frame=$1
if [ -z $1 ]; then echo "parameter is frame"; exit; fi
if [ ! -z $2 ]; then PROCESSING=0; fi
extra=''

track=`echo $frame | cut -c -3 | sed 's/^0//' | sed 's/^0//'`
lastepoch=`ls $LiCSAR_public/$track/$frame/products/2*_2* -d | tail -n1 | rev | cut -d '_' -f1 | rev`
if [ ! -z $2 ]; then
 echo "You have provided second parameter - here it means PROCESS FROM BEGINNING TILL THE END"
 lastepoch='20141001'
fi
startdate=`date -d $lastepoch"-25 days" +%Y-%m-%d`
enddate=`date -d "-21 days" +%Y-%m-%d`

#this request will however include also files that are already processed.. but now I do not have code to use LUT (so far)
nlamaxdate=`date -d "-89 days" +%Y-%m-%d`
nlamaxdateshort=`date -d "-89 days" +%Y%m%d`

echo "last epoch: "$lastepoch

#check the time of the last epoch - use NLA or just download?
if [ $nlamaxdateshort -gt $lastepoch ]; then
  if [ `datediff $nlamaxdateshort $lastepoch` -gt $DAYSTOLERANCE ]; then
   #in this option we will do NLA first
   echo "starting NLA request"
   LiCSAR_0_getFiles.py -f $frame -s $startdate -e $nlamaxdate -r > temp_nla.$frame
   if [ $PROCESSING -eq 0 ]; then 
     echo "indicated NLA only - exiting";
     echo "you may start the processing itself manually using: "
     echo licsar_make_frame.sh -S $extra $frame 1 1 $startdate $enddate
     exit;
   fi
   #this should be exchanged to proper checking of NLA requests status...
   if [ `grep -c "Created request" temp_nla.$frame` -gt 0 ]; then
    #now just sleeping for 24 hours
    #echo "sleeping for 24 hours to wait for NLA requests to finish"
    #sleep 86400
    #
    pom=0
    hours=0
    while [ $pom == 0 ]; do
      let hours=$hours+1
      echo "waiting for NLA to finish: "$hours" hours"
      sleep 3600
      pom=1
      for request in `grep "Created request" temp_nla.$frame | gawk {'print $3'}`; do
        if [ `nla.py req $request | grep Status | grep -c "On disk"` -eq 0 ];
          then pom=0
        fi
      done
      if [ $hours -gt 50 ]; then
           echo "enough waiting, NLA didnt work fully"
           pom=1
      fi
    done
    #
    extra="-c"
    autodown=0
   else
    echo "no data from this space and time are available on NLA"
    echo "will check on scihub/ASF"
    autodown=1
   fi
   rm temp_nla.$frame
   #after couple of hours, autodownload is not working. so setting to zero
  fi
else
   echo "autodownload will be used"
   autodown=1
fi

licsar_make_frame.sh -S $extra $frame 1 $autodown $startdate $enddate

