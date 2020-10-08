#!/bin/bash
work_dir="/gws/nopw/j04/nceo_geohazards_vol2/LiCS/temp/GACOS"

if [ -z $1 ]; then
 echo "parameter is just a frame";
 exit; fi

frame=$1
maxwaithours=168

cd $work_dir
#check for writing rights
touch pokuspokusgacos_$frame
if [ ! -f pokuspokusgacos_$frame ]; then echo "you do not have writing rights here, cancelling"; exit; fi
rm pokuspokusgacos_$frame

if [ ! -d $frame ]; then
 mkdir $frame 2>/dev/null
else
 echo "the frame is already in processing??"
 echo "check (and delete?)"$work_dir"/"$frame
 exit
fi
#track=`echo $frame | cut -c -3 | sed 's/^0//' | sed 's/^0//'`

#create input file
gacos_input_creator.sh $frame

if [ ! -f $frame.inp ]; then
 echo "some error in creating input"
 exit
fi

#use input file to request gacos data
gacosapi.sh $frame.inp

if [ ! -f $frame.tar.gz ]; then
 echo "some error in getting GACOS corrections"
 exit
fi

#now decompress the files
mkdir $frame 2>/dev/null
mv $frame.tar.gz $frame/.
cd $frame
tar -xzf $frame.tar.gz
cd ..

#maybe it works like this?
#archive gacos data to LiCSAR_public
gacos_archive_to_portal.sh $frame

echo "done, cleaning"
cd $work_dir
rm -r $frame $frame.tar.gz $frame.inp

exit








#an older attempt below



#wait for gacos data to appear
    pom=0
    hours=-1
    while [ $pom == 0 ]; do
      let hours=$hours+1
      echo "waiting for GACOS server to finish: "$hours" hours"
      sleep 3600
      pom=1
      for request in `grep "Created request" temp_nla.$frame | gawk {'print $3'}`; do
        if [ `nla.py req $request | grep Status | grep -c "On disk"` -eq 0 ];
          then pom=0
        fi
      done
      if [ $hours -gt $maxwaithours ]; then
           echo "enough waiting, GACOS didnt work fully"
           pom=1
      fi
    done

#archive gacos data to LiCSAR_public
gacos_archive_to_portal.sh $frame
