#!/bin/bash
#procdir=$BATCH_CACHE_DIR
curdir=$LiCSAR_procdir

if [ -d $XFCPATH/SLC ]; then
  SLCdir=$XFCPATH/SLC
else
  SLCdir=$LiCSAR_SLC
fi

#if [ $USER == 'earmla' ]; then
#  #echo "WARNING, data write errors in xfc - using vol2 instead"
#  SLCdir=/work/xfc/vol5/user_cache/earmla/SLC
#  if [ ! -d $SLCdir ]; then
#    SLCdir=$LiCSAR_SLC
#  fi
#fi
#             if os.environ['USER'] == 'earmla':
#                outdir = '/work/xfc/vol5/user_cache/earmla/SLC'
echo "will download to "$SLCdir

USE_SSH_DOWN=1 #if the wget error is related to SSL blocking, set this to 1 -- however JASMIN prefers to have it always =1 (to use xfer servers for download)
use_cdse=0 #being used only for the latest data... like.. the current or previous day
trycdse=1 # back on by default now
CHECKONLY=0
MAXIMAGES=100 # if more images are requested to download, stop it
NOCHECKMAX=0

if [ -z $2 ]; then
 echo "Parameters are: FRAME STARTDATE [ENDDATE]"
 echo "e.g. 007D_05286_131310 2014-10-10"
 echo "optional parameter -c: will do only check if data are ingested in licsar db"
 echo "optional parameter -A: will not check for max number of images to download: max number is "$MAXIMAGES
 echo "optional temporary parameter -f: will try CDSE when needed. By default use only ASF since CDSE was ultra slow"
 exit
fi


while getopts ":cAf" option; do
 case "${option}" in
  c ) CHECKONLY=1;
      echo "Checking if files are properly ingested to licsar database";
      shift
      ;;
  A ) NOCHECKMAX=1;
      echo "overriding check for max images";
      shift
      ;;
  f ) trycdse=1;
      use_cdse=1;
      echo "overriding CDSE blocker. Download might take long";
      shift
      ;;
esac
done


frame=$1
startdate=$2 #should be as 2014-10-10

#if [ `grep -c '-' $2 |..... ]; then .....; fi
#this is to use scihub to download only the today's and yesterday's data
if [ ! -z $3 ]; then 
 enddate=$3;
 #if [ `date -d $enddate +'%Y%m%d'` -gt `date +'%Y%m%d'` ]; then enddate=`date +'%Y-%m-%d'`; fi
 if [ $enddate == `date +'%Y-%m-%d'` ] || [ `date -d $enddate +'%Y%m%d'` -gt `date +'%Y%m%d'` ] || [ $enddate == `date -d 'tomorrow' +'%Y-%m-%d'` ] || [ $enddate == `date -d 'yesterday' +'%Y-%m-%d'` ]; then
  if [ $trycdse == 1 ]; then
    if [ -f ~/.cdse_credentials ]; then use_cdse=1; echo "using CDSE"; fi
  else
    echo "WARNING - issues with CDSE download speed - not using CDSE but WE SHOULD HERE. Temporary solution. To force CDSE, rerun framebatch_data_refill.sh with -f"
  fi
 fi
else
 enddate=`date -d 'tomorrow' +'%Y-%m-%d'`;
fi

if [[ ! `echo $frame | cut -d '_' -f3 | cut -c 6` == ?([0-9]) ]]; then echo 'frame wrongly set: '$frame; exit; fi
if [ ! -d $BATCH_CACHE_DIR/$frame ]; then echo 'this frame was not started by framebatch. I suppose you know what you are doing'; mkdir $BATCH_CACHE_DIR/$frame; fi
tr=`echo $frame | cut -c -3 | sed 's/^0//' | sed 's/^0//'`
dir=`echo $frame | cut -c 4`
if [ $dir == 'D' ]; then dir='dsc'; else dir='asc'; fi
mode='IW'
if [ `echo $frame | cut -d '_' -f2` == 'SM' ]; then mode='SM'; fi

cd $BATCH_CACHE_DIR/$frame
chmod 777 $BATCH_CACHE_DIR/$frame 2>/dev/null
chmod 777 $BATCH_CACHE_DIR/$frame/* 2>/dev/null
if [ -z `ls $curdir/$tr/$frame/*xy` ]; then 
  echo 'no polygonfile (.xy) generated. probably not needed anyway';
else   # probably not needed anymore
 xyfile=`ls $curdir/$tr/$frame/*xy | head -n1 | rev | cut -d '/' -f1 | rev`
 cp $curdir/$tr/$frame/$xyfile .
 chmod 777 $BATCH_CACHE_DIR/$frame/$xyfile 2>/dev/null
 mv $xyfile ${frame}-poly.txt
 make_simple_polygon.sh ${frame}-poly.txt
fi

# to get list of files that are missing:
rm ${frame}_zipfile_names.list ${frame}_scihub.list ${frame}_todown missingFiles 2>/dev/null
# to clean from previous request
rm ${frame}_db_query.list s1_search.py 2>/dev/null

# 2023/11: CDSE change -> will not use query_sentinel.sh anymore
if [ $use_cdse -eq 1 ]; then
 flagasf='False'
 echo 'getting CDSE data'
else
 flagasf='True'
 echo 'getting ASF data'
fi

## make list from scihub
# echo "getting scihub data"
# if [ ! -z $enddate ]; then
#   #the way of query_sentinel.sh misses the latest data (so increasing enddate by 1 day to the future)
#   enddate_str=`echo $enddate | sed 's/-//g'`
#   query_sentinel.sh $tr $dir ${frame}.xy `echo $startdate | sed 's/-//g'` `date -d $enddate_str'+1day' +'%Y%m%d'` $mode >/dev/null 2>/dev/null
#  else
#   query_sentinel.sh $tr $dir ${frame}.xy `echo $startdate | sed 's/-//g'` `date -d 'tomorrow' +'%Y%m%d'` $mode >/dev/null 2>/dev/null
# fi
# echo "identified "`cat ${frame}_zipfile_names.list | wc -l`" images"
# echo "getting their expected CEMS path"
# zips2cemszips.sh ${frame}_zipfile_names.list ${frame}_scihub.list >/dev/null

#else
# 2023: ok, ASF OFTEN changes the filenames, i.e. scihub vs ASF differs (last 4 letters)
# found by Pedro, fixed by Milan.. we really should fully rearrange all those historic shell scripts
#echo 'getting ASF data'
#
startdate_str=`echo $startdate | sed 's/-//g'`
enddate_str=`echo $enddate | sed 's/-//g'`
echo "DEBUG 202507: it appears search_alaska does not return S1C data - using CDSE temporarily only to search for filenames"
cat << EOF > s1_search.py
from s1data import *
a=get_images_for_frame('$frame', '$startdate_str', '$enddate_str', sensType='$mode', asf = False); # $flagasf);
a=get_neodc_path_images(a);
for b in a:
    print(b)
EOF
python3 s1_search.py | grep neodc > ${frame}_scihub.list


 sort -o ${frame}_scihub2.list ${frame}_scihub.list
 mv ${frame}_scihub2.list ${frame}_scihub.list

 echo "double-checking for correct database entries (there were issues in 2025)"
 python3 -c "import framecare as fc; fc.check_reingest_filelist('"$frame'_scihub.list'"')"

## make list from nla
rm ${frame}_db_query.list 2>/dev/null
touch ${frame}_db_query.list 2>/dev/null
#if [ ! -f ${frame}_db_query.list ]; then
 echo "getting expected filelist from NLA (takes quite long - coffee break)"
 echo "*******"
 if [ ! -z $enddate ]; then
   LiCSAR_0_getFiles.py -f $frame -s $startdate -e $enddate -z ${frame}_db_query.list
  else
   LiCSAR_0_getFiles.py -f $frame -s $startdate -e `date +'%Y-%m-%d'` -z ${frame}_db_query.list
 fi
 echo "*******"
#fi
 sort -o ${frame}_db_query2.list ${frame}_db_query.list
 mv ${frame}_db_query2.list ${frame}_db_query.list
 diff  ${frame}_scihub.list ${frame}_db_query.list | grep '^<' | cut -c 3- > ${frame}_todown
 echo "There are "`cat ${frame}_todown | wc -l`" extra images, not currently existing on CEMS (neodc) disk"
# checking if the files from scihub exist in RSLC or SLC folders..
rm tmp_processed.txt 2>/dev/null
rm tmp_existing.txt 2>/dev/null
pom=0
for rslcdir in RSLC SLC $curdir/$tr/$frame/RSLC; do
 if [ -d $rslcdir ]; then
  #echo "Previous processing exists. Checking"
  ls $rslcdir >> tmp_existing.txt
  for rslcdatedir in `ls -d $rslcdir/20??????`; do
   if [ `ls $rslcdatedir/*slc 2>/dev/null | wc -l` -gt 0 ]; then
    echo $rslcdatedir | rev | cut -d '/' -f1 | rev >> tmp_processed.txt
   fi
  done
  pom=1
 fi
done
if [ $pom -eq 1 ]; then
 cp tmp_processed.txt tmp_tmp; sort -u tmp_tmp > tmp_processed.txt; rm tmp_tmp
 cp tmp_existing.txt tmp_tmp; sort -u tmp_tmp > tmp_existing.txt; rm tmp_tmp
 if [ -d geo ]; then
  master=`ls geo/20??????.hgt | cut -d '/' -f2 | cut -d '.' -f1`
  sed -i '/'$master'/d' tmp_existing.txt
  sed -i '/'$master'/d' tmp_processed.txt
 fi
 echo "You have "`cat tmp_existing.txt | wc -l`" already processed images,"
 if [ `cat tmp_existing.txt | wc -l` -gt `cat tmp_processed.txt | wc -l` ]; then
  echo "the RSLCs are physically existing for "`cat tmp_processed.txt | wc -l`" of them"
  echo "(data will be downloaded only for those non-existing ones)"
  #do you like the existing X processed paradox?
  #check this then, you will like it too: https://www.youtube.com/watch?v=2uHNSuGeTpM
 fi
fi
 if [ $pom -eq 1 ]; then
  cp ${frame}_db_query.list tmp_dbquery.list
  # i know i should do it opposite, but it works anyway..
  for file in `cat tmp_dbquery.list`; do 
   filedate=`echo $file | rev | cut -d '/' -f1 | rev | cut -c 18-25`
   #if the filedate is in 'already processed and existing' files, then ignore it
   if [ `grep -c $filedate tmp_processed.txt` -gt 0 ]; then
    #echo "The image from "$filedate" has been already processed, ignoring."
    sed -i '/'$filedate'/d' ${frame}_db_query.list
    sed -i '/'$filedate'/d' ${frame}_todown
   fi
  done
  rm tmp_processed.txt tmp_dbquery.list tmp_existing.txt 2>/dev/null
 fi
 echo "This means you have now "`cat ${frame}_todown | wc -l`" images to download."
 echo "Checking if the NLA-registered files exist on the disk. If not, include them for redownload"
 pom=0
 for file in `cat ${frame}_db_query.list`; do 
   if [ ! -f $file ]; then
     #echo "A file that should be restored from NLA is not existing and will be downloaded"; 
     let pom=$pom+1;
     echo $file >> ${frame}_todown
   fi
 done
 if [ $pom -gt 0 ]; then
  echo "There are "$pom" images that are indexed in licsinfo database but not existing on disk"
  echo "Did you run NLA request already?? If not, cancel me and do it first"; sleep 5; 
 fi
## check what really is existing on disk (maybe we missed something?)
 pom=0
 for file in `cat ${frame}_todown`; do 
   filename=`echo $file | rev | cut -d '/' -f1 | rev`
   if [ -f $file ]; then
     echo "A file "$filename" is actually existing in /neodc. It will be indexed to licsinfo instead of downloading."
     arch2DB.py -f $file >/dev/null 2>/dev/null
     pom=1;
     sed -i '/'$filename'/d' ${frame}_todown
   else
    if [ -f $SLCdir/$filename ]; then
     echo "The file "$filename" has already been downloaded"
     zipcheck=`7za l $SLCdir/$filename 2> tmp_zipcheck | grep Error | tail -n1`
     if [ `echo $zipcheck | wc -m` -gt 1 ]; then
       echo "..however it is broken:"
       ls -alh $SLCdir/$filename
       echo "zip error: "
       echo "----------"
       cat tmp_zipcheck
       echo "----------"
       rm tmp_zipcheck
       echo "so it will be redownloaded"
       rm -rf $SLCdir/$filename
     else
       sed -i '/'$filename'/d' ${frame}_todown
       if [ `grep -c $SLCdir/$filename ${frame}_db_query.list` -eq 0 ]; then
        echo "..ingesting to database"
        arch2DB.py -f $SLCdir/$filename >/dev/null 2>/dev/null
       fi
       sed -i '/'$filename'/d' ${frame}_todown
       pom=1
     fi
    fi
   fi
 done
 filestodown=`cat ${frame}_todown | wc -l`
 if [ $filestodown -eq 0 ]; then echo "Congratulations, seems there is nothing more to download. Exiting";exit; fi

if [ $CHECKONLY -eq 1 ]; then echo "files checked, exiting without downloading"; exit; fi

 echo "After the checks, there will be "$filestodown" files downloaded";

## update what is not physically existing on disk 
## (we assume users did the nla request before and want to fill all the unavailable data
## update 21-02-2019: CEMS disallows secure connection
## doing workaround through xfer server (or login server if you do not have approved xfer service)
## update 08-03-2019: it seems it was something temporary in CEMS. It works again
## returning back to the direct download......this is real headache
## update 03-07-2019: we SHOULD use xfer servers... and actually xfer3 (if the user has xfer services approved)
## reoptimizing the code and using ssh -A way to connect to the xfer3 - hope all users use this way of connection...
 #bash workaround to aliases
shopt -s expand_aliases
sshout=$SLCdir
wgetcmd_scihub=''
if [ $USE_SSH_DOWN -eq 1 ]; then
 #xferserver=jasmin-xfer1.ceda.ac.uk
 xferserver=xfer-vm-01.jasmin.ac.uk
 #testing connection
 #if [ `grep -c licsar@gmail.com ~/.ssh/authorized_keys` -eq 0 ]; then
 # cat $LiCSAR_configpath/.id_rsa_licsar.pub >> ~/.ssh/authorized_keys
 #fi
 #alias sshinst="if [ \`grep -c licsar@gmail.com ~/.ssh/authorized_keys\` -eq 0 ]; then cat \$LiCSAR_configpath/.id_rsa_licsar.pub >> ~/.ssh/authorized_keys; fi"
 #sshinst 2>/dev/null
 #ssh -q -i $LiCSAR_configpath/.id_rsa_licsar -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $xferserver exit
 test_conn=`ssh -q -A -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $xferserver "echo 1"`
 if [ ! -z $test_conn ] && [ $test_conn -eq 1 ]; then
  echo "will use XFER-01 server to download data"
#  sshout=$SLCdir
#  sshparams="-q -i $LiCSAR_configpath/.id_rsa_licsar -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
  sshparams="-q -A -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
  sshserver=$xferserver
  #xfer3 is without access to /gws/smf/... - doing workaround
  cp `which wget_alaska` ~/.wget_alaska
  wgetcmd="~/.wget_alaska"
  downspeed=14 #MB/s
  #making it ready also through scihub:
  if [ $use_cdse -eq 1 ]; then
   #seems only xfer3 cannot access smf disk..
   #cp `which wget_scihub` ~/.wget_scihub
   #wgetcmd_scihub="~/.wget_scihub"
   #sshserver_scihub=jasmin-xfer2.ceda.ac.uk
   sshserver_scihub=xfer-vm-01.jasmin.ac.uk
   #wgetcmd_scihub=`which wget_scihub`  # 2023 - change from scihub
   wgetcmd_scihub=`which wget_cdse`
  fi
 else
  #echo "You do not have access to (fast) XFER3 server, please request hpxfer service via CEDA web portal"
  if [ `hostname` == 'host293.jc.rl.ac.uk' ]; then
    echo "(users noticed that XFER3 connection does not work from cems-sci2.. you may try another server)"
  fi
  #echo "now we will use a slower solution"
  echo "no connection to "$xferserver". trying other one"
  xferserver=xfer-vm-02.jasmin.ac.uk
  test_conn=`ssh -q -A -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no $xferserver "echo 1"`
  if [ ! -z $test_conn ] && [ $test_conn -eq 1 ]; then
   #echo "will use XFER1 server to download data"
   sshparams="-q -A -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
   sshserver=$xferserver
   wgetcmd=`which wget_alaska`
   downspeed=2 #MB/s
   if [ $use_cdse -eq 1 ]; then
    #cp `which wget_scihub` ~/.wget_scihub
    sshserver_scihub=$sshserver
    #wgetcmd_scihub=`which wget_scihub`
    wgetcmd_scihub=`which wget_cdse`
   fi
  else
   echo "no xfer server is available.. .downloading directly from this node - THIS IS NOT PROPER WAY"
   USE_SSH_DOWN=0
   #echo "will use login server to download"
   #echo "please apply for hpxfer service in JASMIN website"
   #echo "(as a workaround, will use your home folder to download..will clean afterwards)"
   #sshdown="ssh cems-login1.cems.rl.ac.uk"
   #sshout=~/temp_licsar_down
   #mkdir -p $sshout
   #downspeed=2 #MB/s
   #cp `which wget_alaska` $sshout/.
   #wgetcmd=`$sshout/wget_alaska`
   #sshparams="-q -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
   #sshserver=cems-login1.cems.rl.ac.uk
   #if [ $use_scihub -eq 1 ]; then
   # cp `which wget_scihub` $sshout/.
   # sshserver_scihub=$sshserver
   # wgetcmd_scihub=`$sshout/wget_scihub`
   #fi
   #echo "please delete this files as temporary - they were created as workaround to data download. Normally they should be cleaned" > $sshout/README
  fi
 fi
 alias sshdown=`echo ssh $sshparams $sshserver "'cd "$sshout"; export LiCSAR_configpath=$LiCSAR_configpath; $wgetcmd '"`
 if [ $use_cdse -eq 1 ]; then
  alias sshdown_scihub=`echo ssh $sshparams $sshserver_scihub "'cd "$sshout"; export LiCSAR_configpath=$LiCSAR_configpath; $wgetcmd_scihub '"`
 fi
fi

if [ $USE_SSH_DOWN -eq 0 ]; then
 if [ $use_cdse -eq 1 ]; then
  downit() { cd "$sshout"; wget_cdse "$1"; cd -; }
 else
  downit() { cd "$sshout"; wget_alaska "$1"; cd -; }
 fi
 alias sshdown=downit
 alias sshdown_scihub=downit
fi

 timetodown=`echo "$filestodown*4500/$downspeed/60/60" | bc`
 echo "please note that the download can take approx. " $timetodown " hours to finish, you may want to run this in tmux or screen??"
 echo "(press CTRL-C if you want to cancel.. waiting 5 sec)"
 sleep 5

if [ `cat ${frame}_todown | wc -l` -gt 0 ]; then
 if [ $NOCHECKMAX -eq 0 ]; then
   if [ `cat ${frame}_todown | wc -l` -gt $MAXIMAGES ]; then
     echo "Whoops - the requested amount of images is over the threshold. Will cancel the processing"
     exit
   fi
 fi
 cd $SLCdir
 count=0
 for x in `cat $BATCH_CACHE_DIR/$frame/${frame}_todown | rev | cut -d '/' -f1 | rev`; do
  let count=$count+1
  echo "checking last time if the file does not exist in neodc"
  y=`echo $x | cut -c 18-21`
  m=`echo $x | cut -c 22-23`
  d=`echo $x | cut -c 24-25`
  pom_to=''
  pom_to=`ls /neodc/sentinel1?/data/IW/L1_SLC/*/$y/$m/$d/$x 2>/dev/null`
  if [ ! -z $pom_to ]; then
   echo "it is so - the file appeared on neodc, will update the licsinfo_db"
   if [ `arch2DB.py -f $pom_to | grep -c ERROR` -gt 0 ]; then pom_to=''; echo "but it is erroneous, so will redownload it"; fi
  fi
  if [ -z $pom_to ]; then
   echo "downloading file "$x #" from alaska server"
   echo "( it is file no. "$count" from "$filestodown" )"
   scihub_pom=0
   if [ `echo $x | cut -c 18-25` -ge `date -d 'yesterday' +'%Y%m%d'` ]; then
    echo "( it is latest date, will check for RESORBs and download them )"
    update_resorb_for_slc.sh $x
   fi
   #if [ `echo $x | cut -c 18-25` -ge `date -d 'yesterday' +'%Y%m%d'` ] &&
   if [ $use_cdse -eq 1 ]; then
    echo "trying from ASF first"
    time sshdown $x >/dev/null 2>/dev/null
    sshdown $x >/dev/null 2>/dev/null
    if [ ! -f $sshout/$x ]; then
      echo "none from ASF, proceeding with (slower) CDSE"
      scihub_pom=1
      time sshdown_scihub $x >/dev/null 2>/dev/null
      if [ ! -f $sshout/$x ]; then
        sshdown_scihub $x >/dev/null 2>/dev/null
      fi
    fi
   else
    #sshinst 2>/dev/null;
    time sshdown $x >/dev/null 2>/dev/null
    #just to check it by wget itself..
    #sshinst;
    sshdown $x >/dev/null 2>/dev/null
   fi
   if [ ! -f $sshout/$x ]; then
    echo "Some download error appeared, trying again (verbosed)"
    #sshinst;
    if [ $scihub_pom -eq 1 ]; then
     sshdown_scihub $x
    else
     sshdown $x
    fi
   else
    zipcheck=`7za l $sshout/$x | grep ERROR -A1 | tail -n1`
    if [ `echo $zipcheck | wc -c` -gt 1 ]; then 
     echo "download error, trying once more (verbosed)"
     #sshinst;
     sshdown $x;
    fi
    zipcheck=`7za l $sshout/$x | grep ERROR -A1 | tail -n1`
    if [ `echo $zipcheck | wc -c` -gt 1 ]; then
     echo "The downloaded file is corrupted:"
     ls -alh $sshout/$x
     echo $zipcheck
     echo "...removing it (sorry)"
     rm -rf $sshout/$x
     echo $x >> $BATCH_CACHE_DIR/$frame/${frame}_download_errors
    else
     echo "..downloaded correctly, ingesting to database"
     if [ $sshout != $SLCdir ]; then echo "(first moving downloaded file from "$sshout" to "$SLCdir" )"; mv $sshout/$x $SLCdir/.; fi
     arch2DB.py -f $SLCdir/$x >/dev/null 2>/dev/null
     touch $SLCdir/$x
    fi
    chmod 777 $SLCdir/$x 2>/dev/null
   fi
  fi
 done
fi

cd $BATCH_CACHE_DIR/$frame
echo "Data gap filling done"
if [ -f ${frame}_download_errors ]; then
 echo "..but there were errors in getting following files:"
 cat ${frame}_download_errors
fi

#note that licsar_clean will (weekly) remove files older than... a week.. from this folder
