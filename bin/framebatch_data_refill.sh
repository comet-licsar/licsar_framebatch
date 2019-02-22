#!/bin/bash
#procdir=$BATCH_CACHE_DIR
curdir=$LiCSAR_procdir
SLCdir=$LiCSAR_SLC

frame=$1
startdate=$2 #should be as 2014-10-10

if [[ ! `echo $frame | cut -d '_' -f3 | cut -c 6` == ?([0-9]) ]]; then echo 'frame wrongly set: '$frame; exit; fi
if [ ! -d $BATCH_CACHE_DIR/$frame ]; then echo 'this frame was not started by framebatch'; exit; fi
tr=`echo $frame | cut -c -3 | sed 's/^0//' | sed 's/^0//'`
dir=`echo $frame | cut -c 4`
if [ $dir == 'D' ]; then dir='dsc'; else dir='asc'; fi

cd $BATCH_CACHE_DIR/$frame
chmod -R 770 $BATCH_CACHE_DIR/$frame
if [ -z `ls $curdir/$tr/$frame/*xy` ]; then echo 'no polygonfile (.xy) generated. stopping'; exit; fi
xyfile=`ls $curdir/$tr/$frame/*xy | head -n1 | rev | cut -d '/' -f1 | rev`
cp $curdir/$tr/$frame/$xyfile .
chmod 770 $BATCH_CACHE_DIR/$frame/$xyfile
mv $xyfile ${frame}-poly.txt
make_simple_polygon.sh ${frame}-poly.txt

# to get list of files that are missing:
## make list from scihub
 echo "getting scihub data"
 query_sentinel.sh $tr $dir ${frame}.xy `echo $startdate | sed 's/-//g'` `date +'%Y%m%d'` >/dev/null 2>/dev/null
 echo "identified "`cat ${frame}_zipfile_names.list | wc -l`" images"
 echo "getting their expected CEMS path"
 zips2cemszips.sh ${frame}_zipfile_names.list ${frame}_scihub.list >/dev/null
 sort -o ${frame}_scihub.list ${frame}_scihub.list
## make list from nla
 echo "getting expected filelist from NLA (takes quite long - coffee break)"
 echo "*******"
 LiCSAR_0_getFiles.py -f $frame -s $startdate -e `date +'%Y-%m-%d'` -z ${frame}_db_query.list
 echo "*******"
 sort -o ${frame}_db_query.list ${frame}_db_query.list
 diff  ${frame}_scihub.list ${frame}_db_query.list | grep '^<' | cut -c 3- > ${frame}_todown
 echo "There are "`cat ${frame}_todown | wc -l`" extra images, not currently existing on CEMS disk"
# checking if the files from scihub exist in RSLC or SLC folders..
rm tmp_processed.txt 2>/dev/null
pom=0
for rslcdir in RSLC SLC $curdir/$tr/$frame/RSLC; do
 if [ -d $rslcdir ]; then
  echo "Previous processing exists. Checking"
  ls $rslcdir >> tmp_processed.txt
  pom=1
 fi
done
cp tmp_processed.txt tmp_tmp; sort -u tmp_tmp > tmp_processed.txt; rm tmp_tmp
echo "You have "`cat tmp_processed.txt | wc -l`" already processed images,"
 if [ $pom -eq 1 ]; then
  cp ${frame}_db_query.list tmp_dbquery.list
  for file in `cat tmp_dbquery.list`; do 
   filedate=`echo $file | rev | cut -d '/' -f1 | rev | cut -c 18-25`
   #if the filedate is in 'already processed and existing' files, then ignore it
   if [ `grep -c $filedate tmp_processed.txt` -gt 0 ]; then
    #echo "The image from "$filedate" has been already processed, ignoring."
    sed -i '/'$filedate'/d' ${frame}_db_query.list
    sed -i '/'$filedate'/d' ${frame}_todown
   fi
  done
  rm tmp_processed.txt tmp_dbquery.list
 fi
echo "this means you have now "`cat ${frame}_todown | wc -l`"images to download."
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
  echo "There are "$pom" images that are in NLA but not restored to /neodc"
  echo "Did you run NLA request already?? If not, cancel me and do it first"; sleep 5; 
  filetodown=`cat ${frame}_todown | wc -l`
  timetodown=`echo "$filetodown*4500/15/60/60" | bc`
  echo "ok, nevermind, continuing with "$filetodown" files to download";
  echo "please note that this can take approx. " $timetodown " hours to finish, hope you run it in tmux or screen????"
 fi
## check what really is existing on disk (maybe we missed something?)
 pom=0
 for file in `cat ${frame}_todown`; do 
   filename=`echo $file | rev | cut -d '/' -f1 | rev`
   if [ -f $file ]; then
     echo "A file that should be downloaded is actually existing in /neodc. It will be indexed to licsinfo instead."
     arch2DB.py -f $file >/dev/null 2>/dev/null
     pom=1;
     sed -i '/'$filename'/d' ${frame}_todown
   fi
   if [ -f $SLCdir/$filename ]; then
     echo "This file has already been downloaded"
     zipcheck=`7za l $SLCdir/$filename | grep ERROR -A1 | tail -n1`
     if [ `echo $zipcheck | wc -m` -gt 0 ]; then
       echo "..however it is broken:"
       ls -alh $SLCdir/$filename
       echo "zip error: "$zipcheck
       echo "so will be redownloaded"
       rm -rf $SLCdir/$filename
     else
       sed -i '/'$filename'/d' ${frame}_todown
       echo "..ingesting to database"
       arch2DB.py -f $SLCdir/$filename >/dev/null 2>/dev/null
       pom=1
     fi
   fi
 done
 if [ $pom -eq 1 ]; then echo "After the checks, there will be "`cat ${frame}_todown | wc -l`" files downloaded"; fi

## update what is not physically existing on disk 
## (we assume users did the nla request before and want to fill all the unavailable data
## update 21-02-2019: CEMS disallows secure connection
## doing workaround through xfer server (or login server if you do not have approved xfer service)
xferserver=jasmin-xfer1.ceda.ac.uk
#testing connection
ssh -q $xferserver exit
test_conn=$?
if [ $test_conn -eq 0 ]; then
 echo "will use XFER server to download data"
 sshout=$SLCdir
 sshserver=$xferserver
else
 echo "will use login server to download"
 echo "please apply for XFER service in JASMIN website"
 echo "(as a workaround, will use your home folder to download..will clean afterwards)"
 sshdown="ssh cems-login1.cems.rl.ac.uk"
 sshout=~/temp_licsar_down
 mkdir -p $sshout
 sshserver=cems-login1.cems.rl.ac.uk
 echo "please delete this files as temporary - they were created as workaround to data download. Normally they should be cleaned" > $sshout/README
fi
wgetcmd=`which wget_alaska`

#bash workaround to aliases
shopt -s expand_aliases
alias sshdown=`echo ssh -q $sshserver "'cd " $sshout "; export LiCSAR_configpath=$LiCSAR_configpath; $wgetcmd '"`

if [ `cat ${frame}_todown | wc -l` -gt 0 ]; then
 cd $SLCdir
 for x in `cat $BATCH_CACHE_DIR/$frame/${frame}_todown | rev | cut -d '/' -f1 | rev`; do
  echo "downloading file "$x" from alaska server"
  time sshdown $x >/dev/null 2>/dev/null
  if [ ! -f $sshout/$x ]; then
   echo "Some download error appeared, trying again (verbosed)"
   sshdown $x
  else
   zipcheck=`7za l $sshout/$x | grep ERROR -A1 | tail -n1`
   if [ `echo $zipcheck | wc -c` -gt 1 ]; then 
    echo "download error, trying once more (verbosed)"; sshdown $x;
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
   fi
   chmod 777 $SLCdir/$x 2>/dev/null
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
