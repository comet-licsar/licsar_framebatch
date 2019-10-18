#!/bin/bash
#input is txt file with 'bad dates'. the txt filename should be FRAME.whatever
#all data connected to these 'bad dates' will be removed from both $LiCSAR_public and $LiCSAR_procdir

framebad=$1

frame=`echo $framebad | cut -d '.' -f1`
track=`echo $frame | cut -c -3 | sed 's/^0//' | sed 's/^0//'`

pubdir=$LiCSAR_public/$track/$frame/products
procdir=$LiCSAR_procdir/$track/$frame


for badrslc in `cat $framebad`; do

 echo "deleting "$badrslc
 echo `ls $pubdir/*$badrslc* -d | wc -l`" folders in pubdir"

 #clean from public
 for dir in `ls $pubdir/*$badrslc* -d 2>/dev/null`; do 
  #echo $dir #>> $frame.tocopy
  rm -rf $dir 2>/dev/null
 done

 echo `ls $procdir/*/*$badrslc* -d | wc -l`" files in procdir"

 #clean from procdir
 for this in `ls $procdir/*/*$badrslc* -d 2>/dev/null`; do
  #echo $this
  rm -rf $this 2>/dev/null
 done

done

startdate=`head -n1 $framebad`
enddate=`tail -n1 $framebad`

echo LiCSAR_0_getFiles.py -f $frame -s `date -d $startdate" -13 days" +%Y-%m-%d` -e `date -d $enddate" +13 days" +%Y-%m-%d` -r
echo licsar_make_frame.sh -S -f $frame 1 1 `date -d $startdate" -13 days" +%Y-%m-%d` `date -d $enddate" +13 days" +%Y-%m-%d`
