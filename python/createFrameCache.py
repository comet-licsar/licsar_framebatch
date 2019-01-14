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
                    batch_link_unws_to_new_jobs
from batchEnvLib import create_lics_cache_dir
import sys
import datetime as dt
import os

################################################################################
#get parameters
################################################################################
frame = sys.argv[1]
batchN = int(sys.argv[2])
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
rslcDir = os.path.join(cacheDir,frame,'RSLC')
dateStr = os.listdir(rslcDir)[0]
mstrDate = dt.datetime.strptime(dateStr,'%Y%m%d')

################################################################################
#setup database for processing
################################################################################
polyid = get_polyid(frame)
acq_imgs = add_acq_images(polyid)
set_master(polyid,mstrDate)
acq_imgs = acq_imgs[acq_imgs['acq_date']!=mstrDate]

slcs = create_slcs(polyid,acq_imgs)
rslcs = create_rslcs(polyid,acq_imgs)
ifgs = create_ifgs(polyid,acq_imgs)
unws = create_unws(polyid,acq_imgs)

batch_link_slcs_to_new_jobs(polyid,user,slcs,batchN)
batch_link_rslcs_to_new_jobs(polyid,user,rslcs,batchN)
batch_link_ifgs_to_new_jobs(polyid,user,ifgs,batchN)
batch_link_unws_to_new_jobs(polyid,user,unws,batchN)
