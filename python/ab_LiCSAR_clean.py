#!/usr/bin/env python

################################################################################
#import
################################################################################
import batchDBLib as lq
from configLib import config
import os
import shutil
import sys
import global_config as gc
import re

################################################################################
#Status Codes
################################################################################
REMOVED=-6


################################################################################
#Main
################################################################################
def main(argv):
    #Paramters
    frameName = argv[1]
    polyID = lq.get_polyid(frameName)
    try:
        cacheDir = os.environ['BATCH_CACHE_DIR']
    except KeyError as error:
        print 'I required you to set your cache directory using the'\
                'enviroment variable BATCH_CACHE_DIR'
        raise error

    slc = lq.get_unreq_slcs(polyID)
    slcDir = os.path.join(cacheDir,frameName,'SLC')

#-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
    print 'Ceaning {frame} slcs'.format(frame=frameName)

#-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
    for ind,row in slc.iterrows():
        date = row['acq_date']
        print 'removing date {:%Y%m%d}'.format(date)
        slcDateDir = os.path.join(slcDir,date.strftime('%Y%m%d'))
        shutil.rmtree(slcDateDir)
        lq.set_slc_status(row['slc_id'],REMOVED)

if __name__ == "__main__":
    sys.exit(main(sys.argv))
