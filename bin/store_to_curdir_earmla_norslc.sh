#!/bin/bash
#curdir=/gws/nopw/j04/nceo_geohazards_vol1/projects/LiCS/proc/current
curdir=$LiCSAR_procdir
public=$LiCSAR_public
if [ -z $1 ]; then echo "Parameter: *_*_* frame folder.. MUST BE IN THIS FOLDER"; exit;
 else frame=`basename $1`; fi

if [ ! -d $frame ]; then echo "wrong framedir - you should be in the \$BATCH_CACHE_DIR, sorry"; exit; fi
if [ $USER != 'earmla' ]; then echo "you are not admin. Not storing anything."; exit; fi

MOVE=0
DORSLC=1
DOGEOC=1
DOIFG=1
DELETEAFTER=0
if [ ! -z $2 ]; then if [ $2 -eq 1 ]; then DELETEAFTER=1; echo "setting to delete"; fi; fi

#for thisDir in /gws/nopw/j04/nceo_geohazards_vol2/LiCS/temp/volc /gws/nopw/j04/nceo_geohazards_vol2/LiCS/temp/volc/frames; do
#cd $thisDir
#for frame in `ls [0-9]*_?????_?????? -d`; do
cd $frame
cd ..
thisDir=`pwd`
 tr=`echo $frame | cut -d '_' -f1 | sed 's/^0//' | sed 's/^0//' | rev | cut -c 2- | rev`
 frameDir=$curdir/$tr/$frame
 if [ $DORSLC -eq 1 ]; then
 #move rslcs
 if [ -d $frame/RSLC ]; then
  mkdir -p $frameDir/RSLC
  for date in `ls $frame/RSLC/20?????? -d | cut -d '/' -f3`; do
   # if it is not master
   if [ ! -d $frameDir/SLC/$date ]; then
    if [ $MOVE -eq 1 ]; then rm $frame/RSLC/$date/$date.rslc 2>/dev/null; fi
    # if there are 'some' rslc files
    if [ -f $frame/RSLC/$date/$date.IW2.rslc ]; then
     echo "checking "$frame"/"$date
     #if it already doesn't exist in current dir
     if [ ! -d $frameDir/RSLC/$date ] && [ ! -f $frameDir/RSLC/$date.7z ]; then
      cd $frame/RSLC
      #cleaning the folder
      if [ `ls $date/*.lt 2>/dev/null | wc -w` -gt 0 ]; then
       mkdir -p $frameDir/LUT
       rm -f $date/*.lt.orbitonly 2>/dev/null
       echo "compressing LUT of "$date
       7za a -mx=1 $frameDir/LUT/$date.7z $date/*.lt >/dev/null 2>/dev/null
       rm -f $date/*.lt
      fi
      #echo "compressing RSLC from "$date
      echo "the RSLC will not get compressed anymore"
      #time 7za a -mx=1 '-xr!*.lt' $frameDir/RSLC/$date.7z $date >/dev/null 2>/dev/null
      if [ $MOVE -eq 1 ]; then rm -r $date; fi
      cd $thisDir
     fi
    fi
   fi
  done
 fi
 fi

if [ $DOIFG -eq 1 ]; then
 #move ifgs (if unwrapped is also done)
 if [ -d $frame/IFG ]; then
  for dates in `ls $frame/IFG/20??????_20?????? -d | cut -d '/' -f3`; do
   if [ -f $frame/IFG/$dates/$dates.unw ]; then
       if [ ! -d $frameDir/IFG/$dates ]; then
        mkdir -p $frameDir/IFG/$dates
        echo "moving (or copying) ifg "$dates
        for ext in cc diff filt.cc filt.diff off unw; do
        if [ $MOVE -eq 1 ]; then 
         mv $frame/IFG/$dates/$dates.$ext $frameDir/IFG/$dates/.
         else
         cp $frame/IFG/$dates/$dates.$ext $frameDir/IFG/$dates/.
         fi
        done
       fi
#   else
       #this is a quick fix if the geocoding was not performed, then i want to copy ifgs back
#       if [ -d $frameDir/IFG/$dates ]; then
#         echo "Copying ifg "$dates" back from current database"
#         cp $frameDir/IFG/$dates/* $frame/IFG/$dates/.
#       fi
   fi
  done
 fi
fi

 echo "Stored "$frame" on "`date +'%Y-%m-%d'`>> $thisDir/stored_to_curdir.txt
 #move tabs and logs
 if [ -d $frame/tab ]; then
  echo "copying new tabs and logs"
  for tab in `ls $frame/tab`; do
   if [ ! -f $frameDir/tab/$tab ]; then
    cp $frame/tab/$tab $frameDir/tab/.
   fi
  done
  for log in `ls $frame/log`; do
   if [ ! -f $frameDir/log/$log ]; then
    cp $frame/log/$log $frameDir/log/.
   fi
  done
 fi


if [ $DOGEOC -eq 1 ]; then
 #move geoc
 if [ -d $frame/GEOC ]; then
  echo "Moving geoifgs to public folder for frame "$frame
  track=$tr
  for geoifg in `ls $frame/GEOC/2*_2* -d | rev | cut -d '/' -f1 | rev`; do
   if [ -f $frame/GEOC/$geoifg/$geoifg.geo.unw.bmp ]; then
    if [ -d $public/$track/$frame/products/$geoifg ]; then 
     #echo "warning, geoifg "$geoifg" already existed. Data will not be overwritten";
     echo "warning, geoifg "$geoifg" already exists. Data will be overwritten";
    else
     echo "moving geocoded "$geoifg
    fi
    mkdir -p $public/$track/$frame/products/$geoifg 2>/dev/null
    for toexp in cc.bmp cc.tif diff.bmp diff_mag.tif diff_pha.tif unw.bmp unw.tif disp_blk.png; do
       if [ -f $frame/GEOC/$geoifg/$geoifg.geo.$toexp ]; then
         #this condition is to NOT TO OVERWRITE the GEOC results. But it makes sense to overwrite them 'always'
         #if [ ! -f $public/$track/$frame/products/$geoifg/$geoifg.geo.$toexp ]; then
          if [ $MOVE -eq 1 ]; then 
           mv $frame/GEOC/$geoifg/$geoifg.geo.$toexp $public/$track/$frame/products/$geoifg/.
          else
           cp $frame/GEOC/$geoifg/$geoifg.geo.$toexp $public/$track/$frame/products/$geoifg/.
          fi
         #fi
       fi
    done
   fi
  done
 else
  echo "warning, geocoding was not performed for "$frame
 fi
fi
#  for dates in `ls $frame/GEOC/20??????_20?????? -d | cut -d '/' -f3`; do
#   if [ -f $frame/GEOC/$dates.geo.diff ] && [ ! -d $frameDir/GEOC/$dates ]; then
#   fi
#  done
# fi
#done
#done

echo "Updating bperp file in pubdir"
cd $thisDir/$frame
#mk_bperp_file.sh
#if [ -f bperp_file ]; then
update_bperp_file.sh
#fi

echo "Deactivating the frame after its storing to db"
setFrameInactive.py $frame



##
#remove this:
#exit
#
##


if [ $DELETEAFTER -eq 1 ];
then
 cd $thisDir
 echo "Deleting downloaded files (if any)"
 if [ -f $frame/$frame'_todown' ]; then
  for zipf in `cat $frame/$frame'_todown' | rev | cut -d '/' -f1 | rev`; do
   if [ -f /gws/nopw/j04/nceo_geohazards_vol2/LiCS/temp/SLC/$zipf ]; then
    rm /gws/nopw/j04/nceo_geohazards_vol2/LiCS/temp/SLC/$zipf
   fi
  done
 fi
 echo "Deleting the frame folder "$frame
 rm -r $frame
fi

echo "done"
