#!/bin/bash

echo "2026/02: Disabling store script due to migration (you may secure your data by touchscratch \$BATCH_CACHE_DIR/\$frame - yes, please use full path)"
echo ""
exit

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


function comparefiles() {
  cmp $1 $2 >/dev/null && echo "identical" || echo "different"
}


#check for changed frame IDs
framechanges=/gws/nopw/j04/nceo_geohazards_vol1/public/LiCSAR_products/frameid_changes.txt
list_added=/gws/nopw/j04/nceo_geohazards_vol1/public/LiCSAR_products/updates/`date +'%Y%m%d'`.$frame.added
if [ -f $list_added'.lock' ]; then
 numprevlines=`ls -al $list_added | gawk {'print $5'}`
 echo "the store process is locked, trying again in 5 seconds"
 sleep 5
 numpostlines=`ls -al $list_added | gawk {'print $5'}`
 while [ ! $numpostlines == $numprevlines ]; do
   numprevlines=`ls -al $list_added | gawk {'print $5'}`
   echo "someone is storing the frame at this moment, waiting iteratively, in 30 sec steps"
   sleep 30
   numpostlines=`ls -al $list_added | gawk {'print $5'}`
 done
 #if [ ! $numpostlines == $numprevlines ]; then
 #  echo "the lock seems not valid, continuing"
 #else
   # if it is active, just create new outfile
   #numm=`ls $list_added.{0-9} 2>/dev/null | wc -l`
   #list_added=/gws/nopw/j04/nceo_geohazards_vol1/public/LiCSAR_products/updates/`date +'%Y%m%d'`.$frame.added.$numm
   #touch $list_added'.lock'
   # but this would cause multiple writes... so cancelling instead
 #  echo "error, someone is storing the frame at this moment, please repeat a bit later"
 #fi
else
 # locking the log file
 touch $list_added'.lock'
fi
if [ ! -f $list_added ]; then touch $list_added; chmod 777 $list_added; fi

if [ `grep -c ^$frame $framechanges` -gt 0 ]; then
 echo "the frame ID has changed:"
 grep $frame $framechanges
 exit
fi

#echo $frame
#exit
#if [ $USER != 'earmla' ]; then echo "you are not admin. Not storing anything."; exit; fi
STORE50m=1
MOVE=0
DORSLC=1
KEEPRSLC=1
DOGEOC=1
DOWEB=1
DOIFG=0 # that's only radarcoded (abandoned...)
DOSUBSETS=1
#let's request gacos data if we do DELETEAFTER..
DOGACOS=0
#previously the default was to overwrite...
GEOC_OVERWRITE=0
IFG_OVERWRITE=0
DELETEAFTER=0
DELETESLCS=0
DOLONGRAMPS=0
QUALCHECK=0
store_logs=1 #for autodelete only
updatedframe=0

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

# check if this was not any previously reinitialised frame
if [ -f $frame/geo/offsets ]; then
if [ `diff $frameDir/geo/offsets $frame/geo/offsets | wc -l ` -gt 0 ]; then
   echo "The frame has been reinitialised and your data are obsolete now - skipping store command, please contact earmla"; exit;
fi
fi

mkdir $pubDir_ifgs 2>/dev/null

if [ $QUALCHECK -eq 1 ]; then
 echo "performing a fast quality check/removal of bad ifgs/epochs"
 frame_ifg_quality_check.py -l -d $frame
fi

if [ $DORSLC -eq 1 ]; then
 DORSLC=0 # need to check further if there is any update to deal with log files transfer.. takes too long..
 if [ -f $frame/framebatch_01_mk_image.nowait.sh ]; then
  firstrun=`stat $frame/framebatch_01_mk_image.nowait.sh | grep Modify | gawk {'print $2'} | sed 's/-//g'`
 else
  firstrun=$today
 fi
 #move rslcs
 if [ -d $frame/RSLC ]; then
  mkdir -p $frameDir/RSLC
  chmod 775 $frameDir/RSLC 2>/dev/null
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
     #let's keep only newer 2 ones - and if the datediff is at least 21 days from the scripts... (precise orbits)
     #if [ $date -gt $master ] && [ `datediff $date $today` -ge 21 ]; then
     if [ $date -gt $master ] && [ `datediff $date $firstrun` -ge 21 ] && [ `datediff $date $today` -ge 21 ]; then
      #these should be kept in RSLC folder!
      out7z=$frameDir/RSLC/$date.7z
      if [ ! -f $out7z ]; then
       echo "compressing RSLC of "$date" to keep last 2 dates"
       cd $frame/RSLC
       7za -mmt=1 a -mx=1 '-xr!*.lt' '-xr!20??????.rslc' '-xr!*mod*' '-xr!*mli*' $out7z $date >/dev/null 2>/dev/null
       chmod 775 $out7z 2>/dev/null
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
  master=`ls $frame/geo/20??????.hgt | cut -d '.' -f1 | cut -d '/' -f3`
  for date in `ls $frame/RSLC/20?????? -d | cut -d '/' -f3`; do
   # if it is not master
   if [ ! $date == $master ]; then
     # skip if not with POEORB
     copydis=1
     if [ -f $frame/log/getValidOrbFile_$date.log ]; then
       if [ ! `grep POEORB $frame/log/getValidOrbFile_$date.log 2>/dev/null | wc -l` -ge 1 ]; then
         copydis=0;
       fi
     fi
    # BUT WE MAY GET SITUATION OF NO SUCH LOG FILE!!!! THUS SKIPPING THIS CHECK
      #if [ $MOVE -eq 1 ]; then rm $frame/RSLC/$date/$date.rslc 2>/dev/null; fi
      # if there are 'some' rslc files
     if [ $copydis -eq 1 ]; then
      if [ `ls $frame/RSLC/$date/$date.IW?.rslc 2>/dev/null | wc -l` -gt 0 ]; then
       echo "checking "$frame"/"$date
       #if it already doesn't exist in LiCSAR_proc dir, or in LUTs, zip it there
       if [ ! -d $frameDir/RSLC/$date ] && [ ! -f $frameDir/RSLC/$date.7z ] && [ ! -f $frameDir/LUT/$date.7z ]; then
        DORSLC=1
        cd $frame/RSLC
        #cleaning the folder
        if [ `ls $date/*.lt 2>/dev/null | wc -w` -gt 0 ] && [ `datediff $date $today` -ge 21 ]; then
         mkdir -p $frameDir/LUT
         chmod 775 $frameDir/LUT 2>/dev/null
         chgrp gws_lics_admin $frameDir/LUT 2>/dev/null
         rm -f $date/*.lt.orbitonly 2>/dev/null
         #copy results file to logs..
         chmod 775 $date/*.results
         cp $date/*.results $frameDir/log/. 2>/dev/null
         echo "compressing LUT of "$date
         7za -mmt=1 a -mx=1 $frameDir/LUT/$date.7z $date/*.lt $date/*.off >/dev/null 2>/dev/null
         if [ -f $frameDir/LUT/$date.7z ]; then
            chmod 775 $frameDir/LUT/$date.7z 2>/dev/null
            chgrp gws_lics_admin $frameDir/LUT/$date.7z 2>/dev/null
            rm -f $date/*.lt 2>/dev/null
         else
            echo "error in zipping the "$date"/*.lt to "$frameDir"/LUT/"$date".7z - please check manually"
         fi
        fi
        #echo "compressing RSLC from "$date
        #echo "the RSLC will not get compressed anymore"
        #time 7za -mmt=1 a -mx=1 '-xr!*.lt' $frameDir/RSLC/$date.7z $date >/dev/null 2>/dev/null
        #if [ $MOVE -eq 1 ]; then rm -r $date; fi
        cd $thisDir
        if [ -f $frame/log/coreg_quality_$master'_'$date.log ]; then
         echo "exporting ESD value"
         store_ESD.py $frame $frame/log/coreg_quality_$master'_'$date.log
        fi
        fi
      fi
     fi
   fi
  done
 fi
fi

if [ $DOSUBSETS -eq 1 ]; then
 subsetsupdated=0
 if [ -d $frameDir/subsets ]; then
  echo "clipping for subsets"
  for subset in `ls $frameDir/subsets`; do
    echo "subset "$subset
    cornersclip=$frameDir/subsets/$subset/corners_clip.$frame
    subdir=$frameDir/subsets/$subset
    if [ -f $cornersclip ]; then
       # getting the clip coords
       azi1=`cat $cornersclip | rev | gawk {'print $1'} | rev | sort -n | head -n1`
       azi2=`cat $cornersclip | rev | gawk {'print $1'} | rev | sort -n | tail -n1`
       let azidiff=azi2-azi1+1
       rg1=`cat $cornersclip | rev | gawk {'print $2'} | rev | sort -n | head -n1`
       rg2=`cat $cornersclip | rev | gawk {'print $2'} | rev | sort -n | tail -n1`
       let rgdiff=rg2-rg1+1
       # running the clipping
       for sdate in `ls $frame/RSLC/20?????? -d | cut -d '/' -f3`; do
       #for x in `ls RSLC | grep 20`; do 
        if [ -f $frame/RSLC/$sdate/$sdate.rslc ]; then
        if [ ! -d $subdir/RSLC/$sdate ]; then
          subsetsupdated=1
          echo "clipping "$sdate
          mkdir -p $subdir/RSLC/$sdate;
          SLC_copy $frame/RSLC/$sdate/$sdate.rslc $frame/RSLC/$sdate/$sdate.rslc.par $subdir/RSLC/$sdate/$sdate.rslc $subdir/RSLC/$sdate/$sdate.rslc.par - - $rg1 $rgdiff $azi1 $azidiff - - >/dev/null 2>/dev/null
          chmod -R 775 $subdir/RSLC/$sdate
          # no need for multilooking here?... 
          #multi_look $outdir/RSLC/$x/$x.rslc $outdir/RSLC/$x/$x.rslc.par $outdir/RSLC/$x/$x.rslc.mli $outdir/RSLC/$x/$x.rslc.mli.par $rgl $azl >/dev/null 2>/dev/null
          # create_geoctiffs_to_pub.sh -M `pwd` $x >/dev/null   # to be improved
        fi
        fi
       done
    else
       echo "corners clip file does not exist - the subset was not initialised correctly"
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
        chmod 775 $frameDir/IFG/$dates 2>/dev/null
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
           chmod 775 $frameDir/IFG/$dates/$dates.$ext 2>/dev/null
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
  if [ -f $frameDir/local_config.py ]; then
   if [ `diff $frame/local_config.py $frameDir/local_config.py | wc -l` -gt 0 ]; then
    echo "copying updated local config file"
    cploc=1
   else
    cploc=0
   fi
  else cploc=1
  fi
  if [ $cploc == 1 ]; then
    cp $frame/local_config.py $frameDir/. 2>/dev/null
    chmod 775 $frameDir/local_config.py 2>/dev/null
    chgrp gws_lics_admin $frameDir/local_config.py 2>/dev/null
  fi
 fi


if [ $DOGEOC -eq 1 ]; then
 #move geoc
 if [ -d $frame/GEOC ]; then
  echo "Storing geoifgs to public folder for frame "$frame
  track=$tr
  for geoifg in `ls $frame/GEOC/20??????_20?????? -d | rev | cut -d '/' -f1 | rev`; do
    updated=0
   if [ -f $frame/GEOC/$geoifg/$geoifg.geo.unw.tif ]; then
    if [ -f $pubDir_ifgs/$geoifg/$geoifg.geo.unw.tif ]; then
     if [ $GEOC_OVERWRITE == 1 ]; then
      if [ `comparefiles $frame/GEOC/$geoifg/$geoifg.geo.unw.tif $pubDir_ifgs/$geoifg/$geoifg.geo.unw.tif` == 'different' ]; then
      #if [ $GEOC_OVERWRITE == 1 ]; then
      # echo "warning, geoifg "$geoifg" already exists. Data will be overwritten";
        echo "the geoifg "$geoifg" differs - updating"
        updated=1
      else
        updated=0
        #echo "warning, geoifg "$geoifg" already existed. Data will not be overwritten";
      fi;
     else
       updated=0
     fi
    else
     echo "copying geocoded "$geoifg
     updated=1
    fi
    mkdir -p $pubDir_ifgs/$geoifg 2>/dev/null
    chmod 775 $pubDir_ifgs/$geoifg 2>/dev/null
    #chgrp gws_lics_admin $pubDir_ifgs/$geoifg 2>/dev/null

    for toexp in bovldiff.adf.mm.tif bovldiff.tif bovldiff.cc.tif bovldiff.adf.tif bovldiff.adf.png bovldiff.adf.cc.tif \
        sbovldiff.adf.mm.tif sbovldiff.adf.cc.tif \
        azi.tif azi.png rng.tif rng.png tracking_corr.tif \
        cc.png cc.tif cc.full.png diff.png diff.full.png diff_unfiltered.png diff_unfiltered.full.png diff_unfiltered_pha.tif \
        mag_cc.png mag_cc.tif \
        diff_pha.tif unw.png unw.full.png unw.tif disp_blk.png; do
       if [ -f $frame/GEOC/$geoifg/$geoifg.geo.$toexp ]; then
         GOON=1
         #if [ $GEOC_OVERWRITE == 0 ]; then
         if [ -f $pubDir_ifgs/$geoifg/$geoifg.geo.$toexp ]; then
          if [ $GEOC_OVERWRITE == 1 ]; then
           if [ `comparefiles $frame/GEOC/$geoifg/$geoifg.geo.$toexp $pubDir_ifgs/$geoifg/$geoifg.geo.$toexp` == 'identical' ]; then
            GOON=0;
           fi;
          else
            GOON=0;
          fi;
         fi
         if [ $GOON == 1 ]; then
         # prelb issue
         if [ -L $frame/GEOC/$geoifg/$geoifg.geo.$toexp ]; then
           if [ -f $frame/GEOC/$geoifg/$geoifg.geo.$toexp.prelb.tif ]; then
             echo "WARNING, you are mixing LiCSAR processed data with LiCSBAS processing - solving for "$geoifg
             rm $frame/GEOC/$geoifg/$geoifg.geo.$toexp
             mv $frame/GEOC/$geoifg/$geoifg.geo.$toexp.prelb.tif $frame/GEOC/$geoifg/$geoifg.geo.$toexp
           else
             echo "The "$geoifg.geo.$toexp" is a link instead of file - skipping"
             GOON=0
           fi
         fi
         fi
         if [ $GOON == 1 ]; then
         #this condition is to NOT TO OVERWRITE the GEOC results. But it makes sense to overwrite them 'always'
         #if [ ! -f $public/$tr/$frame/products/$geoifg/$geoifg.geo.$toexp ]; then
          if [ -L $pubDir_ifgs/$geoifg/$geoifg.geo.$toexp ]; then rm -f $pubDir_ifgs/$geoifg/$geoifg.geo.$toexp; fi
          if [ $MOVE -eq 1 ]; then 
           mv $frame/GEOC/$geoifg/$geoifg.geo.$toexp $pubDir_ifgs/$geoifg/.
          else
           cp $frame/GEOC/$geoifg/$geoifg.geo.$toexp $pubDir_ifgs/$geoifg/.
          fi
         #fi
          echo $pubDir_ifgs/$geoifg/$geoifg.geo.$toexp >> $list_added 2>/dev/null
          chmod 775 $pubDir_ifgs/$geoifg/$geoifg.geo.$toexp 2>/dev/null
          chgrp gws_lics_admin $pubDir_ifgs/$geoifg/$geoifg.geo.$toexp 2>/dev/null
          updated=1
         fi
       fi
    done
   fi
   if [ $updated == 1 ]; then
     cedaarch_create_html.sh $frame $geoifg
     updated=0
     updatedframe=1
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
    GOON=1;
    if [ -f $pubDir_epochs/$img/$img.geo.mli.tif ]; then
     if [ $GEOC_OVERWRITE == 1 ]; then
      if [ `comparefiles $frame/GEOC.MLI/$img/$img.geo.mli.tif $pubDir_epochs/$img/$img.geo.mli.tif` == 'identical' ]; then
            GOON=0;
      fi;
     else
       GOON=0;
     fi
    fi
    if [ $GOON == 1 ]; then
     echo "moving/copying epoch "$img
     mkdir -p $pubDir_epochs/$img
     chmod 775 $pubDir_epochs/$img 2>/dev/null
     #chgrp gws_lics_admin $pubDir_epochs/$img 2>/dev/null
     for toexp in mli.png mli.tif; do
     if [ -f $frame/GEOC.MLI/$img/$img.geo.$toexp ]; then
      if [ -L $pubDir_epochs/$img/$img.geo.$toexp ]; then rm -f $pubDir_epochs/$img/$img.geo.$toexp; fi
      if [ $MOVE -eq 1 ]; then
       mv $frame/GEOC.MLI/$img/$img.geo.$toexp $pubDir_epochs/$img/.
      else
       cp $frame/GEOC.MLI/$img/$img.geo.$toexp $pubDir_epochs/$img/.
      fi
      echo $pubDir_epochs/$img/$img.geo.$toexp >> $list_added 2>/dev/null
      chmod 775 $pubDir_epochs/$img/$img.geo.$toexp 2>/dev/null
      cedaarch_create_html.sh $frame $img epochs
      #chgrp gws_lics_admin $pubDir_epochs/$img/$img.geo.$toexp 2>/dev/null
     fi
     done
    fi
   fi
  done
 fi
fi

# now check and update volcano clips.. ok, still might get skipped (hope not)
if [ ! -z $subsetsupdated ]; then
  if [ $subsetsupdated -gt 0 ]; then
    falbino_volc_clip_figs.py autoframe $frame
    #cntry=`python3 -c "import volcdb as v; a=v.get_volcanoes_in_frame('"$frame"').vportal_area; print(list(set(list(a[~a.isna()])))[0])" 2>/dev/null`
    #if [ ! -z $cntry ]; then
    #  echo "Clipping ifgs for volcano portal"
    #  falbino_volc_clip_figs.py $cntry $frame
    #fi
  fi
fi


if [ $STORE50m -eq 1 ]; then
 if [ -d $frame/GEOC_50m ]; then
  updated=1
  echo "storing also higher res data"
  outdir_ep=$pubDir_epochs'_50m'
  outdir_ifg=$pubDir_ifgs'_50m'
  mkdir -p $outdir_ep $outdir_ifg
  rm $frame/GEOC_50m/*/*.cc $frame/GEOC_50m/*/*.diff $frame/GEOC_50m/*/*.diff_pha 2>/dev/null
  rsync -r $frame/GEOC_50m.MLI/* $outdir_ep
  rsync -r $frame/GEOC_50m/* $outdir_ifg
  chmod -R 775 $outdir_ifg 2>/dev/null
  chmod -R 775 $outdir_ep 2>/dev/null
 fi
 if [ ! -d $LiCSAR_procdir/$tr/$frame/geo_50m ]; then
  if [ -d $frame/geo_50m ]; then
    echo "copying back geo 50 m dir"
    cp -r $frame/geo_50m $LiCSAR_procdir/$tr/$frame/geo_50m
    chmod -R 775 $LiCSAR_procdir/$tr/$frame/geo_50m 2>/dev/null
  fi
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
if [ $updatedframe == 1 ]; then
 echo "Updating bperp file in pubdir"
 cd $thisDir/$frame
 #mk_bperp_file.sh
 #if [ -f bperp_file ]; then
 update_bperp_file.sh
 #fi

 echo "regenerating baseline plot and gaps.txt file (now updated for common bursts - might take bit longer)"
 plot_network.py $pubDir $pubDir_meta/network.png $pubDir_meta/gaps.txt 1
 chmod -R 775 $pubDir_meta/* 2>/dev/null
 
 # checking if the frame is in framelist - if not, add it there
 framelist=$LiCSAR_public/framelist.txt
 if [ `grep -c $frame $framelist` == 0 ]; then
  if [ ! -f $framelist.tmp ]; then
  cp $framelist $framelist.tmp
  echo $frame >> $framelist.tmp
  sort $framelist.tmp > $framelist
  rm $framelist.tmp
  else
   echo "ERROR - wanted to update framelist.txt but it seems in a parallel process, cancelling"
  fi
 fi
fi
#echo "WARNING - we do not deactivate the frame now..."
#echo "Deactivating the frame after its storing to db"
#setFrameInactive.py $frame
#for tr in `seq 1 175`; do for fr in `ls $tr`; do plot_network.py $LiCSAR_public/$tr/$fr $LiCSAR_public/$tr/$fr/metadata/network.png $LiCSAR_public/$tr/$fr/metadata/gaps.txt; done; done

#plot_network.py `pwd` `pwd`/metadata/network2.png `pwd`/metadata/gaps.txt



 #move tabs and logs
# if [ -d $frame/tab ]; then
#  echo "copying new tabs and logs"
#  for tab in `ls $frame/tab`; do
#   if [ ! -f $frameDir/tab/$tab ]; then
#    cp $frame/tab/$tab $frameDir/tab/.
#   fi
#  done
# fi
# 12/2022 - copy logs only for data after esd (new orbits) correction
if [ $DORSLC -eq 1 ]; then
 if [ -d $frame/log ]; then
  echo "copying logs"
  echo "only *quality* logs will be saved"
  for log in `ls $frame/log/*quality* $frame/log/getValidO*`; do
   #if [ ! -f $frameDir/log/`basename $log` ]; then
    rm -f $frameDir/log/`basename $log`
    cp $log $frameDir/log/.
    chmod 775 $frameDir/log/`basename $log` 2>/dev/null
    chgrp gws_lics_admin $frameDir/log/`basename $log` 2>/dev/null
    ##cp $frame/log/$log $frameDir/log/.
   #fi
  done
 fi
fi


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
   if [ -f /gws/nopw/j04/nceo_geohazards_vol2/LiCS/temp/SLC/$zipf ]; then
    rm -f /gws/nopw/j04/nceo_geohazards_vol2/LiCS/temp/SLC/$zipf
   fi
  done
 fi
 fi
 if [ $store_logs -eq 1 ]; then
  echo "storing log files"
  logoutf=LOGS/$frame'.7z'
  rm -f $logoutf 2>/dev/null
  7za -mmt=1 a $logoutf $frame/LOGS/* >/dev/null 2>/dev/null
 fi
 echo "Deleting the frame folder "$frame
 rm -rf $frame

#echo "Expiring NLA requests (if any)"
#for nlareqid in `nla.py requests | grep $frame | gawk {'print $1'} 2>/dev/null`; do
# nla.py expire $nlareqid
#done

fi


if [ $DOGACOS -eq 1 ]; then
 echo "requesting GACOS data " #"- in the background, please run in tmux or keep session alive for HOURS"
 framebatch_update_gacos.sh $frame # >/dev/null 2>/dev/null &
 DOLONGRAMPS=1
fi

# deleting log file lock and empty log file
if [ `ls -al $list_added | gawk {'print $5'}` == 0 ]; then
 echo "nothing changed in the public directory"
 rm -f $list_added
fi
rm -f $list_added'.lock'

# exceptions
if [ $frame == '140D_SM_FGBR_S4' ]; then
  echo "exception - checking the geocoding if ok - epochs and GACOS might be still bad.. to improve"
  fix_geocoding_frame.sh 140D_SM_FGBR_S4
fi

# SET and ionosphere
if [ $DOLONGRAMPS -eq 1 ]; then
 echo "additionally, extracting extra terms for correction (SET and IONO)"
 python3 -c "from iono_correct import *; make_all_frame_epochs('"$frame"')"
 # and now SET (bigger files.. unfortunately)
 create_LOS_tide_frame_allepochs $frame
 for ep in `ls $pubDir_epochs | grep ^20`; do
   cedaarch_create_html.sh $frame $ep epochs
 done
fi
echo "done"



exit



# ok, need to run following to check and make link to /neodc for all png and tif files in epochs and interferograms folders:
cedaarch_filelink.sh $file
# function to get same or different file within /neodc:

function comparefiles() {
  cmp $1 $2 >/dev/null && echo "identical" || echo "different"
}
