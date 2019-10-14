#!/usr/bin/env python

################################################################################
#imports
################################################################################
from configLib import config
from batchDBLib import get_polyid,add_acq_images,set_master,\
                    create_slcs,create_rslcs,create_ifgs,create_unws,\
                    batch_link_slcs_to_new_jobs,\
                    batch_link_rslcs_to_new_jobs,\
                    batch_link_ifgs_to_new_jobs,\
                    batch_link_unws_to_new_jobs,\
                    get_all_rslcs,set_rslc_status,\
                    get_all_slcs,set_slc_status,\
                    get_all_ifgs,set_ifg_status,\
                    get_all_unws,set_unw_status
from batchEnvLib import create_lics_cache_dir, get_rslcs_from_lics, get_ifgs_from_lics
import sys
import datetime as dt
import os
import glob
import fnmatch
import pandas as pd

################################################################################
#get parameters
################################################################################
frame = sys.argv[1]
batchN = int(sys.argv[2])

#something extra - assuming that 3rd argument would be starting date:
startdate = dt.datetime.strptime('2014-10-01','%Y-%m-%d')
enddate = dt.datetime.now()

if len(sys.argv) > 3:
    startdate = str(sys.argv[3])
    startdate = dt.datetime.strptime(startdate,'%Y-%m-%d')
#if 4th argument is given, it will be the enddate
if len(sys.argv) > 4:
    enddate = str(sys.argv[4])
    enddate = dt.datetime.strptime(enddate,'%Y-%m-%d')

srcDir = config.get('Env','SourceDir')
try:
    cacheDir = os.environ['BATCH_CACHE_DIR']
except KeyError as error:
    print('I required you to set your cache directory using the'\
            'enviroment variable BATCH_CACHE_DIR')
    raise error
user = os.environ['USER']

################################################################################
#Create cache copy
################################################################################
print('copying frame data from licsar database')
create_lics_cache_dir(frame,srcDir,cacheDir)

################################################################################
# Get master date
################################################################################
#rslcDir = os.path.join(cacheDir,frame,'RSLC')
#dateStr = os.listdir(rslcDir)[0]
#mstrDate = dt.datetime.strptime(dateStr,'%Y%m%d')
geoDir = os.path.join(cacheDir,frame,'geo')
dateStr = glob.glob(geoDir+'/*[0-9].hgt')[0].split('/')[-1].split('.')[0]
mstrDate = dt.datetime.strptime(dateStr,'%Y%m%d')
################################################################################
#setup database for processing
################################################################################
polyid = get_polyid(frame)
acq_imgs = add_acq_images(polyid, startdate.date(), enddate.date(), mstrDate.date())
if len(acq_imgs)<2:
    print('No acquisitions registered for this frame in this time period. Try framebatch_data_refill.sh first?')
    exit
masterset = set_master(polyid,mstrDate)
mstrline = acq_imgs[acq_imgs['acq_date']==mstrDate]
acq_imgs = acq_imgs[acq_imgs['acq_date']!=mstrDate]
#start from startingdate
#if startdate:
#    acq_imgs = acq_imgs[acq_imgs['acq_date']>=startdate]
#if enddate:
#    acq_imgs = acq_imgs[acq_imgs['acq_date']<=enddate]

#remove existing rslc dates from the list 
#(only for make_img list since rslcs should be used further for ifgs)
date_strings = [dt.strftime("%Y%m%d") for dt in pd.to_datetime(acq_imgs['acq_date']).dt.date.tolist()]

#get acquisitions existing in lics db
#(this will make links and decompress the lics db files to cacheDir)
print('Getting existing RSLCs from LiCS database')
existing_acq_lics = get_rslcs_from_lics(frame,srcDir,cacheDir,date_strings)

#get final acquisitions list for those existing in the RSLC processing directory
existing_acq = fnmatch.filter(os.listdir(cacheDir+'/'+frame+'/RSLC'), '20??????')

#acq_imgs2 = acq_imgs
#for r in existing_acq:
#    acq_imgs2 = acq_imgs2[acq_imgs2.acq_date != dt.datetime.strptime(r,'%Y%m%d')]

#slcs = create_slcs(polyid,acq_imgs2)
slcs = create_slcs(polyid,acq_imgs)
rslcs = create_rslcs(polyid,acq_imgs)
#
#for all rslcs and slcs that already exist in current, make them set 'done'
rslcids = get_all_rslcs(polyid)
slcids = get_all_slcs(polyid)

if rslcids.rslc_id.count():
    for acq in existing_acq:
        if dt.datetime.strptime(acq,'%Y%m%d').date() in rslcids.acq_date.dt.date.tolist():
            rslcID=int(rslcids[rslcids.acq_date == dt.datetime.strptime(acq,'%Y%m%d')].rslc_id)
            set_rslc_status(rslcID,0)
            slcID=int(slcids[slcids.acq_date == dt.datetime.strptime(acq,'%Y%m%d')].slc_id)
            set_slc_status(slcID,0)

#avoid regenerating existing SLC files
existing_slcs = fnmatch.filter(os.listdir(cacheDir+'/'+frame+'/SLC'), '20??????')
if slcids.slc_id.count():
    for acq in existing_slcs:
        if dt.datetime.strptime(acq,'%Y%m%d').date() in slcids.acq_date.dt.date.tolist():
            slcID=int(slcids[slcids.acq_date == dt.datetime.strptime(acq,'%Y%m%d')].slc_id)
            set_slc_status(slcID,0)

#reingesting the master here
ifgs = create_ifgs(polyid,acq_imgs.append(mstrline))
unws = create_unws(polyid,acq_imgs.append(mstrline))

print('Getting existing interferograms from LiCS database')
existing_ifgs_lics = get_ifgs_from_lics(frame,srcDir,cacheDir,startdate,enddate)
existing_ifgs = fnmatch.filter(os.listdir(cacheDir+'/'+frame+'/IFG'), '20??????_20??????')
ifgids = get_all_ifgs(polyid)
unwids = get_all_unws(polyid)
for ifg in existing_ifgs:
    rslcA = ifg.split('_')[0]
    rslcB = ifg.split('_')[1]
    i = ifgids.loc[(ifgids['acq_date_1'].dt.date == dt.datetime.strptime(rslcA,'%Y%m%d').date())\
            & (ifgids['acq_date_2'].dt.date == dt.datetime.strptime(rslcB,'%Y%m%d').date()) ]
    if not i.empty:
        ifgID = int(i.ifg_id)
        set_ifg_status(ifgID,0)
        if os.path.exists(os.path.join(cacheDir,frame,'IFG',ifg,ifg+'.unw')):
            u = unwids.loc[(unwids['acq_date_1'].dt.date == dt.datetime.strptime(rslcA,'%Y%m%d').date())\
                & (unwids['acq_date_2'].dt.date == dt.datetime.strptime(rslcB,'%Y%m%d').date()) ]
            unwID = int(u.unw_id)
            set_unw_status(unwID,0)

batch_link_slcs_to_new_jobs(polyid,user,slcs,batchN)
#the rslcs job linking should be improved, but it is ok this way..
batch_link_rslcs_to_new_jobs(polyid,user,rslcs,batchN)
batch_link_ifgs_to_new_jobs(polyid,user,ifgs,batchN)
batch_link_unws_to_new_jobs(polyid,user,unws,batchN)

