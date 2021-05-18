#!/bin/bash
#curdir=/gws/nopw/j04/nceo_geohazards_vol1/projects/LiCS/proc/current
module load LiCSBAS
source $LiCSARpath/lib/LiCSAR_bash_lib.sh

today=`date +%Y%m%d`
curdir=$LiCSAR_procdir
public=$LiCSAR_public
if [ -z $1 ]; then
 echo "Parameter: *_*_* frame folder.. MUST BE IN THIS FOLDER";
 echo "full parameters are:";
 echo "store_to_curdir.sh FRAME [DELETEAFTER] [OVERWRITE] [DOGACOS]";
 echo "defaults are 0 0 0"
 exit;
 else frame=`basename $1`; fi

if [ ! -d $frame ]; then echo "framedir does not exist - are you be in the \$BATCH_CACHE_DIR \?"; exit; fi

#check for changed frame IDs
framechanges=/nesi/project/gns03165/geohazards/public/LiCSAR_products/frameid_changes.txt
list_added=/nesi/project/gns03165/geohazards/public/LiCSAR_products/updates/`date +'%Y%m%d'`.added

if [ ! -f $list_added ]; then touch $list_added; chmod 777 $list_added; fi

if [ `grep -c ^$frame $framechanges` -gt 0 ]; then
 echo "the frame ID has changed:"
 grep $frame $framechanges
 exit
fi

#echo $frame
#exit
#if [ $USER != 'earmla' ]; then echo "you are not admin. Not storing anything."; exit; fi

MOVE=0
DORSLC=1
KEEPRSLC=1
DOGEOC=1
DOIFG=1
#let's request gacos data if we do DELETEAFTER..
DOGACOS=0
#previously the default was to overwrite...
GEOC_OVERWRITE=0
IFG_OVERWRITE=0
DELETEAFTER=0
DELETESLCS=0
QUALCHECK=0
store_logs=1 #for autodelete only

#second parameter - if 1, then delete after storing
#third parameter - if 0, then disable overwriting of GEOC and IFG files
if [ ! -z $2 ]; then if [ $2 -eq 1 ]; then DELETEAFTER=1; store_logs=1; MOVE=1; DOGACOS=1; echo "setting to delete (and to perform GACOS)"; fi; fi
if [ ! -z $3 ]; then if [ $3 -eq 0 ] || [ $3 -eq 1 ]; then GEOC_OVERWRITE=$3; IFG_OVERWRITE=$3; echo "overwrite switched to "$3; fi; fi
if [ ! -z $4 ]; then if [ $4 -eq 0 ] || [ $4 -eq 1 ]; then DOGACOS=$4; echo "DOGACOS switched to "$4; fi; fi
#have to remove this line ASAP:
#DELETEAFTER=0

#for thisDir in /gws/nopw/j04/nceo_geohazards_vol2/LiCS/temp/volc /gws/nopw/j04/nceo_geohazards_vol2/LiCS/temp/volc/frames; do
#cd $thisDir
#for frame in `ls [0-9]*_?????_?????? -d`; do
#cd $frame
#cd ..
thisDir=`pwd`
tr=`echo $frame | cut -d '_' -f1 | sed 's/^0//' | sed 's/^0//' | rev | cut -c 2- | rev`
frameDir=$curdir/$tr/$frame
pubDir=$public/$tr/$frame
pubDir_ifgs=$public/$tr/$frame/interferograms
pubDir_epochs=$public/$tr/$frame/epochs
pubDir_meta=$public/$tr/$frame/metadata
if [ ! -d $pubDir_meta ]; then
 echo "public directory does not exist for the frame. Cancelling"
 exit
fi

if [ $QUALCHECK -eq 1 ]; then
 echo "performing a fast quality check/removal of bad ifgs/epochs"
 frame_ifg_quality_check.py -l -d $frame
fi


if [ $DORSLC -eq 1 ]; then
 #move rslcs
 if [ -d $frame/RSLC ]; then
  mkdir -p $frameDir/RSLC
  chmod 774 $frameDir/RSLC 2>/dev/null
  chgrp gws_lics_admin $frameDir/RSLC 2>/dev/null
  #first of all check and move last three RSLCs - if they are full-bursted
  if [ $KEEPRSLC -eq 1 ]; then
    #check only last 10 rslcs
    ls $frame/RSLC/20?????? -d | cut -d '/' -f3 | tail -n 10 > temp_$frame'_keeprslc'
    master=`ls $frame/geo/20??????.hgt | cut -d '.' -f1 | cut -d '/' -f3`
    mastersize=`grep azimuth_lines $frame/SLC/$master/$master.slc.par | gawk {'print $2'}`
    sed -i '/'$master'/d' temp_$frame'_keeprslc'
    for date in `cat temp_$frame'_keeprslc' `; do
      if [ ! `grep azimuth_lines $frame/RSLC/$date/$date.rslc.par | gawk {'print $2'}` -eq $mastersize ]; then
       sed -i '/'$date'/d' temp_$frame'_keeprslc'
      fi
    done
    for date in `sort -r temp_$frame'_keeprslc' | head -n2`; do
     #let's keep only newer 2 ones - and if the datediff is at least 21 days... (precise orbits)
     if [ $date -gt $master ] && [ `datediff $date $today` -ge 21 ]; then
      #these should be kept in RSLC folder!
      out7z=$frameDir/RSLC/$date.7z
      if [ ! -f $out7z ]; then
       echo "compressing RSLC of "$date" to keep last 2 dates"
       cd $frame/RSLC
       7za a -mx=1 '-xr!*.lt' '-xr!20??????.rslc' $out7z $date >/dev/null 2>/dev/null
       chmod 664 $out7z 2>/dev/null
       chgrp gws_lics_admin $out7z 2>/dev/null
       cd - 2>/dev/null
      fi
     fi
    done
    if [ `ls $frameDir/RSLC/*7z 2>/dev/null | wc -l` -gt 2 ]; then
     #delete more rslc 7z files than last 2 dates
     ls $frameDir/RSLC/*7z > temp_$frame'_keeprslc2'
     for todel in `head -n-2 temp_$frame'_keeprslc2'`; do
      rm -f $todel
     done
    fi
    rm -f temp_$frame'_keeprslc' temp_$frame'_keeprslc2' 2>/dev/null
  fi
  #now do the routine export
  for date in `ls $frame/RSLC/20?????? -d | cut -d '/' -f3`; do
   # if it is not master
   if [ ! -d $frameDir/SLC/$date ]; then
    #if [ $MOVE -eq 1 ]; then rm $frame/RSLC/$date/$date.rslc 2>/dev/null; fi
    # if there are 'some' rslc files
    if [ `ls $frame/RSLC/$date/$date.IW?.rslc 2>/dev/null | wc -l` -gt 0 ]; then
     echo "checking "$frame"/"$date
     #if it already doesn't exist in current dir
     if [ ! -d $frameDir/RSLC/$date ] && [ ! -f $frameDir/RSLC/$date.7z ]; then
      cd $frame/RSLC
      #cleaning the folder
      if [ `ls $date/*.lt 2>/dev/null | wc -w` -gt 0 ] && [ `datediff $date $today` -ge 21 ]; then
       mkdir -p $frameDir/LUT
       chmod 774 $frameDir/LUT 2>/dev/null
       chgrp gws_lics_admin $frameDir/LUT 2>/dev/null
       rm -f $date/*.lt.orbitonly 2>/dev/null
       echo "compressing LUT of "$date
       7za a -mx=1 $frameDir/LUT/$date.7z $date/*.lt $date/*.off >/dev/null 2>/dev/null
       if [ -f $frameDir/LUT/$date.7z ]; then
          chmod 664 $frameDir/LUT/$date.7z 2>/dev/null
          chgrp gws_lics_admin $frameDir/LUT/$date.7z 2>/dev/null
          rm -f $date/*.lt
       else
          echo "error in zipping the "$date"/*.lt to "$frameDir"/LUT/"$date".7z - please check manually"
       fi
      fi
      #echo "compressing RSLC from "$date
      #echo "the RSLC will not get compressed anymore"
      #time 7za a -mx=1 '-xr!*.lt' $frameDir/RSLC/$date.7z $date >/dev/null 2>/dev/null
      #if [ $MOVE -eq 1 ]; then rm -r $date; fi
      cd $thisDir
     fi
    fi
   fi
  done
 fi
 fi

if [ $DOIFG -eq 1 ]; then
 echo "checking interferograms"
 #move ifgs (if unwrapped is also done)
 if [ -d $frame/IFG ]; then
  for dates in `ls $frame/IFG/20??????_20?????? -d | cut -d '/' -f3`; do
   if [ -f $frame/IFG/$dates/$dates.unw ]; then
       if [ ! -d $frameDir/IFG/$dates ]; then
        mkdir -p $frameDir/IFG/$dates
        chmod 774 $frameDir/IFG/$dates 2>/dev/null
        chgrp gws_lics_admin $frameDir/IFG/$dates 2>/dev/null
        echo "moving (or copying) ifg "$dates
       fi
        #for ext in cc diff filt.cc filt.diff off unw; do
        for ext in cc diff off; do
         if [ -f $frame/IFG/$dates/$dates.$ext ] && [ ! -L $frame/IFG/$dates/$dates.$ext ]; then
          GOON=1
          if [ $IFG_OVERWRITE == 0 ]; then
           if [ -f $frameDir/IFG/$dates/$dates.$ext ]; then GOON=0; fi
          fi
          if [ $GOON == 1 ]; then
           echo "copying ifg file "$dates.$ext
           if [ $MOVE -eq 1 ]; then
            mv $frame/IFG/$dates/$dates.$ext $frameDir/IFG/$dates/. 2>/dev/null
           else
            cp $frame/IFG/$dates/$dates.$ext $frameDir/IFG/$dates/. 2>/dev/null
           fi
           chmod 664 $frameDir/IFG/$dates/$dates.$ext 2>/dev/null
           chgrp gws_lics_admin $frameDir/IFG/$dates/$dates.$ext 2>/dev/null
          fi
         fi
        done
       #fi
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

# echo "Stored "$frame" on "`date +'%Y-%m-%d'`>> $thisDir/stored_to_curdir.txt
 #local_config.py file
 if [ -f $frame/local_config.py ]; then
  echo "copying local config file"
  cp $frame/local_config.py $frameDir/. 2>/dev/null
  chmod 774 $frameDir/local_config.py 2>/dev/null
  chgrp gws_lics_admin $frameDir/local_config.py 2>/dev/null
 fi

 #move tabs and logs
# if [ -d $frame/tab ]; then
#  echo "copying new tabs and logs"
#  for tab in `ls $frame/tab`; do
#   if [ ! -f $frameDir/tab/$tab ]; then
#    cp $frame/tab/$tab $frameDir/tab/.
#   fi
#  done
# fi
 if [ -d $frame/log ]; then
  echo "copying logs"
  echo "only *quality* logs will be saved"
  for log in `ls $frame/log/*quality*`; do
   #if [ ! -f $frameDir/log/`basename $log` ]; then
    cp $log $frameDir/log/.
    chmod 774 $frameDir/log/$log 2>/dev/null
    chgrp gws_lics_admin $frameDir/log/$log 2>/dev/null
    ##cp $frame/log/$log $frameDir/log/.
   #fi
  done
 fi


if [ $DOGEOC -eq 1 ]; then
 #move geoc
 if [ -d $frame/GEOC ]; then
  echo "Moving geoifgs to public folder for frame "$frame
  track=$tr
  for geoifg in `ls $frame/GEOC/20??????_20?????? -d | rev | cut -d '/' -f1 | rev`; do
   if [ -f $frame/GEOC/$geoifg/$geoifg.geo.unw.tif ]; then
    if [ -f $pubDir_ifgs/$geoifg/$geoifg.geo.unw.tif ]; then
      if [ $GEOC_OVERWRITE == 1 ]; then
       echo "warning, geoifg "$geoifg" already exists. Data will be overwritten";
      else
       echo "warning, geoifg "$geoifg" already existed. Data will not be overwritten";
      fi;
    else
     echo "moving geocoded "$geoifg
    fi
    mkdir -p $pubDir_ifgs/$geoifg 2>/dev/null
    chmod 774 $pubDir_ifgs/$geoifg 2>/dev/null
    #chgrp gws_lics_admin $pubDir_ifgs/$geoifg 2>/dev/null

    # update this for unfiltered ones..
    for toexp in cc.png cc.tif cc.full.png diff.png diff.full.png diff_unfiltered.png diff_unfiltered.full.png diff_unfiltered_pha.tif diff_pha.tif unw.png unw.full.png unw.tif disp_blk.png; do
       if [ -f $frame/GEOC/$geoifg/$geoifg.geo.$toexp ]; then
         GOON=1
         if [ $GEOC_OVERWRITE == 0 ]; then
          if [ -f $pubDir_ifgs/$geoifg/$geoifg.geo.$toexp ]; then GOON=0; fi
         fi
         if [ $GOON == 1 ]; then
         #this condition is to NOT TO OVERWRITE the GEOC results. But it makes sense to overwrite them 'always'
         #if [ ! -f $public/$tr/$frame/products/$geoifg/$geoifg.geo.$toexp ]; then
          if [ $MOVE -eq 1 ]; then
           mv $frame/GEOC/$geoifg/$geoifg.geo.$toexp $pubDir_ifgs/$geoifg/.
          else
           cp $frame/GEOC/$geoifg/$geoifg.geo.$toexp $pubDir_ifgs/$geoifg/.
          fi
         #fi
          echo $pubDir_ifgs/$geoifg/$geoifg.geo.$toexp >> $list_added 2>/dev/null
          chmod 664 $pubDir_ifgs/$geoifg/$geoifg.geo.$toexp 2>/dev/null
          chgrp gws_lics_admin $pubDir_ifgs/$geoifg/$geoifg.geo.$toexp 2>/dev/null
         fi
       fi
    done
   fi
  done
 else
  echo "warning, geocoding was not performed for "$frame
 fi

 if [ -d $frame/GEOC.MLI ]; then
  echo "Moving geoimages to public folder for frame "$frame
  track=$tr
  for img in `ls $frame/GEOC.MLI/2* -d | rev | cut -d '/' -f1 | rev`; do
   if [ -f $frame/GEOC.MLI/$img/$img.geo.mli.tif ]; then
    if [ -d $pubDir_epochs/$img ]; then
     echo "epoch for "$img" exists, we will not overwrite now"
    else
     echo "moving/copying epoch "$img
     mkdir -p $pubDir_epochs/$img
     chmod 774 $pubDir_epochs/$img 2>/dev/null
     #chgrp gws_lics_admin $pubDir_epochs/$img 2>/dev/null
     for toexp in mli.png mli.tif; do
     if [ -f $frame/GEOC.MLI/$img/$img.geo.$toexp ]; then
      if [ $MOVE -eq 1 ]; then
       mv $frame/GEOC.MLI/$img/$img.geo.$toexp $pubDir_epochs/$img/.
      else
       cp $frame/GEOC.MLI/$img/$img.geo.$toexp $pubDir_epochs/$img/.
      fi
      echo $pubDir_epochs/$img/$img.geo.$toexp >> $list_added 2>/dev/null
      chmod 664 $pubDir_epochs/$img/$img.geo.$toexp 2>/dev/null
      #chgrp gws_lics_admin $pubDir_epochs/$img/$img.geo.$toexp 2>/dev/null
     fi
     done
    fi
   fi
  done
 fi
fi



#  for dates in `ls $frame/GEOC/20??????_20?????? -d | cut -d '/' -f3`; do
#   if [ -f $frame/GEOC/$dates.geo.diff ] && [ ! -d $frameDir/GEOC/$dates ]; then
#   fi
#  done
# fi
#done
#done


#this does not work well due to multiple connections...of course
#echo "Updating frame csv"
#update_framecsv.py -f $frame

echo "Updating bperp file in pubdir"
cd $thisDir/$frame
#mk_bperp_file.sh
#if [ -f bperp_file ]; then
update_bperp_file.sh
#fi

echo "regenerating baseline plot and gaps.txt file"
plot_network.py $pubDir $pubDir_meta/network.png $pubDir_meta/gaps.txt

#echo "WARNING - we do not deactivate the frame now..."
#echo "Deactivating the frame after its storing to db"
#setFrameInactive.py $frame


##
#remove this:
#exit
#
##


if [ $DELETEAFTER -eq 1 ];
then
 cd $thisDir
 echo "Deactivating the frame after its storing to db"
 setFrameInactive.py $frame
 if [ $DELETESLCS -eq 1 ]; then
 echo "Deleting downloaded files (if any)"
 if [ -f $frame/$frame'_todown' ]; then
  for zipf in `cat $frame/$frame'_todown' | rev | cut -d '/' -f1 | rev`; do
#   if [ -f /gws/nopw/j04/nceo_geohazards_vol2/LiCS/temp/SLC/$zipf ]; then
#    rm -f /gws/nopw/j04/nceo_geohazards_vol2/LiCS/temp/SLC/$zipf
#   fi
   if [ -f /nesi/nobackup/gns03165/LiCS/temp/SLC/$zipf ]; then
    rm -f /nesi/nobackup/gns03165/LiCS/temp/SLC/$zipf
   fi
  done
 fi
 fi
 if [ $store_logs -eq 1 ]; then
  echo "storing log files"
  logoutf=$BATCH_CACHE_DIR/LOGS/$frame'.7z'
  rm -f $logoutf 2>/dev/null
  7za a $logoutf $frame/LOGS/* >/dev/null 2>/dev/null
 fi
 echo "Deleting the frame folder "$frame
 rm -rf $frame

#echo "Expiring NLA requests (if any)"
#for nlareqid in `nla.py requests | grep $frame | gawk {'print $1'} 2>/dev/null`; do
# nla.py expire $nlareqid
#done

fi


if [ $DOGACOS -eq 1 ]; then
 echo "requesting GACOS data - in the background, please run in tmux or keep session alive for HOURS"
 framebatch_update_gacos.sh $frame >/dev/null 2>/dev/null &
fi

echo "done"
