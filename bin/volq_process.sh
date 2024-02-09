#!/bin/bash

# this is to process the volcid - ifgs and licsbas

if [ -z $1 ]; then
 echo "Usage e.g.: volq_process.sh [-P] [-l] -i volclip_id (or -n volcname or -v volcID)"
 #echo "Usage e.g.: subset_mk_ifgs.sh [-P] $LiCSAR_procdir/subsets/Levee_Ramsey/165A [ifgs.list]"
 echo "parameter -P will run through comet queue"
 echo "parameter -l means to run from lowres"
 echo "----"
 echo "this will copy and process ifgs and store in \$BATCH_CACHE_DIR/subsets/\$sid/\$frameid directory"
 #echo "NOTE: if you use ifgs.list, please provide FULL PATH. Also note, the ifgs.list should contain pairs in the form of e.g.:"
 #echo "20180101_20180303"
 exit
fi

extra=''
lowres=0
while getopts ":PRln:i:v:" option; do
 case "${option}" in
  P) extra='-P ';
     ;;
  i ) vid=$OPTARG;
     ;;
  n ) vid=`python3 -c "import volcdb; volcid=int(volcdb.find_volcano_by_name('"$OPTARG"').volc_id); print(volcdb.get_volclip_vids(volcid)[0])" | tail -n 1`;
     ;;
  v ) vid=`python3 -c "import volcdb; print(volcdb.get_volclip_vids("$OPTARG")[0])" | tail -n 1`;
     ;;
  l ) lowres=1;
    ;;
  R) extra='-R ';
 esac
done
shift $((OPTIND -1))

if [ ! -z $vid ]; then
 echo "Running processing for volclip ID "$vid
else
 echo "error finding volclip ID, cancelling"
 exit
fi
#if [ -z $1 ]; then echo "please check provided parameters"; exit; fi

if [ $lowres == 1 ]; then
  echo "running for lowres only"
  procpath=$BATCH_CACHE_DIR/subsets/$vid/lowres
  mkdir -p $procpath; cd $procpath
  cliparea=`python3 -c "import volcdb; print(volcdb.get_licsbas_clipstring_volclip("$vid"))" | tail -n 1`
  for frame in `python3 -c "from volcdb import *; volc=get_volcano_from_vid("$vid"); print(get_volcano_frames(volc))" | tail -n 1 | sed 's/\,//g' | sed "s/'//g" | sed 's/\[//' | sed 's/\]//'`; do
    echo $frame
    #licsar2licsbas.sh -M 1 -s -g -u -W -T -d -n 4 -G $cliparea $extra $frame
    licsar2licsbas.sh -M 1 -g -u -W -T -n 4 -G $cliparea $extra $frame
  done
exit
fi

#volcid=$1
vidpath=$LiCSAR_procdir/subsets/volc/$vid
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
  echo "licsar2licsbas.sh -M 3 -g -u -W -T -n 4 "$extra >> $procpath/l2l.sh
  chmod 777 $procpath/l2l.sh
  subset_mk_ifgs.sh $extra -s $procpath/l2l.sh $vidpath/$subfr
  # subset_mk_ifgs.sh $extra $vidpath/$subfr
done
