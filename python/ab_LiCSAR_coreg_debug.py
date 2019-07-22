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
import fnmatch
import pandas as pd
from LiCSAR_lib.coreg_lib import *
from LiCSAR_lib.LiCSAR_misc import *
from batchLSFLib import set_lotus_job_status

#to ensure GAMMA will have proper value for CPU count
from multiprocessing import cpu_count
os.environ['OMP_NUM_THREADS'] = str(cpu_count())

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

################################################################################
#Main
################################################################################
def main(argv):
    jobID = int(argv[1])
    rslcs = lq.get_unbuilt_rslcs(jobID)
    frameName = lq.get_frame_from_job(jobID)
    try:
        cacheDir = os.environ['BATCH_CACHE_DIR']
    except KeyError as error:
        print('I required you to set your cache directory using the'\
                'enviroment variable BATCH_CACHE_DIR')
        raise error
    user = os.environ['USER']
    mstrDate = lq.get_master(frameName)
    #-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
    
    #-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
    for ind,row in rslcs.iterrows():
        date = row['acq_date']
        #Get closes date and use as an aux
        rslcCache = os.path.join(cacheDir,frameName,'RSLC')
        #builtRslcDates = pd.to_datetime(os.listdir(rslcCache))
        builtRslcDates = pd.to_datetime(fnmatch.filter(os.listdir(rslcCache), '20??????'))
        builtRslcs = pd.DataFrame({'acq_date': builtRslcDates})
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
    #-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
        rc = coreg_slave(date,'SLC','RSLC',mstrDate.date(),frameName,'.', lq, -1)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
