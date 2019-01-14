#!/usr/bin/env python

################################################################################
#import
################################################################################
import batchDBLib as lq
from batchMiscLib import get_ifg_perc_unwrapd
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

    unw = lq.get_built_unws(polyID)

#-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
    print 'Recalculating unwapped percentages for {frame}'.format(frame=frameName)
    
    frameDir = os.path.join(cacheDir,frameName)
    os.chdir(frameDir)
#-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
    for ind,row in unw.iterrows():
        dateA = row['acq_date_1']
        dateB = row['acq_date_2']
        print 'calculating for dates: {:%Y%m%d} - {:%Y%m%d}'.format(dateA,dateB)
        unwPerc = get_ifg_perc_unwrapd(dateA,dateB)
        lq.set_unw_perc_unwrpd(polyID,unwPerc)

if __name__ == "__main__":
    sys.exit(main(sys.argv))
