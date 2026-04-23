#!/bin/bash
if [ -z $1 ]; then
  echo "provide frame param"
  exit
fi
fr=$1
if [ -d $fr ]; then echo "run this in a subfolder with your frame folder"; exit; fi


echo "restoring missing frame core files from procdir"
tr=`track_from_frame $fr`
for fld in geo SLC RSLC tab; do
  rsync -r $LiCSAR_procdir/$tr/$fr/$fld $fr 2>/dev/null
done
cp $LiCSAR_procdir/$tr/$fr/local_config.py $fr/. 2>/dev/null

# mosaic
bdir=`pwd`
cd $fr
m=`get_master`
rlks=20
azlks=4
source local_config.py 2>/dev/null # would load lks if different
echo "regenerating missing mosaics and cleaning incomplete (R)SLCs"
if [ ! -s SLC/$m/$m.slc ]; then
 createSLCtab_frame `pwd`/SLC/$m/$m slc $fr > tab/$m'_tab'
 SLC_mosaic_ScanSAR tab/$m'_tab' SLC/$m/$m.slc SLC/$m/$m.slc.par $rlks $azlks - -  >/dev/null 2>/dev/null
fi
if [ ! -s SLC/$m/$m.slc ]; then echo "some error with the frame "$fr" - cancelling and moving todelete";
  cd $bdir; mkdir -p todelete; mv $fr todelete/.; exit;
fi
for sc in SLC RSLC; do
 mkdir -p $sc.backup
 scstr=`echo $sc | tr [:upper:] [:lower:]`
 if [ $sc == 'SLC' ]; then sct=''; else sct='R'; fi
 for r in `ls $sc`; do
  if [ ! -s $sc/$r/$r.$scstr ]; then
    # try regen
    createSLCtab_frame `pwd`/$sc/$r/$r $scstr $fr > tab/$r$sct'_tab'
    SLC_mosaic_ScanSAR tab/$r$sct'_tab' $sc/$r/$r.$scstr $sc/$r/$r.$scstr.par $rlks $azlks - tab/$m'_tab' >/dev/null 2>/dev/null
  fi
  if [ ! -s $sc/$r/$r.$scstr ]; then
   echo "probably missing data of "$r" - moving to "$sc".backup"
    mv $sc/$r $sc.backup/.
  fi
 done
done
cd $bdir