if [ ! -f lack_png.list.temp ]; then echo "do what you have to do"; exit; fi
#instructions:
#have following lines in your lack_png.list.temp file:
#080D_05003_131312-20170528_20170603.geo.unw.png

#for line in `sed 's/ /-/' lack_png.list`; do 
pom=0
total=`wc -l lack_png.list.temp | gawk {'print $1'}`
for line in `cat lack_png.list.temp`; do 
 let pom=$pom+1
 echo "processing missing png problem: "$pom" of "$total
 frame=`echo $line | cut -d '-' -f1`
 track=`echo $frame | cut -c -3 | sed 's/^0//' | sed 's/^0//'`
 file=`echo $line | cut -d '-' -f2`
 ifg=`echo $file | cut -d '.' -f1`
 path=$LiCSAR_public/$track/$frame/products/$ifg
 bmpfile=`echo $file | sed 's/.png/.bmp/'`
#sometimes just bmp file exists
 if [ -f $path/$bmpfile ]; then
  echo "converting "$bmpfile
  convert $path/$bmpfile $path/$file
  if [ -f $path/$file ]; then 
   stillbad=0
   rm $path/$bmpfile
  fi
 else
  stillbad=1
 fi
 if [ -f $path/$file ]; then 
  stillbad=0
 fi
#in case of noBMPs, we will need to regenerate the geotiffs...
 if [ $stillbad -eq 1 ]; then 
  create_geoctiffs_to_pub.sh $LiCSAR_procdir/$track/$frame $ifg
  #now move generated files - first amplitudes
  for img in `ls $LiCSAR_procdir/$track/$frame/GEOC.MLI`; do
   if [ `ls $LiCSAR_procdir/$track/$frame/GEOC.MLI/$img/$img.geo.mli.png 2>/dev/null | wc -l` -gt 0 ]; then
     mkdir -p $path/../epochs/$img
     mv $LiCSAR_procdir/$track/$frame/GEOC.MLI/$img/$img.geo.mli.png $path/../epochs/$img/.
     mv $LiCSAR_procdir/$track/$frame/GEOC.MLI/$img/$img.geo.mli.tif $path/../epochs/$img/.
   fi
  done
  rm -rf $LiCSAR_procdir/$track/$frame/GEOC.MLI
  #and also move GEOC ifg files
  mkdir -p $path
  if [ `ls $LiCSAR_procdir/$track/$frame/GEOC/$ifg/$ifg.geo.diff.png 2>/dev/null | wc -l` -gt 0 ]; then
   mv $LiCSAR_procdir/$track/$frame/GEOC/$ifg/$ifg.geo.diff.png $path/.
   mv $LiCSAR_procdir/$track/$frame/GEOC/$ifg/$ifg.geo.cc.png $path/.
   mv $LiCSAR_procdir/$track/$frame/GEOC/$ifg/$ifg.geo.diff_pha.tif $path/.
   mv $LiCSAR_procdir/$track/$frame/GEOC/$ifg/$ifg.geo.cc.tif $path/.
  fi
  if [ `ls $LiCSAR_procdir/$track/$frame/GEOC/$ifg/$ifg.geo.unw.png 2>/dev/null | wc -l` -gt 0 ]; then
   mv $LiCSAR_procdir/$track/$frame/GEOC/$ifg/$ifg.geo.unw.png $path/.
   mv $LiCSAR_procdir/$track/$frame/GEOC/$ifg/$ifg.geo.unw.tif $path/.
  fi
  rm -rf $LiCSAR_procdir/$track/$frame/GEOC/$ifg
 fi
 if [ -f $path/$file ]; then 
  stillbad=0
 fi
 if [ $stillbad -eq 1 ]; then 
  echo $line >> lack_png.list.it1
 fi
done
