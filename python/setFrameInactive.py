#!/usr/bin/env python
from batchDBLib import get_polyid,set_inactive,get_user
import sys
import os
frame=sys.argv[1]
userid = get_user(frame)

if not userid:
    print('frame is already inactive')
    exit()


if userid == os.environ['USER']:
    print('Deactivating frame '+frame+' and removing related fields from framebatch database')
    polyID = get_polyid(frame)
    set_inactive(polyID)
else:
    print('this frame is active under different user: '+userid+'. Cancelling deactivation.')
