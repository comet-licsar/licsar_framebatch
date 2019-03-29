#!/usr/bin/env python

################################################################################
#import
################################################################################
import batchDBLib as lq
from configLib import config
from batchEnvLib import LicsEnv
from batchMiscLib import get_ifg_perc_unwrapd
import os
import shutil
import sys
import global_config as gc
import re
from LiCSAR_lib.LiCSAR_misc import *
from LiCSAR_lib.unwrp_lib import *
from batchLSFLib import set_lotus_job_status


#to ensure GAMMA will have proper value for CPU count
from multiprocessing import cpu_count
os.environ['OMP_NUM_THREADS'] = str(cpu_count())

################################################################################
#Status Codes
################################################################################
BUILT=0
MISSING_IFG=-2
EXCEPTION=-3
BUILDING=-5
################################################################################
#SLC env class
################################################################################
class UnwrapEnv(LicsEnv):
    def __init__(self,jobID,frame,mstrDate,dateA,dateB,cacheDir,tempDir):
        LicsEnv.__init__(self,jobID,frame,cacheDir,tempDir)
        self.srcPats = ['IFG/{0:%Y%m%d}_{1:%Y%m%d}.*'.format(dateA,dateB), 
                'SLC/{:%Y%m%d}.*'.format(mstrDate),
                'geo','DEM']

        self.outPats = ['IFG.*', # Patterns to output
                        'log.*',
                        'tab.*']

        self.srcIFGPath = 'IFG/{0:%Y%m%d}_{1:%Y%m%d}'.format(dateA,dateB)
        self.newDirs = ['tab','log'] # empty directories to create
        self.cleanDirs = ['./IFG','./tab'] # Directories to clean on failure

################################################################################
#Main
################################################################################
def main(argv):
    #Paramters
    jobID = int(argv[1])
    unws = lq.get_unbuilt_unws(jobID)
    frameName = lq.get_frame_from_job(jobID)
    try:
        cacheDir = os.environ['BATCH_CACHE_DIR']
    except KeyError as error:
        print('I required you to set your cache directory using the'\
                'enviroment variable BATCH_CACHE_DIR')
        raise error
    tempDir = config.get('Env','TempDir')
    user = os.environ['USER']
    tempDir = os.path.join(tempDir,user)
    mstrDate = lq.get_master(frameName)

#-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
    print("Processing job {0} in frame {1}".format( jobID, frameName))
    lq.set_job_started(jobID)

#-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
    for ind,row in unws.iterrows():
        
        dateA = row['acq_date_1']
        dateB = row['acq_date_2']

        #Parse multi look options
        slcCache = os.path.join(cacheDir,frameName,'SLC')
        gc.rglks = int(grep1('range_looks',os.path.join(slcCache,mstrDate.strftime('%Y%m%d/%Y%m%d.slc.mli.par'))).split(':')[1].strip())
        gc.aglks = int(grep1('azimuth_looks',os.path.join(slcCache,mstrDate.strftime('%Y%m%d/%Y%m%d.slc.mli.par'))).split(':')[1].strip())

        set_lotus_job_status('Setting up {:%y-%m-%d}->{:%y-%m-%d}'.format(dateA, dateB))
#-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
        with UnwrapEnv(jobID,frameName,mstrDate,dateA,dateB,cacheDir,tempDir) as env:
            print("created new processing enviroement {}".format(env.actEnv))
            print("processing ifg {0} between dates {1:%Y%m%d} and {2:%Y%m%d}".format(
                    row['unw_id'],dateA,dateB))

            #Set failure status
            env.cleanHook = lambda : lq.set_unw_status(row['unw_id'],EXCEPTION)

            #If source slc was succesfully copied over
            if os.path.exists(env.srcIFGPath):
                ifgName = '{0:%Y%m%d}_{1:%Y%m%d}'.format(dateA,dateB)
                lq.set_unw_status(row['unw_id'],BUILDING) #building status
                set_lotus_job_status('Building {:%y-%m-%d}->{:%y-%m-%d}'.format(dateA, dateB))
                rc = do_unwrapping(mstrDate.strftime('%Y%m%d'),frameName,ifgName,'./IFG','.',lq,-1)
                #Finally set ifg status to return code
                lq.set_unw_status(row['unw_id'],rc)

                if rc == 0:
                    ifgPerc = get_ifg_perc_unwrapd(dateA,dateB)
                    lq.set_unw_perc_unwrpd(row['unw_id'],ifgPerc)

            else: # otherwise set status to missing rslc
                lq.set_unw_status(row['unw_id'],MISSING_IFG)
                
            set_lotus_job_status('Cleaning {:%y-%m-%d}->{:%y-%m-%d}'.format(dateA, dateB))
#-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
    lq.set_job_finished(jobID,3)

if __name__ == "__main__":
    sys.exit(main(sys.argv))
