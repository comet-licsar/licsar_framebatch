#!/usr/bin/env python
#ML 2021
import sys, os
import LiCSAR_lib.LiCSAR_misc as misc
import LiCSquery as lq

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

#now daz is SD shift + ICC shift in azimuth
daz = esd + ccazi

rslc3 = misc.grep1line('Spectral diversity destimation',logfile).split(':')[-1]
if not rslc3:
    rslc3 = master


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
