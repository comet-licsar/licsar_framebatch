#!/bin/bash
thisDir=`pwd`
if [ ! `basename $thisDir` == 'LOGS' ]; then echo "you have to run this script inside your LOGS folder"; exit; fi
if [ ! -f badrslcs.txt ]; then
 echo "you need to manually identify wrong RSLCs"
 echo "and write their list to LOGS/badrslcs.txt file"
 echo "with contents as e.g.:"
 echo "20160331"
 echo "20161108"
 echo "etc."
 exit
fi

#for badrslc in 20160331 20161108 20180824 20181110 20181029 20181017 20180806 20180219 20180303 20170519 20170612 20170425 20161102 20161202 20161120; do
for badrslc in `cat badrslcs.txt`; do
 baddate=`echo ${badrslc:0:4}-${badrslc:4:2}-${badrslc:6:2}`
 echo "slc "$badrslc" was used for ESD estimation of following files:";
 for file in `ls framebatch_02_coreg_*out`; do 
  grep "found potential aux slave date "$baddate -B4 $file | grep "Coregistering";
 done
 echo "for coregistering this slc "$badrslc", following file was used for its ESD estimation:";
 SL=""; SLF=""
 for file in `ls framebatch_02_coreg_*out`; do 
  SL=`grep "Coregistering slave "$baddate -A4 $file | grep "found potential aux slave date" | rev | gawk {'print $2'} | rev`
  if [ ! -z $SL ]; then echo $SL; SLF=$SL; fi
 done
 if [ -z $SLF ]; then echo -e "\033[33;7mfile "$badrslc" has been ESD-corrected directly to master - SEED\033[0m"; fi
 echo "----"
done
