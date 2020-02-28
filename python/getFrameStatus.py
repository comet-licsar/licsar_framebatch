#!/usr/bin/env python
from batchDBLib import get_master
import sys

frame=sys.argv[1]

master = get_master(frame)

if master:
    print('active')
else:
    print('inactive')
