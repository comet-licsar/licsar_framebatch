#!/usr/bin/env python
#ML 2023
import os
#import LiCSAR_lib.LiCSAR_misc as misc
#import LiCSquery as lq
#import framecare as fc

# INPUTS
#frame='100A_05236_141313'
volcid = 
#lon=-71.377  # centre lon,lat
#lat=-36.863
radius_km=25/2
resol_m=30
sid='SAREZ' # or volc ID
is_volc=False


# BASICS
radius_deg=radius_km/111
resol=resol_m/111111 #0.00027
framebatchdir=os.path.join(os.environ['BATCH_CACHE_DIR'], frame)
if not os.path.exists(framebatchdir):
    from batchEnvLib import create_lics_cache_dir
    from configLib import config
    srcDir = config.get('Env','SourceDir')
    cacheDir = os.environ['BATCH_CACHE_DIR']
    print('copying frame data from licsar database')
    create_lics_cache_dir(frame,srcDir,cacheDir)

hgt=os.path.join(os.environ['LiCSAR_public'], str(int(frame[:3])), frame, 'metadata', frame+'.geo.hgt.tif')
a=rioxarray.open_rasterio(hgt)
medhgt=round(float(a.sel(x=(lon-radius_deg, lon+radius_deg), y=(lat+radius_deg, lat-radius_deg), method='nearest').median()))

# running the clipping
clipcmd = "clip_slc.sh "+str(sid)+" "+str(lon-radius_deg)+" "+str(lon+radius_deg)+" "
clipcmd =     clipcmd   +str(lat-radius_deg)+" "+str(lat+radius_deg)+" "
clipcmd =     clipcmd   +str(medhgt)+" "+str(resol)+" 0"

os.chdir(framebatchdir)
os.system(clipcmd)
