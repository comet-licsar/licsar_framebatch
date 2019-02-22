#!/usr/bin/env python
from batchDBLib import get_polyid,set_active
import sys, os, fnmatch

framename=sys.argv[1]

polyID = get_polyid(sys.argv[1])

#get curdir
try:
    curDir = os.environ['LiCSAR_procdir']
except KeyError as error:
    print('Somehow the current processing directory is not set')
    raise error

#check if framename is initialized, i.e. exists in curdir
frameDir = curDir + '/' + framename.split('_')[0].lstrip("0")[:-1] + '/' + framename
try:
    master = fnmatch.filter(os.listdir(frameDir+'/geo'), '????????.hgt')[0].split('.')[0]
except KeyError as error:
    print('Seems that the frame was not initialized yet')
    raise error

#now we can activate the frame
set_active(polyID)
#update_existing_rslcs(polyID)
