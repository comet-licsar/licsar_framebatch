#!/usr/bin/env python

################################################################################
#import
################################################################################
import batchDBLib as lq
from configLib import config
from batchEnvLib import LicsEnv
import os
import shutil
import sys
import global_config as gc
import re
from LiCSAR_lib.LiCSAR_misc import *
from LiCSAR_lib.ifg_lib import *
from LiCSAR_lib.coreg_lib import rebuild_rslc
from batchLSFLib import set_lotus_job_status

################################################################################
#Status Codes
################################################################################
BUILT=0
MISSING_RSLC=-2
EXCEPTION=-3
BUILDING=-5
################################################################################
#SLC env class
################################################################################
class MkIfgEnv(LicsEnv):
    def __init__(self,jobID,frame,mstrDate,dateA,dateB,cacheDir,tempDir):
        LicsEnv.__init__(self,jobID,frame,cacheDir,tempDir)
        self.srcPats = ['RSLC/{:%Y%m%d}.*'.format(dateA), 
                'RSLC/{:%Y%m%d}.*'.format(dateB), 
                'RSLC/{:%Y%m%d}.*'.format(mstrDate),
                'SLC/{:%Y%m%d}.*'.format(mstrDate),
                'geo.*','DEM.*']

        self.outPats = ['IFG.*', # Patterns to output
                        'log.*',
                        'tab.*']

        self.srcRSLCAPath = 'RSLC/{:%Y%m%d}'.format(dateA)
        self.srcRSLCBPath = 'RSLC/{:%Y%m%d}'.format(dateB)
        self.newDirs = ['tab','log'] # empty directories to create
        self.cleanDirs = ['./IFG','./tab'] # Directories to clean on failure

################################################################################
#Main
################################################################################
def main(argv):
    #Paramters
    jobID = int(argv[1])
    ifgs = lq.get_unbuilt_ifgs(jobID)
    frameName = lq.get_frame_from_job(jobID)
    try:
        cacheDir = os.environ['BATCH_CACHE_DIR']
    except KeyError as error:
        print 'I required you to set your cache directory using the'\
                'enviroment variable BATCH_CACHE_DIR'
        raise error
    tempDir = config.get('Env','TempDir')
    user = os.environ['USER']
    tempDir = os.path.join(tempDir,user)
    mstrDate = lq.get_master(frameName)

#-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
    print "Processing job {0} in frame {1}".format( jobID, frameName)
    lq.set_job_started(jobID)

#-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
    for ind,row in ifgs.iterrows():
        
        dateA = row['acq_date_1']
        dateB = row['acq_date_2']

        #Parse multi look options
        slcCache = os.path.join(cacheDir,frameName,'SLC')
        gc.rglks = int(grep('range_looks',os.path.join(slcCache,mstrDate.strftime('%Y%m%d/%Y%m%d.slc.mli.par'))).split(':')[1].strip())
        gc.aglks = int(grep('azimuth_looks',os.path.join(slcCache,mstrDate.strftime('%Y%m%d/%Y%m%d.slc.mli.par'))).split(':')[1].strip())

        set_lotus_job_status('Setting up {:%y-%m-%d}->{:%y-%m-%d}'.format(dateA, dateB))
#-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
        with MkIfgEnv(jobID,frameName,mstrDate,dateA,dateB,cacheDir,tempDir) as env:
            print "created new processing enviroement {}".format(env.actEnv)
            print "processing ifg {0} between dates {1:%Y%m%d} and {2:%Y%m%d}".format(
                    row['ifg_id'],dateA,dateB)

            #Set failure status
            env.cleanHook = lambda : lq.set_ifg_status(row['ifg_id'],EXCEPTION)

            lq.set_ifg_status(row['ifg_id'],BUILDING) #building status
            #If source slc was succesfully copied over
            if os.path.exists(env.srcRSLCAPath) \
                and os.path.exists(env.srcRSLCBPath):

                set_lotus_job_status('Rebuilding RSLC {:%Y-%m-%d}'.format(dateA))
                rcA = rebuild_rslc('.',dateA,mstrDate,gc.rglks,gc.aglks)
                set_lotus_job_status('Rebuilding RSLC {:%Y-%m-%d}'.format(dateA))
                rcB = rebuild_rslc('.',dateB,mstrDate,gc.rglks,gc.aglks)

            else:
                rcA = None
                rcB = None

            if (rcA==0 or rcA==3) and (rcB==0 or rcB==3):
                set_lotus_job_status('Building {:%y-%m-%d}->{:%y-%m-%d}'.format(dateA, dateB))
                rc = make_interferogram(mstrDate,dateA,dateB,'.',lq,-1)
                #Finally set ifg status to return code
                lq.set_ifg_status(row['ifg_id'],rc)

            else: # otherwise set status to missing rslc
                lq.set_ifg_status(row['ifg_id'],MISSING_RSLC)

            set_lotus_job_status('Cleaning {:%y-%m-%d}->{:%y-%m-%d}'.format(dateA, dateB))
#-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
    lq.set_job_finished(jobID,3)

if __name__ == "__main__":
    sys.exit(main(sys.argv))
