#!/usr/bin/env python

# in case the requested dataset is not connected within 180 days..:

continue_anyway = True

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
print('debug:')
print('polyid is: '+str(polyid))
print('mstrDate is: '+str(mstrDate))
masterset = set_master(polyid,mstrDate)

acq_imgs = add_acq_images(polyid, startdate.date(), enddate.date(), mstrDate.date())
#acq_imgs will now contain at least the master epoch
if len(acq_imgs)<2:
    print('No acquisitions registered for this frame in this time period. Try framebatch_data_refill.sh first?')
    exit()


acq_imgs = acq_imgs.sort_values('acq_date').reset_index(drop=True)
mstrline = acq_imgs[acq_imgs['acq_date']==mstrDate]
acq_imgs['btemp'] = acq_imgs.acq_date.apply(lambda x: abs(x - mstrDate)) #mstrline['acq_date']))
acq_imgs = acq_imgs.sort_values('btemp')

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

#get available LUTs - needed for RSLCs if longer than 6 months..
track=str(int(frame[:3]))
try:
    existing_luts = fnmatch.filter(os.listdir(os.path.join(srcDir,track,frame,'LUT')), '20*')
    def rpl(x): return x.replace('.7z','')
    existing_luts = list(map(rpl,existing_luts))
    existing_luts.sort()
except:
    existing_luts = []

# if the closest epoch to the master is >6 months, then check if it has lut. if not, then find file with closest lut (or in existing_ lists) and update the start/end date
rlsc3_limit = 180
if min(abs(acq_imgs.btemp)).days > rlsc3_limit:
    possible_acqs = existing_acq + existing_acq_lics + existing_luts
    possible_acqs = list(set(possible_acqs))
    def todt(x): return pd.Timestamp(x)
    try:
        possible_acqs_dt = list(map(todt,possible_acqs))
    except:
        possible_acqs_dt = []
    isinposs = False
    for x in acq_imgs.acq_date.values:
        if not isinposs:
            if x in possible_acqs_dt:
                isinposs = True
    if not isinposs:
        # need to change the dates:
        print('WARNING: the dates did not contain Btemp connection towards the frame. Updating the dates')
        print('will not start until this is fixed')
        # if it is empty, we need to choose some closer to master:
        if not possible_acqs_dt:
            fromstart = (startdate - mstrDate).days
            fromend = (enddate - mstrDate).days
            tdelta_limit = rlsc3_limit - 25  # will include few more - at least two
            td = pd.Timedelta(days=tdelta_limit)
            if fromstart < fromend:
                startdate = mstrDate + td
                print('updated startdate = '+startdate.strftime('%Y-%m-%d'))
            else:
                enddate = mstrDate - td
                print('updated enddate = ' +enddate.strftime('%Y-%m-%d'))
        else:
            pomfirst = acq_imgs['acq_date'].sort_values().values[0]
            pomlast = acq_imgs['acq_date'].sort_values().values[-1]
            possible_acqs_pd = pd.DataFrame(possible_acqs_dt)
            possible_acqs_pd = possible_acqs_pd.sort_values(0)
            pomfirstlen = min(abs(pomfirst - possible_acqs_pd[0]))
            pomlastlen = min(abs(pomlast - possible_acqs_pd[0]))
            if pomfirstlen < pomlastlen:
                possible_acqs_pd['btemp'] = abs(pomfirst - possible_acqs_pd[0])
                # also adding a bit longer time
                startdate = (possible_acqs_pd.sort_values('btemp').iloc[0][0] - pd.Timedelta(days=25)).to_pydatetime()
                print('updated startdate = ' +startdate.strftime('%Y-%m-%d'))
            else:
                possible_acqs_pd['btemp'] = abs(pomlast - possible_acqs_pd[0])
                enddate = (possible_acqs_pd.sort_values('btemp').iloc[0][0] + pd.Timedelta(days=25)).to_pydatetime()
                print('updated enddate = '+enddate.strftime('%Y-%m-%d'))
        print('please rerun with the new dates')
        if not continue_anyway:
            exit()
        # repeat the acq_images adding - not the best as it expects ingested data - thus will do this twice, see licsar_make_frame.sh
        #acq_imgs = add_acq_images(polyid, startdate.date(), enddate.date(), mstrDate.date())
        #acq_imgs = acq_imgs.sort_values('acq_date').reset_index(drop=True)
        #mstrline = acq_imgs[acq_imgs['acq_date']==mstrDate]
        #acq_imgs['btemp'] = acq_imgs.acq_date.apply(lambda x: abs(x - mstrDate)) #mstrline['acq_date']))
        #acq_imgs = acq_imgs.sort_values('btemp')
        #acq_imgs = acq_imgs[acq_imgs['acq_date']!=mstrDate]


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

existing_rslcids = []
if rslcids.rslc_id.count():
    for acq in existing_acq:
        if dt.datetime.strptime(acq,'%Y%m%d').date() in rslcids.acq_date.dt.date.tolist():
            rslcID=int(rslcids[rslcids.acq_date == dt.datetime.strptime(acq,'%Y%m%d')].rslc_id)
            set_rslc_status(rslcID,0)
            existing_rslcids.append(rslcID)
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
#ok, first sort rslcs w.r.t. master:
aa = acq_imgs.join(rslcs.set_index('img_id'), on='img_id')
for exrs in existing_rslcids:
    aa = aa[aa['rslc_id'] != exrs]
#.join(
#            rslcids.rename(columns={"acq_date": "rslc_date"}).set_index('rslc_id'), on='rslc_id')
#            rslcids.set_index('img_id'), on='img_id')
rslcs = aa[['rslc_id']].reset_index(drop=True)
batch_link_rslcs_to_new_jobs(polyid,user,rslcs,batchN)
batch_link_ifgs_to_new_jobs(polyid,user,ifgs,batchN)
batch_link_unws_to_new_jobs(polyid,user,unws,batchN)

