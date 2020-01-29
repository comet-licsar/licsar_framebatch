#!/bin/bash
rm -r $BATCH_CACHE_DIR/volc 2>/dev/null
mkdir $BATCH_CACHE_DIR/volc
echo "preparing list of frames to update"
for x in `ls /gws/nopw/j04/nceo_geohazards_vol1/projects/LiCS/volc-proc/list_database/*frame.txt`; do
 cat $x >> $BATCH_CACHE_DIR/volc/allframes.tmp
done
#additional requests
echo 015A_03923_131313 >> $BATCH_CACHE_DIR/volc/allframes.tmp
echo 088A_03925_131313 >> $BATCH_CACHE_DIR/volc/allframes.tmp
echo 139D_04017_131313 >> $BATCH_CACHE_DIR/volc/allframes.tmp

#let's update also turkey frames..
#cat /gws/nopw/j04/nceo_geohazards_vol1/projects/LiCS/turkey_frames.txt >> $BATCH_CACHE_DIR/volc/allframes.tmp

sed -i 's/000D_/175D_/' $BATCH_CACHE_DIR/volc/allframes.tmp
sed -i 's/000A_/175A_/' $BATCH_CACHE_DIR/volc/allframes.tmp
sed -i '/014A_04939_131313/d' $BATCH_CACHE_DIR/volc/allframes.tmp
#sort -u $BATCH_CACHE_DIR/volc/allframes.tmp >  $BATCH_CACHE_DIR/volc/allframes.txt
#if to start from 175-->1
sort -u -r $BATCH_CACHE_DIR/volc/allframes.tmp >  $BATCH_CACHE_DIR/volc/allframes.txt

rm $BATCH_CACHE_DIR/volc/allframes.tmp

totalno=`wc -l $BATCH_CACHE_DIR/volc/allframes.txt | gawk {'print $1'}`
echo "there are "`wc -l $BATCH_CACHE_DIR/volc/allframes.txt`" frames to update"


#volcdir=/gws/nopw/j04/nceo_geohazards_vol1/projects/LiCS/proc/current/../../volc-proc/current

#for country in `ls $volcdir`; do
#for country in europe southeast_asia south_america northern_asia eastern_asia central_america pacific_island africa oceania north_america atlantic_island; do

i=0
for frame in `cat $BATCH_CACHE_DIR/volc/allframes.txt`; do
 let i=$i+1
 echo "Processing frame no. "$i"/"$totalno" (frame "$frame"):"
 date
 #getting the last 4th image date in a row, in order to save decompressing of not needed data
 tr=`echo $frame | cut -d '_' -f1 | cut -c -3 | sed 's/^0//' | sed 's/^0//'`
 master=`ls $LiCSAR_procdir/$tr/$frame/SLC | head -n1`
 ls $LiCSAR_procdir/$tr/$frame/RSLC | cut -d '.' -f1 > tmp_volc
 sed -i '/'$master'/d' tmp_volc
 #startdate=`tail -n4 tmp_volc | head -n1`
 #er... let's have only last 3 images....
 startdate=`tail -n3 tmp_volc | head -n1`
 maybesd=`date -d '3 months ago' +%Y%m%d`
 if [ -z $startdate ]; then
  startdate=`date -d '3 months ago' +%Y-%m-%d`
 else
  if [ $maybesd -gt $startdate ]; then
   startdate=`date -d '3 months ago' +%Y-%m-%d`
  else
   startdate=`date -d $startdate +%Y-%m-%d`
  fi
 fi
# maybesd=`date -d '3 months ago' +%Y-%m-%d`
#if [ $startdate]
 #licsar_make_frame.sh -S $frame 0 1 `date -d '3 months ago' +%Y-%m-%d` `date  +%Y-%m-%d` >$BATCH_CACHE_DIR/volc/auto_volc_$frame.log 2>$BATCH_CACHE_DIR/volc/auto_volc_$frame.err
 licsar_make_frame.sh -S -N $frame 0 1 $startdate `date  +%Y-%m-%d` >$BATCH_CACHE_DIR/volc/auto_volc_$frame.log 2>$BATCH_CACHE_DIR/volc/auto_volc_$frame.err
 #echo "waiting 30 minutes before starting another frame.."
 #sleep 1800
# echo "waiting 20 minutes before starting another frame.."
# sleep 1200
done

#echo "Processing volcano frames over country "$country
#for x in `ls $volcdir/$country`; do
# a=`echo $x | rev`; tri=`echo $a | cut -d '_' -f1 | rev`; dva=`echo $a | cut -d '_' -f2 | rev`; jedna=`echo $a | cut -d '_' -f3 | rev`; 
# echo "establishing automatic processing over the frame "$jedna'_'$dva'_'$tri
# licsar_make_frame.sh -c -S $jedna'_'$dva'_'$tri 0 0  `date -d '3 months ago' +%Y-%m-%d` `date  +%Y-%m-%d` >>$BATCH_CACHE_DIR/auto_volc.log 2>>$BATCH_CACHE_DIR/auto_volc.err
# echo "waiting one hour before starting another one"
# sleep 3600
#done

#numsec=40000
#numsec=6000
#echo "volcanoes over country "$country" are updated. Giving some time of "`echo $numsec/60/60 | bc`" hours before starting another one"
#sleep $numsec
#echo "now we have following disk space:"
#pan_df -h /work/scratch
#pan_df -h /work/scratch-nompiio
#pan_df -h /gws/nopw/j04/nceo_geohazards_vol1
#pan_df -h /gws/nopw/j04/nceo_geohazards_vol2

#done
