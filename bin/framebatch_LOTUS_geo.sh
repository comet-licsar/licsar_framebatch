###### following lines should be started in LOTUS... and in the frame directory:
NOPAR=$1

#second parameter is for whether to do full res previews as well or not
if [ ! -z $2 ]; then
 #FULL=1
 extracmd='-F'
else
 #FULL=0
 extracmd=''
fi
#echo "./tmp_geocmd_\${LSF_PM_TASKID}.sh" > tmp_geocmd.sh
#chmod 777 tmp_geocmd.sh

mkdir GEOC 2>/dev/null
#getting list of files to geocode:
rm -f tmp_to_pub 2>/dev/null
for ifg in `ls IFG/*_* -d | rev | cut -d '/' -f1 | rev`; do
if [ ! -f GEOC/$ifg/$ifg.geo.unw.tif ]; then
 if [ -f IFG/$ifg/$ifg.unw ]; then
  echo $ifg >> tmp_to_pub
 fi
fi
done

#now i need to distribute the list of files to process to $NOPAR files:
total=`wc -l tmp_to_pub | gawk {'print $1'}`
if [ -z $total ]; then
 echo "no new interferograms finished their unwrapping, cancelling now"
 exit
fi

#this simple way we get full number of ifgs per job and the rest will be filled afterwards
let ifgperjob=$total/$NOPAR
for i in `seq $NOPAR`; do
 #let tmpifgstart=($i-1)*$ifgperjob+1
 let tmpifgstop=$i*$ifgperjob
 head -n $tmpifgstop tmp_to_pub | tail -n $ifgperjob > tmp_to_pub_$i
done
let resttotal=$total-$tmpifgstop
if [ $resttotal -gt 0 ]; then
 for rest in `seq $resttotal`; do
  tail -n -$rest tmp_to_pub | head -n1 >> tmp_to_pub_$rest
 done
fi

#and prepare scripts to process in each computing node:
for i in `seq 1 $NOPAR`; do
cat << EOF > tmp_geocmd_$i'.sh'
for ifg in \`cat tmp_to_pub_$i\`; do
 create_geoctiffs_to_pub.sh $extracmd -a -u \`pwd\` \$ifg
done
EOF
done



chmod 777 tmp_geocmd*

#echo bsub -q cpom-comet -n $NOPAR blaunch ./tmp_geocmd.sh
#echo -n $NOPAR blaunch ./tmp_geocmd.sh

#this was in case of PBS:
#now starting the blaunch
#blaunch ./tmp_geocmd.sh

rm framebatch_geocode_script.sh 2>/dev/null
touch framebatch_geocode_script.sh
for script in `ls tmp_geocmd_*`; do
 echo "./"$script >> framebatch_geocode_script.sh
done
chmod 777 framebatch_geocode_script.sh
parallel --jobs $NOPAR < framebatch_geocode_script.sh
#./framebatch_geocode_script.sh

#additionally process MLIs - without parallelisation

for ifg in `cat tmp_to_pub_*`; do
 create_geoctiffs_to_pub.sh $extracmd -M `pwd` $ifg
done


#mv tmp_geocmd.sh framebatch_geocode_script.sh
