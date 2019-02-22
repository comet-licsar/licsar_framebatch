#!/usr/bin/env python
from batchDBLib import get_polyid,set_inactive
import sys

frame=sys.argv[1]
polyID = get_polyid(sys.argv[1])
print('Deactivating frame '+frame+' and removing related fields from framebatch database')
set_inactive(polyID)
