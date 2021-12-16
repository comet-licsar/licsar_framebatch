#!/usr/bin/env python

################################################################################
#imports
################################################################################
import pandas as pd
from sqlalchemy import create_engine,MetaData,Table,select,insert,update,func,delete,between,bindparam
from sqlalchemy.sql import and_, or_
from sqlalchemy.engine.reflection import Inspector
import sys
import datetime as dt
from configLib import config
import numpy as np

#this is a residual to trick batch processing - must be kept
from LiCSAR_db.LiCSquery import get_ipf
from sqlalchemy.pool import NullPool

################################################################################
# Create SQL engine
################################################################################
engine = create_engine(
    'mysql+pymysql://{usr}:{psswd}@{hst}/{dbname}?charset=utf8'.format(
        usr=config.get('DB','User'),
        psswd=config.get('DB','Password'),
        hst=config.get('DB','Host'),
        dbname=config.get('DB','DBName'),
        ),
    poolclass=NullPool,
    #connect_args={'connect_timeout': 60*60*24},  # using 24 hours timeout - coreg may take so long. still weird, as i close and reopen connection, but.. ok.. whatever
    pool_pre_ping=True
    )

################################################################################
# Create table meta data
################################################################################
licsMeta = MetaData()

jobs = Table('jobs',licsMeta)
polygs = Table('polygs',licsMeta)
polygs2master = Table('polygs2master',licsMeta)
files = Table('files',licsMeta)
files2bursts = Table('files2bursts',licsMeta)
polygs2bursts = Table('polygs2bursts',licsMeta)
slc = Table('slc',licsMeta)
rslc = Table('rslc',licsMeta)
ifg = Table('ifg',licsMeta)
unw = Table('unw',licsMeta)
acq_img = Table('acq_img',licsMeta)
bursts = Table('bursts',licsMeta)

insp = Inspector.from_engine(engine)
insp.reflecttable(jobs,None)
insp.reflecttable(polygs,None)
insp.reflecttable(files,None)
insp.reflecttable(files2bursts,None)
insp.reflecttable(polygs2bursts,None)
insp.reflecttable(polygs2master,None)
insp.reflecttable(slc,None)
insp.reflecttable(rslc,None)
insp.reflecttable(ifg,None)
insp.reflecttable(unw,None)
insp.reflecttable(acq_img,None)
insp.reflecttable(bursts,None)

################################################################################
def get_acq_dates(polyid):
    acqDtSel = select([func.date(files.c.acq_date).distinct()]).select_from(
                    files.join(files2bursts, 
                        onclause=files.c.fid==files2bursts.c.fid)
                    .join(polygs2bursts, 
                        onclause=files2bursts.c.bid==polygs2bursts.c.bid)
                ).where(polygs2bursts.c.polyid==polyid)
    conn = engine.connect()
    acqDats = pd.read_sql_query(acqDtSel,conn)
    conn.close()
    acqDats.columns = ['acq_date']
    acqDats = acqDats.sort_values(by='acq_date')
    return acqDats

################################################################################
def get_polyid(frame):
    conn = engine.connect()
    polygsSel = select([polygs.c.polyid]).where(polygs.c.polyid_name==frame)
    sqlRes = conn.execute(polygsSel)
    try:
        output = sqlRes.fetchone()[0]
    except:
        print('nothing found')
        output = None
    conn.close()
    return output

################################################################################
def get_frame_from_job(jobID):
    conn = engine.connect()
    polygsSel = select([polygs.c.polyid_name]).select_from(
            jobs.join(polygs,
                onclause=polygs.c.polyid==jobs.c.polyid)
            ).where(jobs.c.job_id==jobID)
    sqlRes = conn.execute(polygsSel)
    try:
        res = sqlRes.fetchone()[0]
    except:
        res = None
        print('error fetching sql result')
    conn.close()
    return res

################################################################################
def create_job(polyid,user,jobType):
    jobTypes = {'mk_image':0,
                'coreg':1,
                'mk_ifg':2,
                'unwrap':3
                }
    jobIns = jobs.insert().values(polyid=polyid,
                                    user=user,
                                    job_type=jobTypes[jobType])
    conn = engine.connect()
    sqlRes = conn.execute(jobIns)
    try:
        res = sqlRes.inserted_primary_key[0]
    except:
        res = None
        print('error fetching sql result')
    conn.close()
    return res

################################################################################
def set_master(polyid,mstrDate):
    conn = engine.connect()
    #get masterID
    mstrIDQry = select([acq_img.c.img_id]).where(and_(func.date(acq_img.c.acq_date)==mstrDate,acq_img.c.polyid==polyid))
    mstrID = conn.execute(mstrIDQry).fetchone()
    if mstrID:
        mstrID = mstrID[0]
    #check previous existing records over the polyid
    polycheckQry = select([polygs2master.c.polyid]).where(polygs2master.c.polyid==polyid)
    polycheck = conn.execute(polycheckQry).fetchone()
    if polycheck:
        #Update polygon if there is already a master
        polyDo = polygs2master.update().where(polygs2master.c.polyid==polyid).values(master_img_id=mstrID)
    else:
        #Insert info about master and polygon
        polyDo = polygs2master.insert().values(polyid=polyid,master_img_id=mstrID)
    try:
        res = conn.execute(polyDo)
    except:
        res = None
        print('error fetching sql result')
    conn.close()
    return res

################################################################################
def set_active(polyid):
    conn = engine.connect()
    #Update polygon
    polyUpd = polygs.update().where(polygs.c.polyid==polyid).values(active=True)
    try:
        res = conn.execute(polyUpd)
    except:
        res = None
        print('error fetching sql result')
    conn.close()
    return res

################################################################################
#def update_existing_rslcs(polyid,rslcs):
#    conn = engine.connect()
#    for rslc in rslcs:
#        
#    polyUpd = polygs.update().where(polygs.c.polyid==polyid).values(active=True)
#    return conn.execute(polyUpd)

################################################################################
def set_inactive(polyid):
    conn = engine.connect()
    #Update polygon
    polyUpd = polygs.update().where(polygs.c.polyid==polyid).values(active=False)
    a=conn.execute(polyUpd)
    
    #but i will also remove the non-active data:
    acqDlt = acq_img.delete().where(acq_img.c.polyid==polyid)
    conn.execute(acqDlt)
    
    slcDlt = slc.delete().where(slc.c.polyid==polyid)
    conn.execute(slcDlt)
    
    rslcDlt = rslc.delete().where(rslc.c.polyid==polyid)
    conn.execute(rslcDlt)
    
    ifgDlt = ifg.delete().where(ifg.c.polyid==polyid)
    conn.execute(ifgDlt)
    
    unwDlt = unw.delete().where(unw.c.polyid==polyid)
    conn.execute(unwDlt)
    
    jobDlt = jobs.delete().where(jobs.c.polyid==polyid)
    conn.execute(jobDlt)
    conn.close()
    return a

################################################################################
def get_master(frameName):
    conn = engine.connect()
    #Master date query
    mstrIDQry = select([acq_img.c.acq_date]).select_from(
            polygs.join(polygs2master,onclause=polygs.c.polyid==polygs2master.c.polyid)\
            .join(acq_img,onclause=polygs2master.c.master_img_id==acq_img.c.img_id)\
            ).where(polygs.c.polyid_name==frameName)
    #Update polygon
    mstrDate = conn.execute(mstrIDQry).fetchone()
    if mstrDate:
        output = mstrDate[0]
    else:
        output = None
    conn.close()
    return output


def get_user(frameName):
    conn = engine.connect()
    #query to get user that started processing of the given frame
    userIDQry = select([jobs.c.user]).select_from(
            polygs.join(jobs,onclause=polygs.c.polyid==jobs.c.polyid)).where(
            polygs.c.polyid_name==frameName)
    userID = conn.execute(userIDQry).fetchone()
    if userID:
        output = userID[0]
    else:
        output = None
    return output


################################################################################
def add_acq_images(polyid, startdate = None, enddate = None, masterdate = None):
    #startdate and enddate MUST be of type date!!!
    conn = engine.connect()
    acq_dates = get_acq_dates(polyid)
    
    #clean data in db
    imgDlt = acq_img.delete().where(acq_img.c.polyid==polyid)
    conn.execute(imgDlt)
    if masterdate:
        masteracq = acq_dates[acq_dates['acq_date']==masterdate]
        if startdate:
            acq_dates = acq_dates[acq_dates['acq_date']>=startdate]
        if enddate:
            acq_dates = acq_dates[acq_dates['acq_date']<=enddate]
        #add back master img
        if acq_dates[acq_dates['acq_date']==masterdate].empty:
            acq_dates.loc[max(acq_dates.index)+1, 'acq_date'] = masterdate
    #fix for close-to-midnight values:
    #fix for master image included 2021-08-12
    acq_dates_sorted = acq_dates.sort_values('acq_date')
    for i in range(len(acq_dates)-1):
        date1 = acq_dates_sorted['acq_date'].values[i]
        date2 = acq_dates_sorted['acq_date'].values[i+1]
        if date2 == date1+dt.timedelta(days=1):
            if date1 == masterdate or date2==masterdate:
                if date1 == masterdate:
                    todel = date2
                else:
                    todel = date1
            else:
                todel = date2
            acq_dates = acq_dates[acq_dates['acq_date']!=todel]
    
    #Rebuild
    polyidSrs = pd.Series(polyid,index=acq_dates.index,name='polyid')
    imgDtFrm = pd.concat([polyidSrs,acq_dates],axis=1)
    imgDtFrm.to_sql('acq_img',engine,index=False,if_exists='append')
    imgQry = select([acq_img.c.img_id,acq_img.c.acq_date]).select_from(
            acq_img.join(polygs,onclause=acq_img.c.polyid==polygs.c.polyid)).where(
        acq_img.c.polyid==polyid)
    out = pd.read_sql_query(imgQry,conn)
    conn.close()
    return out

################################################################################
def create_slcs(polyid,imgDtFrm):
    conn = engine.connect()

    #clean data
    slcDlt = slc.delete().where(slc.c.polyid==polyid)
    conn.execute(slcDlt)

    #Rebuild
    polyidSrs = pd.Series(polyid,index=imgDtFrm.index,name='polyid')
    statSrs = pd.Series(-1,index=imgDtFrm.index,name='slc_status')
    slcDtFrm = pd.concat([polyidSrs,statSrs,imgDtFrm['img_id']],axis=1)
    slcDtFrm.to_sql('slc',engine,index=False,if_exists='append')
    slcQry = select([slc.c.slc_id]).where(slc.c.polyid==polyid)
    out = pd.read_sql_query(slcQry,conn)
    conn.close()
    return out

################################################################################
def create_rslcs(polyid,imgDtFrm):
    conn = engine.connect()

    #clean data
    rslcDlt = rslc.delete().where(rslc.c.polyid==polyid)
    conn.execute(rslcDlt)

    #Rebuild
    polyidSrs = pd.Series(polyid,index=imgDtFrm.index,name='polyid')
    statSrs = pd.Series(-1,index=imgDtFrm.index,name='rslc_status')
    rslcDtFrm = pd.concat([polyidSrs,statSrs,imgDtFrm['img_id']],axis=1)
    rslcDtFrm.to_sql('rslc',engine,index=False,if_exists='append')
    rslcQry = select([rslc.c.rslc_id, rslc.c.img_id]).where(rslc.c.polyid==polyid)
    out = pd.read_sql_query(rslcQry,conn)
    conn.close()
    return out

################################################################################
def create_ifgs(polyid,imgDtFrm):
    conn = engine.connect()

    #clean data
    ifgDlt = ifg.delete().where(ifg.c.polyid==polyid)
    conn.execute(ifgDlt)

    #Rebuild
    imgDtFrm = imgDtFrm.sort_values('acq_date')
    imgSrsA = pd.concat( [
        imgDtFrm['img_id'].iloc[:-1],
        imgDtFrm['img_id'].iloc[:-2],
        imgDtFrm['img_id'].iloc[:-3],
            ], axis=0, ignore_index=True)
    imgSrsA.name = 'img_id_1'
    imgSrsA.index = list(range(0,imgSrsA.shape[0]))
    imgSrsB = pd.concat( [
        imgDtFrm['img_id'].iloc[1:],
        imgDtFrm['img_id'].iloc[2:],
        imgDtFrm['img_id'].iloc[3:],
            ], axis=0, ignore_index=True)
    imgSrsB.name = 'img_id_2'
    imgSrsA.index = list(range(0,imgSrsA.shape[0]))
    polyidSrs = pd.Series(polyid,index=imgSrsA.index,name='polyid')
    statSrs = pd.Series(-1,index=imgSrsA.index,name='ifg_status')
    ifgDtFrm = pd.concat([polyidSrs,statSrs,imgSrsA,imgSrsB],axis=1)
    ifgDtFrm.to_sql('ifg',engine,index=False,if_exists='append')
    ifgQry = select([ifg.c.ifg_id]).where(ifg.c.polyid==polyid)
    out = pd.read_sql_query(ifgQry,conn)
    conn.close()
    return out

################################################################################
def create_unws(polyid,imgDtFrm):
    conn = engine.connect()

    #clean data
    unwDlt = unw.delete().where(unw.c.polyid==polyid)
    conn.execute(unwDlt)

    #Rebuild
    imgDtFrm = imgDtFrm.sort_values('acq_date')
    imgSrsA = pd.concat( [
        imgDtFrm['img_id'].iloc[:-1],
        imgDtFrm['img_id'].iloc[:-2],
        imgDtFrm['img_id'].iloc[:-3],
            ], axis=0, ignore_index=True)
    imgSrsA.name = 'img_id_1'
    imgSrsA.index = list(range(0,imgSrsA.shape[0]))
    imgSrsB = pd.concat( [
        imgDtFrm['img_id'].iloc[1:],
        imgDtFrm['img_id'].iloc[2:],
        imgDtFrm['img_id'].iloc[3:],
            ], axis=0, ignore_index=True)
    imgSrsB.name = 'img_id_2'
    imgSrsA.index = list(range(0,imgSrsA.shape[0]))
    polyidSrs = pd.Series(polyid,index=imgSrsA.index,name='polyid')
    statSrs = pd.Series(-1,index=imgSrsA.index,name='unw_status')
    unwDtFrm = pd.concat([polyidSrs,statSrs,imgSrsA,imgSrsB],axis=1)
    unwDtFrm.to_sql('unw',engine,index=False,if_exists='append')
    unwQry = select([unw.c.unw_id]).where(unw.c.polyid==polyid)
    out = pd.read_sql_query(unwQry,conn)
    conn.close()
    return out

################################################################################
def link_slc_to_job(slcId,jobId):
    conn = engine.connect()
    #update
    slcUpd = slc.update().where(slc.c.slc_id==slcId).values(job_id=jobId)
    conn.execute(slcUpd)
    conn.close()

def batch_link_slcs_to_new_jobs(polyid,user,slcIds,batchN):
    slcIds['bin'] = pd.cut(slcIds['slc_id'],batchN,labels=False)
    slcGrouped = slcIds.groupby('bin')
    pom = 1
    for label,slcGroup in slcGrouped:
        jid = create_job(polyid,user,'mk_image')
        if pom:
            print('first_job_id is',jid)
        pom = 0
        slcGroup['slc_id'].map(lambda s:link_slc_to_job(s,jid))

################################################################################
def link_rslc_to_job(rslcId,jobId):
    conn = engine.connect()
    #update
    rslcUpd = rslc.update().where(rslc.c.rslc_id==rslcId).values(job_id=jobId)
    conn.execute(rslcUpd)
    conn.close()

def batch_link_rslcs_to_new_jobs(polyid,user,rslcIds,batchN):
    maxperjob=15
    if len(rslcIds)/batchN > maxperjob:
        print('increasing number of jobs to fit the maxperjob limit')
        batchN = int(len(rslcIds)/maxperjob)
    numrep = int(len(rslcIds)/batchN) + 1
    bins = list(np.arange(batchN))*numrep
    bins = bins[:len(rslcIds)]
    rslcIds['bin'] = bins
    #rslcIds['bin'] = pd.cut(rslcIds['rslc_id'],batchN,labels=False)
    rslcGrouped = rslcIds.groupby('bin')
    for label,rslcGroup in rslcGrouped:
        jid = create_job(polyid,user,'coreg')
        rslcGroup['rslc_id'].map(lambda s:link_rslc_to_job(s,jid))


def batch_link_rslcs_to_new_jobs_todo(polyid,user,rslcs_pd,batchN):
    rslcIds = rslcs_pd[['rslc_id']].reset_index(drop=True)
    maxperjob=15
    if len(rslcIds)/batchN > maxperjob:
        print('increasing number of jobs to fit the maxperjob limit')
        batchN = int(len(rslcIds)/maxperjob)
    numrep = int(len(rslcIds)/batchN) + 1
    bins = list(np.arange(batchN))*numrep
    bins = bins[:len(rslcIds)]
    rslcs_pd['bin'] = bins
    #rslcIds['bin'] = pd.cut(rslcIds['rslc_id'],batchN,labels=False)
    rslcGrouped = rslcs_pd.groupby('bin')
    #for label,rslcGroup in rslcGrouped:
        #make sure each group has at least one coregistrable epoch
    #    abs(rslcGroup.btemp).min().days
    #for label,rslcGroup in rslcGrouped:
        #make sure each group has no uncoregistrable item
    #    abs(rslcGroup.btemp).min().days
    for label,rslcGroup in rslcGrouped:
        jid = create_job(polyid,user,'coreg')
        rslcGroup['rslc_id'].map(lambda s:link_rslc_to_job(s,jid))


################################################################################
def link_ifg_to_job(ifgId,jobId):
    conn = engine.connect()
    #update
    ifgUpd = ifg.update().where(ifg.c.ifg_id==ifgId).values(job_id=jobId)
    conn.execute(ifgUpd)
    conn.close()

def batch_link_ifgs_to_new_jobs(polyid,user,ifgIds,batchN):
    ifgIds['bin'] = pd.cut(ifgIds['ifg_id'],batchN,labels=False)
    ifgGrouped = ifgIds.groupby('bin')
    for label,ifgGroup in ifgGrouped:
        jid = create_job(polyid,user,'mk_ifg')
        ifgGroup['ifg_id'].map(lambda s:link_ifg_to_job(s,jid))

################################################################################
def link_unw_to_job(unwId,jobId):
    conn = engine.connect()
    #update
    unwUpd = unw.update().where(unw.c.unw_id==unwId).values(job_id=jobId)
    conn.execute(unwUpd)
    conn.close()

def batch_link_unws_to_new_jobs(polyid,user,unwIds,batchN):
    unwIds['bin'] = pd.cut(unwIds['unw_id'],batchN,labels=False)
    unwGrouped = unwIds.groupby('bin')
    for label,unwGroup in unwGrouped:
        jid = create_job(polyid,user,'unwrap')
        unwGroup['unw_id'].map(lambda s:link_unw_to_job(s,jid))

################################################################################
def get_unbuilt_slcs(jobID):

    slcSel = select([slc.c.slc_id,acq_img.c.acq_date]).select_from(
            slc.join(acq_img,onclause=acq_img.c.img_id==slc.c.img_id)
            ).where(and_(slc.c.job_id==jobID,slc.c.slc_status!=0,
                slc.c.slc_status!=-6))
    conn = engine.connect()
    out = pd.read_sql_query(slcSel,conn,parse_dates=['acq_date'])
    conn.close()
    return out

################################################################################
def get_unreq_slcs(polyID):

    slcSel = select([slc.c.slc_id,acq_img.c.acq_date]).select_from(
            slc.join(acq_img,onclause=acq_img.c.img_id==slc.c.img_id)\
                    .join(rslc,onclause=rslc.c.img_id==slc.c.img_id)
            ).where(and_(slc.c.polyid==polyID,slc.c.slc_status==0,
                rslc.c.rslc_status==0))
    conn = engine.connect()
    out = pd.read_sql_query(slcSel,conn,parse_dates=['acq_date'])
    conn.close()
    return out

################################################################################
def get_unreq_slc_on_date(polyID,date):

    slcSel = select([slc.c.slc_id,acq_img.c.acq_date]).select_from(
            slc.join(acq_img,onclause=acq_img.c.img_id==slc.c.img_id)\
                    .join(rslc,onclause=rslc.c.img_id==slc.c.img_id)
            ).where(and_(slc.c.polyid==polyID,slc.c.slc_status==0,
                rslc.c.rslc_status==0,func.date(acq_img.c.acq_date)==date.date()))
    conn = engine.connect()
    out = pd.read_sql_query(slcSel,conn,parse_dates=['acq_date'])
    conn.close()
    return out

################################################################################
def get_unbuilt_rslcs(jobID):

    rslcSel = select([rslc.c.rslc_id,acq_img.c.acq_date]).select_from(
            rslc.join(acq_img,onclause=acq_img.c.img_id==rslc.c.img_id)\
            .join(slc,onclause=slc.c.img_id==rslc.c.img_id)
            ).where(and_(rslc.c.job_id==jobID,rslc.c.rslc_status!=0,
                rslc.c.rslc_status!=-6,slc.c.slc_status==0))
    conn = engine.connect()
    out = pd.read_sql_query(rslcSel,conn,parse_dates=['acq_date'])
    conn.close()
    return out

def get_all_slcs(polyid):

    slcSel = select([slc.c.slc_id,acq_img.c.acq_date]).select_from(
            slc.join(acq_img,onclause=acq_img.c.img_id==slc.c.img_id)\
            ).where(slc.c.polyid==polyid)
    conn = engine.connect()
    out = pd.read_sql_query(slcSel,conn,parse_dates=['acq_date'])
    conn.close()
    return out

def get_all_rslcs(polyid):

    rslcSel = select([rslc.c.rslc_id,acq_img.c.acq_date]).select_from(
            rslc.join(acq_img,onclause=acq_img.c.img_id==rslc.c.img_id)\
            ).where(rslc.c.polyid==polyid)
    conn = engine.connect()
    out = pd.read_sql_query(rslcSel,conn,parse_dates=['acq_date'])
    conn.close()
    return out

def get_all_ifgs(polyid):
    imgA = acq_img.alias()
    imgB = acq_img.alias()
    rslcA = rslc.alias()
    rslcB = rslc.alias()
    ifgSel = select([ifg.c.ifg_id,imgA.c.acq_date.label('acq_date_1'),
            imgB.c.acq_date.label('acq_date_2')]).select_from(
            ifg.join(imgA,onclause=imgA.c.img_id==ifg.c.img_id_1)\
            .join(imgB,onclause=imgB.c.img_id==ifg.c.img_id_2)\
            .join(rslcA,onclause=rslcA.c.img_id==ifg.c.img_id_1)\
            .join(rslcB,onclause=rslcB.c.img_id==ifg.c.img_id_2)
            ).where(rslcA.c.polyid==polyid)
            #and_(ifg.c.job_id==jobID,ifg.c.ifg_status!=0,
            #     rslcA.c.rslc_status==0,rslcB.c.rslc_status==0))
    conn = engine.connect()
    out = pd.read_sql_query(ifgSel,conn,parse_dates=['acq_date_1','acq_date_2'])
    conn.close()
    return out

def get_all_unws(polyid):
    imgA = acq_img.alias()
    imgB = acq_img.alias()
    rslcA = rslc.alias()
    rslcB = rslc.alias()
    unwSel = select([unw.c.unw_id,imgA.c.acq_date.label('acq_date_1'),
            imgB.c.acq_date.label('acq_date_2')]).select_from(
            unw.join(imgA,onclause=imgA.c.img_id==unw.c.img_id_1)\
            .join(imgB,onclause=imgB.c.img_id==unw.c.img_id_2)\
            .join(rslcA,onclause=rslcA.c.img_id==unw.c.img_id_1)\
            .join(rslcB,onclause=rslcB.c.img_id==unw.c.img_id_2)
            ).where(rslcA.c.polyid==polyid)
            #and_(ifg.c.job_id==jobID,ifg.c.ifg_status!=0,
            #     rslcA.c.rslc_status==0,rslcB.c.rslc_status==0))
    conn = engine.connect()
    out = pd.read_sql_query(unwSel,conn,parse_dates=['acq_date_1','acq_date_2'])
    conn.close()
    return out

################################################################################
def get_built_rslcs(polyid):

    rslcSel = select([rslc.c.rslc_id,acq_img.c.acq_date]).select_from(
            rslc.join(acq_img,onclause=acq_img.c.img_id==rslc.c.img_id)\
            .join(slc,onclause=slc.c.img_id==rslc.c.img_id)
            ).where(and_(rslc.c.polyid==polyid,rslc.c.rslc_status==0))
    conn = engine.connect()
    out = pd.read_sql_query(rslcSel,conn,parse_dates=['acq_date'])
    conn.close()
    return out

################################################################################
def get_unreq_rslcs(polyID):
    ifgA = ifg.alias()
    ifgB = ifg.alias()

    rslcSel = select([rslc.c.rslc_id.distinct(),acq_img.c.acq_date]).select_from(
            rslc.join(acq_img,onclause=acq_img.c.img_id==rslc.c.img_id)\
                    .join(ifgA,onclause=ifgA.c.img_id_1==rslc.c.img_id)\
                    .join(ifgB,onclause=ifgB.c.img_id_2==rslc.c.img_id)
            ).where(and_(rslc.c.polyid==polyID,rslc.c.rslc_status==0,
                ifgA.c.ifg_status==0,ifgB.c.ifg_status==0))
    conn = engine.connect()
    out = pd.read_sql_query(rslcSel,conn,parse_dates=['acq_date'])
    conn.close()
    return out

################################################################################
def get_unbuilt_ifgs(jobID):

    imgA = acq_img.alias()
    imgB = acq_img.alias()
    rslcA = rslc.alias()
    rslcB = rslc.alias()
    #ifgSel = select([ifg.c.ifg_id,imgA.c.acq_date.label('acq_date_1'),
    #        imgB.c.acq_date.label('acq_date_2')]).select_from(
    #        ifg.join(imgA,onclause=imgA.c.img_id==ifg.c.img_id_1)\
    #        .join(imgB,onclause=imgB.c.img_id==ifg.c.img_id_2)\
    #        .join(rslcA,onclause=rslcA.c.img_id==ifg.c.img_id_1)\
    #        .join(rslcB,onclause=rslcB.c.img_id==ifg.c.img_id_2)
    #        ).where(and_(ifg.c.job_id==jobID,ifg.c.ifg_status!=0,
    #            rslcA.c.rslc_status==0,rslcB.c.rslc_status==0))
    # 10/2021 - removed condition that the RSLCs must be marked as 'ready' in LiCSInfo (often not the case)
    ifgSel = select([ifg.c.ifg_id,imgA.c.acq_date.label('acq_date_1'),
            imgB.c.acq_date.label('acq_date_2')]).select_from(
            ifg.join(imgA,onclause=imgA.c.img_id==ifg.c.img_id_1)\
            .join(imgB,onclause=imgB.c.img_id==ifg.c.img_id_2)\
            .join(rslcA,onclause=rslcA.c.img_id==ifg.c.img_id_1)\
            .join(rslcB,onclause=rslcB.c.img_id==ifg.c.img_id_2)
            ).where(and_(ifg.c.job_id==jobID,ifg.c.ifg_status!=0))
    conn = engine.connect()
    out = pd.read_sql_query(ifgSel,conn,parse_dates=['acq_date_1','acq_date_2'])
    conn.close()
    return out

################################################################################
def get_unbuilt_unws(jobID):
    imgA = acq_img.alias()
    imgB = acq_img.alias()
    #unwSel = select([unw.c.unw_id,imgA.c.acq_date.label('acq_date_1'),
    #        imgB.c.acq_date.label('acq_date_2')]).select_from(
    #        unw.join(imgA,onclause=imgA.c.img_id==unw.c.img_id_1)\
    #        .join(imgB,onclause=imgB.c.img_id==unw.c.img_id_2)\
    #        .join(ifg,
    #            onclause=and_(ifg.c.img_id_1==unw.c.img_id_1,
    #                ifg.c.img_id_2==unw.c.img_id_2))
    #        ).where(and_(unw.c.job_id==jobID,unw.c.unw_status!=0,
    #            ifg.c.ifg_status==0))
    # 10/2021 - removing check for ifgs marked 'ready' in LiCSInfo
    unwSel = select([unw.c.unw_id,imgA.c.acq_date.label('acq_date_1'),
            imgB.c.acq_date.label('acq_date_2')]).select_from(
            unw.join(imgA,onclause=imgA.c.img_id==unw.c.img_id_1)\
            .join(imgB,onclause=imgB.c.img_id==unw.c.img_id_2)\
            .join(ifg,
                onclause=and_(ifg.c.img_id_1==unw.c.img_id_1,
                    ifg.c.img_id_2==unw.c.img_id_2))
            ).where(and_(unw.c.job_id==jobID,unw.c.unw_status!=0))
    conn = engine.connect()
    out = pd.read_sql_query(unwSel,conn,parse_dates=['acq_date_1','acq_date_2'])
    conn.close()
    return out

################################################################################
def get_built_unws(polyID):

    imgA = acq_img.alias()
    imgB = acq_img.alias()
    unwSel = select([unw.c.unw_id,imgA.c.acq_date.label('acq_date_1'),
            imgB.c.acq_date.label('acq_date_2')]).select_from(
            unw.join(imgA,onclause=imgA.c.img_id==unw.c.img_id_1)\
            .join(imgB,onclause=imgB.c.img_id==unw.c.img_id_2)\
            .join(ifg,
                onclause=and_(ifg.c.img_id_1==unw.c.img_id_1,
                    ifg.c.img_id_2==unw.c.img_id_2))
            ).where(and_(unw.c.polyid==polyID,unw.c.unw_status==0))
    conn = engine.connect()
    out = pd.read_sql_query(unwSel,conn,parse_dates=['acq_date_1','acq_date_2'])
    conn.close()
    return out

################################################################################

def get_bursts_in_frame(framename):
    conn = engine.connect()

    brstSel = select([bursts.c.bid_tanx.distinct(),bursts.c.centre_lon,bursts.c.centre_lat])\
        .select_from(
            bursts.join(polygs2bursts,
                    onclause=polygs2bursts.c.bid==bursts.c.bid)\
            .join(polygs,
                    onclause=polygs.c.polyid==polygs2bursts.c.polyid)
        ).where(polygs.c.polyid_name==framename)

    sqlRes = conn.execute(brstSel)
    burstInfo = sqlRes.fetchall()
    conn.close()
    return burstInfo

################################################################################
def get_frame_bursts_on_date(frame,date):
    conn = engine.connect()

    brstSel = select([bursts.c.bid_tanx.distinct(),bursts.c.centre_lon,bursts.c.centre_lat])\
        .select_from(
            bursts.join(polygs2bursts,
                    onclause=polygs2bursts.c.bid==bursts.c.bid)\
            .join(polygs,
                    onclause=polygs.c.polyid==polygs2bursts.c.polyid)\
            .join(files2bursts,
                    onclause=files2bursts.c.bid==bursts.c.bid)\
            .join(files,
                    onclause=files.c.fid==files2bursts.c.fid)
        ).where(and_(polygs.c.polyid_name==frame,
                    func.date(files.c.acq_date)==date.strftime('%Y-%m-%d'))
                )

    sqlRes = conn.execute(brstSel)
    burstInfo = sqlRes.fetchall()
    conn.close()
    return burstInfo

################################################################################
def get_frame_files_period(frame,startdate,enddate):

    conn = engine.connect()

    fileQry = select([polygs.c.polyid_name,func.date(files.c.acq_date),\
            files.c.name, files.c.abs_path]).select_from(
                    files.join(files2bursts,
                        onclause=files.c.fid==files2bursts.c.fid)\
                    .join(polygs2bursts,
                        onclause=polygs2bursts.c.bid==files2bursts.c.bid)\
                    .join(polygs,
                        onclause=polygs.c.polyid==polygs2bursts.c.polyid)
                    ).where(and_(polygs.c.polyid_name==frame,
                        between(func.date(files.c.acq_date),startdate.date(),enddate.date()))
                        ).order_by(files.c.acq_date).distinct()

    sqlRes = conn.execute(fileQry)
    try:
        res = sqlRes.fetchall()
    except:
        res = None
        print('error fetching sql result')
    conn.close()
    return res


################################################################################
def get_frame_files_date(frame,date):
    if type(date) is not type(dt.datetime.now().date()):
        date = date.date()
    
    conn = engine.connect()

    fileQry = select([polygs.c.polyid_name,\
            files.c.name, files.c.abs_path]).select_from(
                    files.join(files2bursts,
                        onclause=files.c.fid==files2bursts.c.fid)\
                    .join(polygs2bursts,
                        onclause=polygs2bursts.c.bid==files2bursts.c.bid)\
                    .join(polygs,
                        onclause=polygs.c.polyid==polygs2bursts.c.polyid)
                    ).where(and_(polygs.c.polyid_name==frame,
                                 or_(func.date(files.c.acq_date)==date,
                                     func.date(files.c.acq_date)==date+dt.timedelta(days=1)
                                    )
                                )
                        ).order_by(files.c.acq_date).distinct()

    sqlRes = conn.execute(fileQry)
    try:
        res = sqlRes.fetchall()
    except:
        res = None
        print('error fetching sql result')
    conn.close()
    return res


################################################################################
def get_burst_no(frame,date):

    conn = engine.connect()

    brstQry = select([bursts.c.bid_tanx.distinct(), files.c.name, files2bursts.c.burst_no]).select_from(
            bursts.join(files2bursts,
                onclause=files2bursts.c.bid==bursts.c.bid)\
            .join(files,
                onclause=files.c.fid==files2bursts.c.fid)\
            .join(polygs2bursts,
                onclause=polygs2bursts.c.bid==bursts.c.bid)\
            .join(polygs,
                onclause=polygs.c.polyid==polygs2bursts.c.polyid)
            ).where(and_(polygs.c.polyid_name==frame,
                func.date(files.c.acq_date)==date.date()))\
            .order_by(files.c.acq_date)

    sqlRes = conn.execute(brstQry)

    try:
        res = sqlRes.fetchall()
    except:
        res = None
        print('error fetching sql result')
    conn.close()
    return res

################################################################################
def set_slc_status(slcID,slcStat):
    conn = engine.connect()
    
    slcUpd = slc.update().where(slc.c.slc_id==slcID).values(slc_status=slcStat)
    conn.execute(slcUpd)
    conn.close()

################################################################################
def set_rslc_status(rslcID,rslcStat):
    conn = engine.connect()
    
    rslcUpd = rslc.update().where(rslc.c.rslc_id==rslcID).values(rslc_status=rslcStat)
    conn.execute(rslcUpd)
    conn.close()

def get_rslc_status(rslcID):
    conn = engine.connect()
    rslcSel = select([rslc.c.rslc_status]).select_from(rslc).where(rslc.c.rslc_id==rslcID)
    sqlRes = conn.execute(rslcSel)
    a = sqlRes.fetchall()
    conn.close()
    return int(str(a[0]).replace('(','').split(',')[0])

def get_slc_status(slcID):
    conn = engine.connect()
    slcSel = select([slc.c.slc_status]).select_from(slc).where(slc.c.slc_id==slcID)
    sqlRes = conn.execute(slcSel)
    a = sqlRes.fetchall()
    conn.close()
    return int(str(a[0]).replace('(','').split(',')[0])

################################################################################
def set_ifg_status(ifgID,ifgStat):
    conn = engine.connect()
    
    ifgUpd = ifg.update().where(ifg.c.ifg_id==ifgID).values(ifg_status=ifgStat)
    conn.execute(ifgUpd)
    conn.close()

################################################################################
def set_unw_status(unwID,unwStat):
    conn = engine.connect()
    
    unwUpd = unw.update().where(unw.c.unw_id==unwID).values(unw_status=unwStat)
    conn.execute(unwUpd)
    conn.close()

################################################################################
def set_unw_perc_unwrpd(unwID,unwPerc):
    conn = engine.connect()
    
    unwUpd = unw.update().where(unw.c.unw_id==unwID).values(unw_perc=unwPerc)
    conn.execute(unwUpd)
    conn.close()

################################################################################
def set_job_started(jobID):
    conn = engine.connect()
    
    jobUpd = jobs.update().where(jobs.c.job_id==jobID).values(job_status=2,time_started=dt.datetime.now())
    conn.execute(jobUpd)
    conn.close()

################################################################################
def set_job_finished(jobID,jobStat):
    conn = engine.connect()
    
    jobUpd = jobs.update().where(jobs.c.job_id==jobID).values(job_status=jobStat,time_finished=dt.datetime.now())
    conn.execute(jobUpd)
    conn.close()

################################################################################
def get_job_status(jobID):
    conn = engine.connect()
    
    jobSel = select([jobs.c.job_status]).where(jobs.c.job_id==jobID)
    res = conn.execute(jobSel)
    ress = res.fetchone()
    conn.close()
    return ress

def get_baseline(polyID):
    bsLnSel = select([acq_img.c.acq_date,acq_img.c.bperp]).\
            where(and_(
                acq_img.c.polyid==polyID,
                acq_img.c.bperp!=None
                ))
    conn = engine.connect()
    out = pd.read_sql_query(bsLnSel,conn)
    conn.close()
    return out

################################################################################
def set_baseline(polyid,baselineDataframe):
    conn = engine.connect()
    bsLnUpd = acq_img.update().\
            where(and_(
                acq_img.c.polyid==polyid,
                func.date(acq_img.c.acq_date)==bindparam('Date')
                )).values(bperp=bindparam('Bperp'))
    baselineDataframe['Date']=baselineDataframe['Date'].map(
            lambda x: x.date())
    bsLnDict = baselineDataframe.to_dict(orient='records')
    conn.execute(bsLnUpd,bsLnDict)
    conn.close()
