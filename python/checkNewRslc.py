#!/usr/bin/env python
# this script is checking if there are some new acquisitions existing in scihub
# compared to the frame RSLCs in LiCSAR_procdir (not checking BATCH_CACHE_DIR as it should be imported to procdir..)

import sys
from LiCSAR_lib.s1data import get_epochs_for_frame
from batchEnvLib import get_rslc_list
from datetime import datetime, timedelta

frame=sys.argv[1]
#polyID = get_polyid(sys.argv[1])



rslcs = get_rslc_list(frame, True)
last_rslc = rslcs[-1]

#to compare I have to get the next day..
last_rslc_date = datetime.strptime(last_rslc,'%Y%m%d') + timedelta(days=2)
last_rslc_date = last_rslc_date.date()
#curDir = os.environ['LiCSAR_procdir']
new_epochs = get_epochs_for_frame(frame, last_rslc_date)
if new_epochs:
    noepochs = len(new_epochs)
else:
    noepochs = 0

print(str(noepochs))

#print('Frame '+frame+' has '+str(noepochs)+' unprocessed epochs since the last run.')