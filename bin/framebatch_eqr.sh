#!/bin/bash

#this should copy the RSLC files to EQR buffer at CEDA, so it can be ingested
#to ARC in the next run

master=`basename geo/20??????.hgt .hgt`
WORKFRAMEDIR=`pwd`
frame=`pwd | rev | cut -d '/' -f1 | rev`
EQRDIR='/gws/nopw/j04/nceo_geohazards_vol1/projects/LiCS/proc/current/EQR'
eqrframedir=$EQRDIR/$frame

if [ ! -d $eqrframedir ]; then
 mkdir $eqrframedir
else
 echo "I should include some check here for cases where it is in processing"
 if [ -f $eqrframedir/COPYING ]; then
  echo "seems done and in process of copying. Exiting now"
  exit
 fi
 if [ -f $eqrframedir/COPYFAILED ]; then
  echo "there was some error copying this frame already. trying again"
  rm $eqrframedir/COPYFAILED
  #exit
 fi
 if [ -f $eqrframedir/COPIED ]; then
  echo "files are copied. I should check for new files - anyway, going on.."
  rm $eqrframedir/COPIED
 fi
fi

touch $eqrframedir/COPYING
if [ `ls $WORKFRAMEDIR/RSLC | wc -l` -lt 2 ]; then
 echo "ERROR - nothing was processed"
 echo "no RSLCs were generated" > $eqrframedir/COPYFAILED
else
 echo "rsyncing to EQR directory "$eqrframedir
 #rsync -r $WORKFRAMEDIR $EQRDIR
 echo "(copying only generated RSLC files)"
 if [ `ls $WORKFRAMEDIR/RSLC | wc -l ` -gt 4 ]; then
  echo "too many RSLCs generated. copying one by one"
  mkdir $eqrframedir/RSLC 2>/dev/null
  for rslc in `ls $WORKFRAMEDIR/RSLC | tail -n 4`; do
   if [ ! -d $eqrframedir/RSLC/$rslc ]; then
    cp -r $WORKFRAMEDIR/RSLC/$rslc $eqrframedir/RSLC/.
   fi
  done
 else
  rsync -r $WORKFRAMEDIR/RSLC $eqrframedir
 fi
 touch $eqrframedir/COPIED
fi

rm $eqrframedir/COPYING

