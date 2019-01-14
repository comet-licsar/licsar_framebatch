#!/usr/bin/env python
from batchDBLib import get_polyid,set_inactive
import sys

polyID = get_polyid(sys.argv[1])
set_inactive(polyID)
