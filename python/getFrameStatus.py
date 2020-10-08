#!/usr/bin/env python
from batchDBLib import get_user
import sys

frame=sys.argv[1]

userid = get_user(frame)

if userid:
    #if second parameter, print the username rather than 'active'
    if len(sys.argv)>2:
        print(userid)
    else:
        print('active')
else:
    print('inactive')


