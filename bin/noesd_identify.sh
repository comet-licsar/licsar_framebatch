for log in `ls log/coreg_qual*`; do
#echo "checking "$log
if [ `wc -l $log | gawk {'print $1'}` -gt 1 ]; then
#echo "file is ok, checking if at least 2 iterations were done"
if [ `grep -c az_ovr_iteration_2 $log` -eq 0 ]; then
#the condition below means that we use the updated (hopefully fixed) approach:
#echo "yes. so check the version of log"
if [ `grep -c "iteration was ignored" $log` -eq 0 ]; then
#echo "it is not the newest version"
 rslc=`echo $log | cut -d '_' -f4 | cut -d '.' -f1`
 val1=`grep intensity_matching $log | head -n1 | gawk {'print $2'} | cut -c -7`
 val2=`grep 'Total azimuth offset' $log | tail -n1 | gawk {'print $9'} | cut -c -7`
#echo "got needed values"
 if [ $val1 == $val2 ]; then
 echo $rslc' has no ESD correction and must be recomputed';
 #if [ `grep -c 'near RSLC' $log` -gt 0 ]; then third=`grep ' near RSLC' $log | rev | gawk {'print $1'} | rev`; echo this RSLC was used for ESD: $third; fi
 for ulog in `ls log/coreg_qual*`; do
  if [ `grep -c $rslc $ulog` -gt 0 ]; then
    affected=`echo $ulog | cut -d '.' -f1 | rev | cut -d '_' -f1 | rev`
    if [ ! $affected == $rslc ]; then
      echo "unfortunately this RSLC is also affected by noESD here: "$affected
      for glog in `ls log/coreg_qual*`; do
       if [ `grep -c $affected $glog` -gt 0 ]; then
       affected2=`echo $glog | cut -d '.' -f1 | rev | cut -d '_' -f1 | rev`
       if [ ! $affected == $affected2 ]; then
        echo "unfortunately this RSLC is also affected by noESD here: "$affected2
#        echo "(check manually if the error propagates from this image as well)"
         for blog in `ls log/coreg_qual*`; do
          if [ `grep -c $affected2 $blog` -gt 0 ]; then
           affected3=`echo $blog | cut -d '.' -f1 | rev | cut -d '_' -f1 | rev`
           if [ ! $affected3 == $affected2 ]; then
           echo "unfortunately this RSLC is also affected by noESD here: "$affected3

            for klog in `ls log/coreg_qual*`; do
             if [ `grep -c $affected3 $klog` -gt 0 ]; then
               affected4=`echo $klog | cut -d '.' -f1 | rev | cut -d '_' -f1 | rev`
              if [ ! $affected4 == $affected3 ]; then
               echo "unfortunately this RSLC is also affected by noESD here: "$affected4

                 for llog in `ls log/coreg_qual*`; do
                  if [ `grep -c $affected4 $llog` -gt 0 ]; then
                   affected5=`echo $blog | cut -d '.' -f1 | rev | cut -d '_' -f1 | rev`
                   if [ ! $affected5 == $affected4 ]; then
                   echo "unfortunately this RSLC is also affected by noESD here: "$affected5
                   echo "(check manually if the error propagates from this image as well)"
                  fi; fi
                 done
              fi; fi
             done
          fi; fi
         done
       fi
       fi
      done
    fi
  fi
 done
 fi
fi
fi
fi
done
