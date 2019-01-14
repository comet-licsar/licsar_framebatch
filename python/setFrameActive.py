#!/usr/bin/env python
from batchDBLib import get_polyid,set_active
import sys

polyID = get_polyid(sys.argv[1])
set_active(polyID)
