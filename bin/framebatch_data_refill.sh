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
if [ -z `ls $curdir/$tr/$frame/*xy` ]; then echo 'no polygonfile (.xy) generated. stopping'; exit; fi
xyfile=`ls $curdir/$tr/$frame/*xy | head -n1 | rev | cut -d '/' -f1 | rev`
cp $curdir/$tr/$frame/$xyfile .
mv $xyfile ${frame}-poly.txt
make_simple_polygon.sh ${frame}-poly.txt

# to get list of files that are missing:
## make list from scihub
 echo "getting scihub data"
 query_sentinel.sh $tr $dir ${frame}.xy `echo $startdate | sed 's/-//g'` `date +'%Y%m%d'` >/dev/null 2>/dev/null
 echo "identified "`cat ${frame}_zipfile_names.list | wc -l`" extra images"
 echo "getting their expected CEMS path"
 zips2cemszips.sh ${frame}_zipfile_names.list ${frame}_scihub.list >/dev/null
 sort -o ${frame}_scihub.list ${frame}_scihub.list
## make list from nla
 echo "getting expected filelist from NLA (takes quite long)"
 LiCSAR_0_getFiles.py -f $frame -s $startdate -e `date +'%Y-%m-%d'` -z ${frame}_db_query.list
 sort -o ${frame}_db_query.list ${frame}_db_query.list
 diff  ${frame}_scihub.list ${frame}_db_query.list | grep '^<' | cut -c 3- > ${frame}_todown
 echo "There are "`cat ${frame}_todown | wc -l`" extra images from scihub queue"
# checking if the files from scihub exist in SLC or SLC folders..
 if [ -d RSLC ]; then
  echo "Previous processing exists. Preprocessed files will be removed from db_query files."
  ls RSLC > tmp_processed.txt
  ls SLC >> tmp_processed.txt
  cp ${frame}_db_query.list tmp_dbquery.list
  for file in `cat tmp_dbquery.list`; do 
   filedate=`echo $file | rev | cut -d '/' -f1 | rev | cut -c 18-25`
   if [ `grep -c $filedate tmp_processed.txt` -gt 0 ]; then
    echo "The image from "$filedate" has been already processed, ignoring."
    sed -i '/'$filedate'/d' ${frame}_db_query.list
    sed -i '/'$filedate'/d' ${frame}_todown
   fi
  done
  rm tmp_processed.txt tmp_dbquery.list
 fi
# checking if the NLA files exist. If not, include them for redownload
 pom=0
 for file in `cat ${frame}_db_query.list`; do 
   if [ ! -f $file ]; then
     echo "A file that should be restored from NLA is not existing and will be downloaded"; pom=1;
     echo $file >> ${frame}_todown
   fi
 done
 if [ $pom -eq 1 ]; then echo "Did you run NLA request already?? If not, cancel me and do it first"; sleep 5; 
  echo "ok, nevermind, continuing with "`cat ${frame}_todown | wc -l`" files to download";
 fi
## check what really is existing on disk
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
     if [ ! -z $zipcheck ]; then
       echo "..however it is broken:"
       ls -alh $SLCdir/$filename
       echo $zipcheck
       echo "so will be redownloaded"
       rm -rf $SLCdir/$filename
     else
       sed -i '/'$filename'/d' ${frame}_todown
       pom=1
     fi
   fi
 done
 if [ $pom -eq 1 ]; then echo "After the checks, there will be "`cat ${frame}_todown | wc -l`" files downloaded"; fi

## update what is not physically existing on disk 
## (we assume users did the nla request before and want to fill all the unavailable data
if [ `cat ${frame}_todown | wc -l` -gt 0 ]; then
 cd $SLCdir
 for x in `cat $BATCH_CACHE_DIR/$frame/${frame}_todown | rev | cut -d '/' -f1 | rev`; do
  echo "downloading file "$x" from alaska server"
  wget_alaska.sh $x >/dev/null 2>/dev/null
  if [ ! -f $x ]; then
   echo "Some download error appeared, trying again (verbosed)"
   wget_alaska.sh $x
  else
   zipcheck=`7za l $x | grep ERROR -A1 | tail -n1`
   if [ `echo $zipcheck | wc -c` -gt 1 ]; then echo "download error, trying once more (verbosed)"; wget_alaska.sh $x; fi
   zipcheck=`7za l $x | grep ERROR -A1 | tail -n1`
   if [ `echo $zipcheck | wc -c` -gt 1 ]; then
    echo "The downloaded file is corrupted:"
    ls -alh $x
    echo $zipcheck
    echo "...removing it (sorry)"
    rm -rf $x
    echo $x >> $BATCH_CACHE_DIR/$frame/${frame}_download_errors
   else
    echo "..downloaded correctly, ingesting to database"
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
