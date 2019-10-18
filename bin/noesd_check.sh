frame=$1
#framelog=$frame.log
#noesd_identify.sh > $framelog
framelog=$1
frame=`echo $framelog | cut -d '.' -f1`
track=`echo $frame | cut -c -3 | sed 's/^0//' | sed 's/^0//'`

grep -B1 manually $framelog
gawk {'print $1'} $framelog > $framelog.tmp1.log
gawk {'print $10'} $framelog >> $framelog.tmp1.log
sort -nu $framelog.tmp1.log | grep 20 > $frame.bad
rm $framelog.tmp1.log

for x in `cat $frame.bad`; do
 ls $LiCSAR_public/$track/$frame/products/*$x*/*diff.png >> $frame.pngs
done
