#!/usr/bin/env python

################################################################################
#imports
################################################################################
from configLib import config
from batchDBLib import get_polyid,set_master,add_acq_images,\
                    create_slcs,create_rslcs,create_ifgs,create_unws,\
                    batch_link_slcs_to_new_jobs,\
                    batch_link_rslcs_to_new_jobs,\
                    batch_link_ifgs_to_new_jobs,\
                    batch_link_unws_to_new_jobs,\
                    get_all_rslcs,set_rslc_status,\
                    get_all_slcs,set_slc_status
from batchEnvLib import create_lics_cache_dir, get_rslcs_from_lics
import sys
import datetime as dt
import os
import glob
import fnmatch

################################################################################
#get parameters
################################################################################
frame = sys.argv[1]
batchN = int(sys.argv[2])

#something extra - assuming that 3rd argument would be starting date:
if len(sys.argv) > 3:
    startdate = str(sys.argv[3])
    startdate = dt.datetime.strptime(startdate,'%Y-%m-%d')

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
acq_imgs = add_acq_images(polyid)
set_master(polyid,mstrDate)
acq_imgs = acq_imgs[acq_imgs['acq_date']!=mstrDate]
#start from startingdate
if startdate:
    acq_imgs = acq_imgs[acq_imgs['acq_date']>startdate]

#remove existing rslc dates from the list 
#(only for make_img list since rslcs should be used further for ifgs)
existing_acq = get_rslcs_from_lics(frame,srcDir,cacheDir,dateStr)
acq_imgs2 = acq_imgs
for r in existing_acq:
    acq_imgs2 = acq_imgs2[acq_imgs2.acq_date != dt.datetime.strptime(r,'%Y%m%d')]

slcs = create_slcs(polyid,acq_imgs2)
rslcs = create_rslcs(polyid,acq_imgs)
#
#for all rslcs and slcs that already exist in current, make them set 'done'
rslcids=get_all_rslcs(polyid)
slcids=get_all_slcs(polyid)

#exclude also RSLCs existing in the RSLC processing directory
existing_acq.append(fnmatch.filter(os.listdir(cacheDir+'/'+frame+'/RSLC'), '20??????'))
if rslcids.rslc_id.count():
    for acq in existing_acq:
        if dt.datetime.strptime(acq,'%Y%m%d').date() in rslcids.acq_date.dt.date.tolist():
            rslcID=int(rslcids[rslcids.acq_date == dt.datetime.strptime(acq,'%Y%m%d')].rslc_id)
            set_rslc_status(rslcID,0)
            try:
                slcID=int(slcids[slcids.acq_date == dt.datetime.strptime(acq,'%Y%m%d')].slc_id)
            try:
                set_slc_status(slcID,0)

ifgs = create_ifgs(polyid,acq_imgs)
unws = create_unws(polyid,acq_imgs)


batch_link_slcs_to_new_jobs(polyid,user,slcs,batchN)
#the rslcs job linking should be improved, but it is ok this way..
batch_link_rslcs_to_new_jobs(polyid,user,rslcs,batchN)
batch_link_ifgs_to_new_jobs(polyid,user,ifgs,batchN)
batch_link_unws_to_new_jobs(polyid,user,unws,batchN)

