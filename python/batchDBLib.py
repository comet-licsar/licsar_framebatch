#!/usr/bin/env python

################################################################################
#imports
################################################################################
import pandas as pd
from sqlalchemy import create_engine,MetaData,Table,select,insert,update,func,delete,between,bindparam
from sqlalchemy.sql import and_
from sqlalchemy.engine.reflection import Inspector
import sys
import datetime as dt
from configLib import config

################################################################################
# Create SQL engine
################################################################################
engine = create_engine(
    'mysql+pymysql://{usr}:{psswd}@{hst}/{dbname}'.format(
        usr=config.get('DB','User'),
        psswd=config.get('DB','Password'),
        hst=config.get('DB','Host'),
        dbname=config.get('DB','DBName'),
        )
    )

################################################################################
# Create table meta data
################################################################################
licsMeta = MetaData()

jobs = Table('jobs',licsMeta)
polygs = Table('polygs',licsMeta)
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
    acqDats = pd.read_sql_query(acqDtSel,engine)
    acqDats.columns = ['acq_date']
    return acqDats

################################################################################
def get_polyid(frame):
    conn = engine.connect()
    polygsSel = select([polygs.c.polyid]).where(polygs.c.polyid_name==frame)
    sqlRes = conn.execute(polygsSel)
    return sqlRes.fetchone()[0]

################################################################################
def get_frame_from_job(jobID):
    conn = engine.connect()
    polygsSel = select([polygs.c.polyid_name]).select_from(
            jobs.join(polygs,
                onclause=polygs.c.polyid==jobs.c.polyid)
            ).where(jobs.c.job_id==jobID)
    sqlRes = conn.execute(polygsSel)
    return sqlRes.fetchone()[0]

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
    return sqlRes.inserted_primary_key[0]

################################################################################
def set_master(polyid,mstrDate):
    conn = engine.connect()
    #get masterID
    mstrIDQry = select([acq_img.c.img_id]).where(and_(func.date(acq_img.c.acq_date)==mstrDate,acq_img.c.polyid==polyid))
    mstrID = conn.execute(mstrIDQry).fetchone()[0]
    #Update polygon
    polyUpd = polygs.update().where(polygs.c.polyid==polyid).values(master_img_id=mstrID)
    return conn.execute(polyUpd)

################################################################################
def set_active(polyid):
    conn = engine.connect()
    #Update polygon
    polyUpd = polygs.update().where(polygs.c.polyid==polyid).values(active=True)
    return conn.execute(polyUpd)

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
    
    return a

################################################################################
def get_master(frameName):
    conn = engine.connect()
    #Master date query
    mstrIDQry = select([acq_img.c.acq_date]).select_from(
            acq_img.join(polygs,
                onclause=polygs.c.master_img_id==acq_img.c.img_id)
            ).where(polygs.c.polyid_name==frameName)
    #Update polygon
    mstrDate = conn.execute(mstrIDQry).fetchone()
    return mstrDate[0]

################################################################################
def add_acq_images(polyid):
    conn = engine.connect()
    acq_dates = get_acq_dates(polyid)
    
    #clean data
    imgDlt = acq_img.delete().where(acq_img.c.polyid==polyid)
    conn.execute(imgDlt)

    #Rebuild
    polyidSrs = pd.Series(polyid,index=acq_dates.index,name='polyid')
    imgDtFrm = pd.concat([polyidSrs,acq_dates],axis=1)
    imgDtFrm.to_sql('acq_img',engine,index=False,if_exists='append')
    imgQry = select([acq_img.c.img_id,acq_img.c.acq_date]).select_from(
            acq_img.join(polygs,onclause=acq_img.c.polyid==polygs.c.polyid)).where(
        acq_img.c.polyid==polyid)
    return pd.read_sql_query(imgQry,engine)

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
    return pd.read_sql_query(slcQry,engine)

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
    rslcQry = select([rslc.c.rslc_id]).where(rslc.c.polyid==polyid)

    return pd.read_sql_query(rslcQry,engine)

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

    return pd.read_sql_query(ifgQry,engine)

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

    return pd.read_sql_query(unwQry,engine)

################################################################################
def link_slc_to_job(slcId,jobId):
    conn = engine.connect()
    #update
    slcUpd = slc.update().where(slc.c.slc_id==slcId).values(job_id=jobId)
    conn.execute(slcUpd)

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

def batch_link_rslcs_to_new_jobs(polyid,user,rslcIds,batchN):
    rslcIds['bin'] = pd.cut(rslcIds['rslc_id'],batchN,labels=False)
    rslcGrouped = rslcIds.groupby('bin')
    for label,rslcGroup in rslcGrouped:
        jid = create_job(polyid,user,'coreg')
        rslcGroup['rslc_id'].map(lambda s:link_rslc_to_job(s,jid))

################################################################################
def link_ifg_to_job(ifgId,jobId):
    conn = engine.connect()
    #update
    ifgUpd = ifg.update().where(ifg.c.ifg_id==ifgId).values(job_id=jobId)
    conn.execute(ifgUpd)

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

    return pd.read_sql_query(slcSel,engine,parse_dates=['acq_date'])

################################################################################
def get_unreq_slcs(polyID):

    slcSel = select([slc.c.slc_id,acq_img.c.acq_date]).select_from(
            slc.join(acq_img,onclause=acq_img.c.img_id==slc.c.img_id)\
                    .join(rslc,onclause=rslc.c.img_id==slc.c.img_id)
            ).where(and_(slc.c.polyid==polyID,slc.c.slc_status==0,
                rslc.c.rslc_status==0))

    return pd.read_sql_query(slcSel,engine,parse_dates=['acq_date'])

################################################################################
def get_unreq_slc_on_date(polyID,date):

    slcSel = select([slc.c.slc_id,acq_img.c.acq_date]).select_from(
            slc.join(acq_img,onclause=acq_img.c.img_id==slc.c.img_id)\
                    .join(rslc,onclause=rslc.c.img_id==slc.c.img_id)
            ).where(and_(slc.c.polyid==polyID,slc.c.slc_status==0,
                rslc.c.rslc_status==0,func.date(acq_img.c.acq_date)==date.date()))

    return pd.read_sql_query(slcSel,engine,parse_dates=['acq_date'])

################################################################################
def get_unbuilt_rslcs(jobID):

    rslcSel = select([rslc.c.rslc_id,acq_img.c.acq_date]).select_from(
            rslc.join(acq_img,onclause=acq_img.c.img_id==rslc.c.img_id)\
            .join(slc,onclause=slc.c.img_id==rslc.c.img_id)
            ).where(and_(rslc.c.job_id==jobID,rslc.c.rslc_status!=0,
                rslc.c.rslc_status!=-6,slc.c.slc_status==0))

    return pd.read_sql_query(rslcSel,engine,parse_dates=['acq_date'])

################################################################################
def get_built_rslcs(polyid):

    rslcSel = select([rslc.c.rslc_id,acq_img.c.acq_date]).select_from(
            rslc.join(acq_img,onclause=acq_img.c.img_id==rslc.c.img_id)\
            .join(slc,onclause=slc.c.img_id==rslc.c.img_id)
            ).where(and_(rslc.c.polyid==polyid,rslc.c.rslc_status==0))

    return pd.read_sql_query(rslcSel,engine,parse_dates=['acq_date'])

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

    return pd.read_sql_query(rslcSel,engine,parse_dates=['acq_date'])

################################################################################
def get_unbuilt_ifgs(jobID):

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
            ).where(and_(ifg.c.job_id==jobID,ifg.c.ifg_status!=0,
                rslcA.c.rslc_status==0,rslcB.c.rslc_status==0))

    return pd.read_sql_query(ifgSel,engine,parse_dates=['acq_date_1','acq_date_2'])

################################################################################
def get_unbuilt_unws(jobID):

    imgA = acq_img.alias()
    imgB = acq_img.alias()
    unwSel = select([unw.c.unw_id,imgA.c.acq_date.label('acq_date_1'),
            imgB.c.acq_date.label('acq_date_2')]).select_from(
            unw.join(imgA,onclause=imgA.c.img_id==unw.c.img_id_1)\
            .join(imgB,onclause=imgB.c.img_id==unw.c.img_id_2)\
            .join(ifg,
                onclause=and_(ifg.c.img_id_1==unw.c.img_id_1,
                    ifg.c.img_id_2==unw.c.img_id_2))
            ).where(and_(unw.c.job_id==jobID,unw.c.unw_status!=0,
                ifg.c.ifg_status==0))

    return pd.read_sql_query(unwSel,engine,parse_dates=['acq_date_1','acq_date_2'])

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

    return pd.read_sql_query(unwSel,engine,parse_dates=['acq_date_1','acq_date_2'])

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
    return sqlRes.fetchall()

################################################################################
def get_frame_files_date(frame,date):

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
                        func.date(files.c.acq_date)==date.date()
                        )
                        ).order_by(files.c.acq_date).distinct()

    sqlRes = conn.execute(fileQry)
    return sqlRes.fetchall()

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

    return sqlRes.fetchall()

################################################################################
def set_slc_status(slcID,slcStat):
    conn = engine.connect()
    
    slcUpd = slc.update().where(slc.c.slc_id==slcID).values(slc_status=slcStat)
    conn.execute(slcUpd)

################################################################################
def set_rslc_status(rslcID,rslcStat):
    conn = engine.connect()
    
    rslcUpd = rslc.update().where(rslc.c.rslc_id==rslcID).values(rslc_status=rslcStat)
    conn.execute(rslcUpd)

################################################################################
def set_ifg_status(ifgID,ifgStat):
    conn = engine.connect()
    
    ifgUpd = ifg.update().where(ifg.c.ifg_id==ifgID).values(ifg_status=ifgStat)
    conn.execute(ifgUpd)

################################################################################
def set_unw_status(unwID,unwStat):
    conn = engine.connect()
    
    unwUpd = unw.update().where(unw.c.unw_id==unwID).values(unw_status=unwStat)
    conn.execute(unwUpd)

################################################################################
def set_unw_perc_unwrpd(unwID,unwPerc):
    conn = engine.connect()
    
    unwUpd = unw.update().where(unw.c.unw_id==unwID).values(unw_perc=unwPerc)
    conn.execute(unwUpd)

################################################################################
def set_job_started(jobID):
    conn = engine.connect()
    
    jobUpd = jobs.update().where(jobs.c.job_id==jobID).values(job_status=2,time_started=dt.datetime.now())
    conn.execute(jobUpd)

################################################################################
def set_job_finished(jobID,jobStat):
    conn = engine.connect()
    
    jobUpd = jobs.update().where(jobs.c.job_id==jobID).values(job_status=jobStat,time_finished=dt.datetime.now())
    conn.execute(jobUpd)

################################################################################
def get_job_status(jobID):
    conn = engine.connect()
    
    jobSel = select([jobs.c.job_status]).where(jobs.c.job_id==jobID)
    res = conn.execute(jobSel)
    return res.fetchone()

def get_baseline(polyID):
    bsLnSel = select([acq_img.c.acq_date,acq_img.c.bperp]).\
            where(and_(
                acq_img.c.polyid==polyID,
                acq_img.c.bperp!=None
                ))
    return pd.read_sql_query(bsLnSel,engine)

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
