#!/usr/bin/env python
#ML 2021
import sys, os
import LiCSAR_lib.LiCSAR_misc as misc
import LiCSquery as lq


'''

these lines are for AGU Meeting

import time
fullcount = len(esds)
orb='fixed_as_in_GRL'
for i,row in esds.iterrows():
    daz=row['daz_total_wrt_orbits']
    ccazi=row['daz_cc_wrt_orbits']
    print(str(i)+'/'+str(fullcount))
    rslc3=row['esd_master']
    frame=row['frame']
    epoch=row['epoch']
    try:
        polyid = lq.sqlout2list(lq.get_frame_polyid(frame))[0]
    except:
        continue
    aa = get_daz(polyid, epoch, getall = True)
    if 'ORB' in aa[3]:
        print('new version exists, skipping - value diff is: '+str(aa[-3]-daz))
        continue
    try:
        ccrg=row['drg_wrt_orbits']
    except:
        ccrg = aa[-1]
        if not ccrg:
            ccrg = 0.0
    # so now updating the value here
    rc = lq.ingest_esd(frame, epoch, rslc3, daz, ccazi, ccrg, orb, overwrite = True)
    time.sleep(0.1)


# or:
    #if not np.isclose(get_daz(polyid, epoch), daz):
    aa = lq.get_daz(polyid, epoch, getall = True)
    if (not aa[3]) or (aa[5]==0) or (aa[6]==0):
        print('reingesting')
        rc = lq.ingest_esd(frame, epoch, rslc3, daz, ccazi, ccrg, orb, overwrite = True)


#if [ ! -d $tr/$fr/SLC ]; then echo $fr; rm -rf $tr/$fr; rm -r $LiCSAR_public/$tr/$fr 2>/dev/null; fi; 

for tr in `seq 1 175`; do for fr in `ls $tr`; do

m=`ls $tr/$fr/SLC | grep ^20 | head -n1 | cut -d '.' -f1`
if [ $m -gt 20200729 ]; then
 zipf=`ls $tr/$fr/SLC/$m/S1*zip -d | head -n1`
 cdate=`stat $zipf | grep Modify | gawk {'print $2'} | sed 's/-//g'`
 if [ $cdate -lt 20210614 ]; then
  echo $fr
 fi
fi
done; done


'''

for tr in `seq 1 175`; do for fr in `ls $tr`; do

m=`ls $tr/$fr/SLC | grep ^20 | head -n1 | cut -d '.' -f1`
if [ $m -gt 20200729 ]; then
 zipf=`ls $tr/$fr/SLC/$m/S1*zip -d | head -n1`
 cdate=`stat $zipf | grep Modify | gawk {'print $2'} | sed 's/-//g'`
 if [ $cdate -lt 20210614 ]; then
  echo $fr
 fi
fi
done; done






frame=sys.argv[1]
logfile=sys.argv[2]

epoch = os.path.basename(logfile).split('.')[0].split('_')[-1]
master = os.path.basename(logfile).split('.')[0].split('_')[-2]

#getting SD value - note that this is w.r.t. LUT - and LUT was generated from orbits (rdc_trans) and after ICC
esd = float(misc.grep1line('Total azimuth offset', logfile).split(':')[1].split('(')[0])

# getting info about intensity cross correlation (ICC) daz/dr from the log file
ccazis = misc.grep_full('daz = ', logfile)
ccazi = 0.0
for ccl in ccazis:
    ccazi = ccazi+float(ccl.split()[2])

ccrgs = misc.grep_full('dr = ', logfile)
ccrg = 0.0
for ccl in ccrgs:
    ccrg = ccrg+float(ccl.split()[2])
'''
keyword='matching_iteration_'
match_it=`grep -c $keyword $c`
let no=$match_it/2
if [ $match_it -eq 0 ]; then
 #another version without '_'
 keyword='matching iteration '

cc=`grep "intensity_matching" $c | head -n1 | cut -d ':' -f2 | gawk {'print $1'}`
 ver=i

'''
#now daz is SD shift + ICC shift in azimuth
daz = esd + ccazi

rslc3 = misc.grep1line('Spectral diversity estimation',logfile).split(':')[-1]
if not rslc3:
    rslc3 = master
else:
    rslc3=rslc3.strip()

# get applied orbit file (if possible)
orblogfile = os.path.join(os.path.dirname(logfile),'getValidOrbFile_{}.log'.format(epoch))
if os.path.exists(orblogfile):
    try:
        orb = misc.grep1line('POEORB',orblogfile).split()[-1]
    except:
        orb = ''
    if not orb:
        try:
            orb = misc.grep1line('RESORB',orblogfile).split()[-1]
        except:
            orb = ''
else:
    orb = ''

#now just write the information to LiCSInfo db
print('Epoch {0} through {1}: daz={2} px'.format(epoch, rslc3, str(daz)))

rc = lq.ingest_esd(frame, epoch, rslc3, daz, ccazi, ccrg, orb)
