#!/bin/bash

# this is to process the volcid - ifgs and licsbas

if [ -z $1 ]; then
 echo "Usage e.g.: volq_process.sh [-M 3] [-P] [-l] [-p] [-L] [-C 0.15] [-g] -i volclip_id (or -n volcname or -v volcID)"
 #echo "Usage e.g.: subset_mk_ifgs.sh [-P] $LiCSAR_procdir/subsets/Levee_Ramsey/165A [ifgs.list]"
 echo "parameter -P will run through comet queue"
 echo "parameter -L will run in LiCSAR regime (frame processing - update)"
 echo "-- for LiCSBAS regime:"
 echo "parameter -g for use of GACOS - not by default anymore as this would not run for the latest epoch..."
 echo "parameter -l means to run from lowres (additionally, with parameter -p it will clip to the extents as on volcano portal that is 55 km diameter)"
 echo "parameter -M X means target multilook factor (only for hires regime - by default -M 3)"
 echo "parameter -C 0.X would apply additional masking based on individual coherence"
 echo "parameter -R would add range offset tracking-supported unwrapping"
 echo "-s would use sid"
 #echo "----"
 echo "this will copy and process ifgs and store in \$BATCH_CACHE_DIR/subsets/\$sid/\$frameid directory"
 echo "---"
 #echo "NOTE: if you use ifgs.list, please provide FULL PATH. Also note, the ifgs.list should contain pairs in the form of e.g.:"
 #echo "20180101_20180303"
 exit
fi

extra=''
lbextra=''
regime='licsbas'
lowres=0
ml=3
clipasportal=0
volcid=''
sid=''

while getopts ":PRlgpLs:n:i:C:M:v:" option; do
 case "${option}" in
  P) extra='-P ';
     ;;
  g) lbextra=$lbextra' -g';
     ;;
  i ) vid=$OPTARG;
     ;;
  M ) ml=$OPTARG;
     ;;
  s ) sid=$OPTARG;
     ;;
  L ) regime='licsar';
     ;;
  n ) vid=`python3 -c "import volcdb; volcid=int(volcdb.find_volcano_by_name('"$OPTARG"').volc_id); print(volcdb.get_volclip_vids(volcid)[0])" | tail -n 1`;
     ;;
  v ) vid=`python3 -c "import volcdb; print(volcdb.get_volclip_vids("$OPTARG")[0])" | tail -n 1`;
      volcid=$OPTARG;
     ;;
  l ) lowres=1;
    ;;
  p ) clipasportal=1;
    ;;
  C ) lbextra=$lbextra' -C '$OPTARG;
    ;;
  R ) extra=$extra' -R ';
      lbextra=$lbextra' -R ';
    ;;
 esac
done
shift $((OPTIND -1))

if [ $clipasportal == 1 ]; then
  if [ $lowres == 0 ]; then
    echo "ERROR, you set clip as portal (-p) but not for the orig lics data regime - volq clips cannot be enlarged, thus stopping here (we may instead pad by zeroes)"
    exit
  fi
fi

if [ ! -z $vid ]; then
 echo "Running processing for volclip ID "$vid
else
  if [ -z $sid ]; then
  echo "error finding volclip ID, cancelling"
  exit
 fi
fi
#if [ -z $1 ]; then echo "please check provided parameters"; exit; fi

if [ $regime == 'licsar' ]; then
  if [ -z $sid ]; then
   tempfile=$BATCH_CACHE_DIR/$vid.frames
   python3 -c "import volcdb; vid="$vid"; volcid=volcdb.get_volcano_from_vid(vid); print(volcdb.get_volcano_frames(volcid))"> $tempfile.bb
   for x in `grep '\[' $tempfile.bb | sed "s/'//g" | sed 's/\[//' | sed 's/\]//' | sed 's/\,//'`; do
     echo $x >> $tempfile
   done
   rm $tempfile.b
  else
   sidpath=$LiCSAR_procdir/subsets/$sid
   tempfile=$BATCH_CACHE_DIR/$sid.frames
   for sidf in `ls $sidpath/*/corners_clip.*`; do
     echo $sidf | rev | cut -d '.' -f 1 | rev >> $tempfile
   done
  fi
  #for x in `grep '\[' $tempfile | sed "s/'//g" | sed 's/\[//' | sed 's/\]//' | sed 's/\,//'`; do
  for x in `cat $tempfile`; do
     echo "running background process for frame "$frame
     # nohup framebatch_update_frame.sh -u $extra $x upfill > $tempfile.log.$x &
     # removing 'extra' as LOTUS2 now does not support prioritised queues...
     nohup framebatch_update_frame.sh -u $x upfill > $tempfile.log.$x &
     sleep 15
  done
  rm $tempfile 2>/dev/null
  exit
fi

# if regime is not licsar, it is licsbas regime.. continuing

# 2024/11: we want to clip to the same area...
if [ $clipasportal == 0 ]; then
  if [ -z $sid ]; then
   cliparea=`python3 -c "import volcdb; print(volcdb.get_licsbas_clipstring_volclip("$vid"))" | tail -n 1`
  fi
else
  if [ -z $volcid ]; then
    volcid=`python3 -c "import volcdb; vid="$vid"; volcid=volcdb.get_volcano_from_vid(vid); print(volcid)"`
  fi
  cliparea=`python3 -c "import volcdb; print(volcdb.get_licsbas_clipstring_volcano(volcid = "$volcid", customradius_km = 55.55/2))" | tail -n 1`
fi

if [ $lowres == 1 ]; then
  echo "running for lowres only"
  procpath=$BATCH_CACHE_DIR/subsets/$vid/lowres
  mkdir -p $procpath; cd $procpath
  for frame in `python3 -c "from volcdb import *; volc=get_volcano_from_vid("$vid"); print(get_volcano_frames(volc))" | tail -n 1 | sed 's/\,//g' | sed "s/'//g" | sed 's/\[//' | sed 's/\]//'`; do
    echo $frame
    #licsar2licsbas.sh -M 1 -s -g -u -W -T -d -n 4 -G $cliparea $extra $frame
    #licsar2licsbas.sh -M 1 -g -u -W -T -n 4 -G $cliparea $extra $frame
    licsar2licsbas.sh -M 1 -u -d -T -n 4 -t 0.15 -G $cliparea $lbextra $frame
  done
exit
fi

#volcid=$1
if [ ! -z $sid ]; then
  vidpath=$LiCSAR_procdir/subsets/$sid
else
  vidpath=$LiCSAR_procdir/subsets/volc/$vid
fi

for subfr in `ls $vidpath`; do
  procpath=$BATCH_CACHE_DIR/subsets/$vid/$subfr
  # prepare licsbas script
  mkdir -p $procpath
  echo "cd "$procpath"; " > $procpath/l2l.sh
  #echo "licsar2licsbas.sh -M 2 -F -g -u -W -T -d -n 4 -s " >> $procpath/l2l.sh
  #echo "licsar2licsbas.sh -M 5 -F -g -u -W -T -d -n 4 -s " >> $procpath/l2l.sh
  # 2024/01 - using GAMMA's ADF2 - should be better than goldstein (i hope)
  #echo "licsar2licsbas.sh -M 3 -F -g -u -W -T -d -n 4 " >> $procpath/l2l.sh
  # 2024/01/31 - NOPE! ADF2 is horrible! using smooth, and from unfiltered - best results over Fogo! (or cascade, but that takes too long)
  #echo "licsar2licsbas.sh -M 3 -s -g -u -W -T -d -n 4 "$extra >> $procpath/l2l.sh
  if [ ! -z $cliparea ]; then
   echo "licsar2licsbas.sh -M "$ml" -G "$cliparea" -u -d -T -t 0.2 -h 23 -n 4 "$lbextra >> $procpath/l2l.sh
  else
    echo "licsar2licsbas.sh -M "$ml" -u -d -T -t 0.2 -h 23 -n 4 "$lbextra >> $procpath/l2l.sh
  fi
  chmod 777 $procpath/l2l.sh
  subset_mk_ifgs.sh $extra -s $procpath/l2l.sh -N $vidpath/$subfr
  # subset_mk_ifgs.sh $extra $vidpath/$subfr
done

if [ -z $sid ]; then
  volcid=`python3 -c "import volcdb; print(volcdb.get_volcano_from_vid("$vid"))" 2>/dev/null | tail -n 1`
  mkdir -p $BATCH_CACHE_DIR/subsets/per_volcano/$volcid
  cd $BATCH_CACHE_DIR/subsets/per_volcano/$volcid
  for subfr in `ls $vidpath`; do
    ln -s $BATCH_CACHE_DIR/subsets/$vid/$subfr;
  done
fi