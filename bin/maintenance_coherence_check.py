#!/usr/bin/env python

import os
from subprocess import call
from osgeo import osr, gdal
import sys 
from mpl_toolkits.basemap import Basemap
import numpy as np
from numpy import gradient
from numpy import pi
from numpy import arctan
from numpy import arctan2
from numpy import sin 
from numpy import cos 
from numpy import sqrt
from numpy import zeros
from numpy import uint8
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt 
from matplotlib import ticker
#import elevation
import datetime
import heapq
import time
import requests
#from libtiff import TIFF
import matplotlib.dates as mdates
#import rasterio
from glob import glob
import scipy.ndimage.interpolation

frame=sys.argv[1]
number = int(frame[: 3])
number = str(number)

homepath = '/gws/nopw/j04/nceo_geohazards_vol1/public/LiCSAR_products/'+number+'/'+frame+'/products/'
savepath = '/gws/nopw/j04/nceo_geohazards_vol1/projects/LiCS/volc-proc/list_database/'
ext='cc.tif'

os.chdir(homepath)
check_coherence = savepath + 'coherence_stat_test.txt'
fid = open(check_coherence, 'w')

#filenames = [f for f in os.listdir(homepath) if f.endswith(ext)]
for root, dirs, files in os.walk(homepath):
    for filename in files:
        if filename.endswith('cc.tif'):  
            print(filename)
            filepath = os.path.join(root,filename)
            gtif = gdal.Open(filepath)
            data = gtif.ReadAsArray()
            Mean = np.mean(data)
            Std = np.std(data)
            Min = np.amin(data)   
            Max = np.amax(data)
            fid.write("%s %.3f %.3f %.3f\n" % (filename,Mean,Min,Max))
fid.close()
