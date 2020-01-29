###### following lines should be started in LOTUS... and in the frame directory:
NOPAR=$1

echo "./tmp_geocmd_\${LSF_PM_TASKID}.sh" > tmp_geocmd.sh
chmod 777 tmp_geocmd.sh

mkdir GEOC 2>/dev/null
#getting list of files to geocode:
rm -f tmp_to_pub 2>/dev/null
for ifg in `ls IFG/*_* -d | rev | cut -d '/' -f1 | rev`; do
 if [ -f IFG/$ifg/$ifg.unw ]; then
  echo $ifg >> tmp_to_pub
 fi
done

#now i need to distribute the list of files to process to $NOPAR files:
total=`wc -l tmp_to_pub | gawk {'print $1'}`
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
 create_geoctiffs_to_pub.sh \`pwd\` \$ifg
done
EOF
done

chmod 777 tmp_geocmd_*

#echo bsub -q cpom-comet -n $NOPAR blaunch ./tmp_geocmd.sh
#echo -n $NOPAR blaunch ./tmp_geocmd.sh

#now starting the blaunch
blaunch ./tmp_geocmd.sh
