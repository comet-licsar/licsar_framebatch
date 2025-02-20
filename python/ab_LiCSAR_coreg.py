#!/usr/bin/env python

################################################################################
#import
################################################################################
import batchDBLib as lq
from configLib import config
from batchEnvLib import LicsEnv
import os
from glob import glob
import shutil
import sys
import global_config as gc
import re
import fnmatch
import pandas as pd
from LiCSAR_lib.coreg_lib import *
from LiCSAR_lib.LiCSAR_misc import *
from batchLSFLib import set_lotus_job_status

#to ensure GAMMA will have proper value for CPU count
#however i had to force processing on 1 core only, so hardcoding here
#from multiprocessing import cpu_count
#os.environ['OMP_NUM_THREADS'] = str(cpu_count())
os.environ['OMP_NUM_THREADS'] = str(1)

################################################################################
#Statuses
################################################################################
REMOVED = -6
BUILDING = -5
UNKOWN_ERROR = -3
MISSING_SLC = -2
BUILT = 0

################################################################################
#SLC env class
################################################################################
class CoregEnv(LicsEnv):
    def __init__(self,jobID,frame,mstrDate,auxDate,date,cacheDir,tempDir):
        LicsEnv.__init__(self,jobID,frame,cacheDir,tempDir)
        self.srcPats = ['SLC/{:%Y%m%d}.*'.format(date), #patterns to source
                'LUT/{:%Y%m%d}.*'.format(date),
                'RSLC/{:%Y%m%d}.*'.format(mstrDate),
                'SLC/{:%Y%m%d}.*'.format(mstrDate),
                'geo','local_config.py']
        if auxDate:
            self.srcPats += ['RSLC/{:%Y%m%d}.*'.format(auxDate)]
        self.outPats = ['RSLC/{0:%Y%m%d}/{0:%Y%m%d}\.IW[1-3]\.rslc.*'.format(date), # Patterns to output
                        'RSLC/{0:%Y%m%d}/{0:%Y%m%d}\.rslc\.par'.format(date), # Patterns to output
                        'RSLC/{0:%Y%m%d}/{0:%Y%m%d}\.rslc'.format(date), # Patterns to output
                        'RSLC/{0:%Y%m%d}/{0:%Y%m%d}.*mli.*'.format(date), # Patterns to output
                        'RSLC/{0:%Y%m%d}/{1:%Y%m%d}_{0:%Y%m%d}.slc.mli.lt'.format(date,mstrDate),
                        'RSLC/{0:%Y%m%d}/{1:%Y%m%d}_{0:%Y%m%d}.off'.format(date,mstrDate),
                        'RSLC/{0:%Y%m%d}/{1:%Y%m%d}_{0:%Y%m%d}.results'.format(date,mstrDate),
                        'GEOC\.MLI.*',
                        'log.*']
        self.srcSlcPath = 'SLC/{:%Y%m%d}'.format(date) #used to check source slc
        self.srcLutPath = 'LUT/{:%Y%m%d}'.format(date) #used to check source slc
        self.newDirs = ['tab','log'] # empty directories to create
        self.cleanDirs = ['./RSLC','./GEOC.*','./tab'] # Directories to clean on failure


################################################################################
#Main
################################################################################
def main(argv):
    #Paramters
    jobID = int(argv[1])
    rslcs = lq.get_unbuilt_rslcs(jobID)
    frameName = lq.get_frame_from_job(jobID)
    acqMode = 'iw'
    if frameName.split('_')[1] == 'SM':
        acqMode = 'sm'
        print('processing stripmap frame - EXPERIMENTAL')
    try:
        cacheDir = os.environ['BATCH_CACHE_DIR']
    except KeyError as error:
        print('I required you to set your cache directory using the'\
                'enviroment variable BATCH_CACHE_DIR')
        raise error
    #tempDir = config.get('Env','TempDir')
    #user = os.environ['USER']
    #tempDir = os.path.join(tempDir,user)
    tempDir = os.environ['LiCSAR_temp']
    mstrDate = lq.get_master(frameName)
    if not mstrDate:
        print('error getting master date - doing workaround')
        import framecare as fc
        mstrDate = pd.Timestamp(fc.get_master(frameName)).to_pydatetime()
        lq.set_master(lq.get_polyid(frameName), mstrDate)
#-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
    print("Processing job {0} in frame {1}".format( jobID, frameName))
    lq.set_job_started(jobID)


#-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
    rslcCache = os.path.join(cacheDir,frameName,'RSLC')
    builtRslcDates = pd.to_datetime(fnmatch.filter(os.listdir(rslcCache), '20??????'))
    builtRslcs = pd.DataFrame({'acq_date': builtRslcDates})
    builtRslcs_nomissing = get_nomissing_rslcs(rslcCache, mstrDate, builtRslcs)
    if not builtRslcs_nomissing.empty:
        builtRslcs = builtRslcs_nomissing.reset_index(drop=True)
    else:
        print('missing bursts check failed - probably no full RSLC available to be used as aux, but trying anyway')
    try:
        builtRslcs_orig = builtRslcs.copy(deep=True)
    except:
        builtRslcs_orig = builtRslcs
    
    for ind,row in rslcs.iterrows():
        date = row['acq_date']
        #oh no.. seeing the lines below makes me think that it is NOT GOOD IDEA to
        # have many people solve the same issue...
        # but keeping as it is since it works. ML
        #Get closes date and use as an aux
        try:
            builtRslcs = builtRslcs_orig.copy(deep=True)
        except:
            builtRslcs = builtRslcs_orig
        builtRslcs['date_diff'] = builtRslcs['acq_date'].apply(
                lambda x: abs(x-date)
                )
        closestDate = builtRslcs.sort_values('date_diff').iloc[0].loc['acq_date']
        if closestDate.date() != mstrDate.date():
            auxDate = closestDate
        else:
            auxDate = None

        #Parse multi look options
        slcCache = os.path.join(cacheDir,frameName,'SLC')
        gc.rglks = int(grep1('range_looks',os.path.join(slcCache,mstrDate.strftime('%Y%m%d/%Y%m%d.slc.mli.par'))).split(':')[1].strip())
        gc.aglks = int(grep1('azimuth_looks',os.path.join(slcCache,mstrDate.strftime('%Y%m%d/%Y%m%d.slc.mli.par'))).split(':')[1].strip())
        set_lotus_job_status('Setting up {:%y-%m-%d}'.format(date))
#-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
        rc = -3
        with CoregEnv(jobID,frameName,mstrDate,auxDate,date,cacheDir,tempDir) as env:
            print("created new processing enviroement {}".format(env.actEnv))
            print("processing rslc {0} on acquisition date {1:%Y%m%d}".format(
                    row['rslc_id'],row['acq_date']))

            #Set failure status
            env.cleanHook = lambda : lq.set_rslc_status(row['rslc_id'],UNKOWN_ERROR)

            #If source slc was succesfully copied over
            if os.path.exists(env.srcSlcPath):
                set_lotus_job_status('Processing {:%y-%m-%d}'.format(date))

                lq.set_rslc_status(row['rslc_id'],BUILDING) #building status
                
                if os.path.exists(env.srcLutPath):
                    #so if LUT exists for this date, do re-recoregistration. otherwise just.. normal one
                    if acqMode == 'sm':
                        print('recoregistration for stripmaps is not ready yet, reprocessing instead!')
                        rc = coreg_slave_sm(date,'SLC','RSLC',mstrDate.date(),frameName,'.', lq, -1)
                    else:
                        rc = recoreg_slave(date,'SLC','RSLC',mstrDate.date(),frameName,'.', lq)
                        if rc != 0:
                            # rc code 7 means LUT not found..
                            slaveLockFile = 'RSLC/'+date.strftime('/%Y%m%d.lock')
                            if os.path.exists(slaveLockFile):
                                os.remove(slaveLockFile)
                            rc = coreg_slave(date,'SLC','RSLC',mstrDate.date(),frameName,'.', lq, -1)
                else:
                    if acqMode == 'sm':
                        rc = coreg_slave_sm(date,'SLC','RSLC',mstrDate.date(),frameName,'.', lq, -1)
                    else:
                        rc = coreg_slave(date,'SLC','RSLC',mstrDate.date(),frameName,'.', lq, -1)

                rslc = os.path.join(env.actEnv,'RSLC',date.strftime('%Y%m%d'),
                                    date.strftime('%Y%m%d.rslc'))
                rslc_epochdir = os.path.join(env.actEnv,'RSLC',date.strftime('%Y%m%d'))
                
                #if os.path.exists(rslc):
                #    print("Removing mosaiced image {0}".format(rslc))
                #    os.remove(rslc)

                #Finally set rslc status to return code
                try:
                    #lq.conn.ping(reconnect=True)
                    try:
                        reconn_pom = lq.connection_established()
                        lq.set_rslc_status(row['rslc_id'],rc)
                    except:
                        reconn_pom = lq.connection_established()
                        lq.set_rslc_status(row['rslc_id'],rc)
                except:
                    print('debug 1: error in mysql connection - common after Sep 2020 change in mysql db by JASMIN..')
                    print('but continuing')
                if os.path.exists(rslc_epochdir):
                    if rc!=0:
                        print('there was an error, cleaning the (probably) wrongly generated RSLC')
                        shutil.rmtree(rslc_epochdir)
                    else:
                        cmd = 'create_geoctiffs_to_pub.sh -M {0} {1}'.format(env.actEnv, date.strftime('%Y%m%d'))
                        rcc = os.system(cmd)
                
            else: # otherwise set status to missing slc
                #lq.conn.ping(reconnect=True)
                lq.set_rslc_status(row['rslc_id'],MISSING_SLC)

            try:
                #lq.conn.ping(reconnect=True)
                set_lotus_job_status('Cleaning {:%y-%m-%d}'.format(date))
            except:
                print('debug 2: error in mysql connection - common after Sep 2020 change in mysql db by JASMIN..')
                print('but continuing')
#-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
       # try:
       #     lq.conn.ping(reconnect=True)
       # except:
       #     print('no reconnection to db')
        polyID = lq.get_polyid(frameName)
        slc = lq.get_unreq_slc_on_date(polyID,date)
        if rc == 0 and not slc.empty:
            slcDateCache = os.path.join(slcCache,date.strftime('%Y%m%d'))
            shutil.rmtree(slcDateCache)
            print("removed slc cache {:%Y%m%d}".format(date))
            lq.set_slc_status(int(slc.loc[0,'slc_id']),-6)
                
#-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
    try:
        #lq.conn.ping(reconnect=True)
        lq.set_job_finished(jobID,3)
    except:
        print('error in db access')

if __name__ == "__main__":
    sys.exit(main(sys.argv))
