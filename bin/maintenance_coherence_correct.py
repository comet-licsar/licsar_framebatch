#!/usr/bin/env python

import os, sys
from osgeo import gdal
import numpy as np

frame=sys.argv[1]
number = int(frame[: 3])
number = str(number)

homepath = '/gws/nopw/j04/nceo_geohazards_vol1/public/LiCSAR_products/'+number+'/'+frame+'/products/'
#savepath = '/gws/nopw/j04/nceo_geohazards_vol1/projects/LiCS/volc-proc/list_database/'
ext='cc.tif'

os.chdir(homepath)
#check_coherence = savepath + 'coherence_stat_test.txt'
#fid = open(check_coherence, 'w')

#filenames = [f for f in os.listdir(homepath) if f.endswith(ext)]
for root, dirs, files in os.walk(homepath):
    for filename in files:
        if filename.endswith('cc.tif'):
            filepath = os.path.join(root,filename)
            gtif = gdal.Open(filepath)
            data = gtif.ReadAsArray()
            Max = np.amax(data)
            if Max <= 1:
                print('rescaling '+filepath)
                filepath_src = filepath.replace('.geo.cc.tif','.geo.cc.orig.tif')
                os.rename(filepath, filepath_src)
                cmd = 'gdal_translate -of GTiff -ot Byte -scale 0 1 0 255 -co COMPRESS=LZW -co PREDICTOR=2 \
                       {0} {1} >/dev/null 2>/dev/null'.format(filepath_src,filepath)
                rc = os.system(cmd)
                if not os.path.exists:
                    print('ERROR during gdal_translating of '+filepath)
                    os.rename(filepath_src, filepath)
                else:
                    os.remove(filepath_src)

