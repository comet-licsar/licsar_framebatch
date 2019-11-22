cd $LiCSAR_procdir
for track in `seq 0 175`; do
 for frame in `ls $track`; do
  echo $frame
  geofile=`ls $track/$frame/geo/*.EQA.dem.grd | head -n1 2>/dev/null`
  degfile=`ls $track/$frame/geo/*.geo.deg.inc.grd | head -n1 2>/dev/null`
  if [ -f $geofile ]; then
   gdal_translate -of GTiff -ot Float32 -co COMPRESS=LZW -co PREDICTOR=3 $geofile $LiCSAR_public/$track/$frame/metadata/$frame.geo.hgt.tif
   gdal_translate -of GTiff -ot Float32 -co COMPRESS=LZW -co PREDICTOR=3 $degfile $LiCSAR_public/$track/$frame/metadata/$frame.geo.inc.tif
  fi
 done
done

