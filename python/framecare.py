#!/usr/bin/env python

# Mar 2020+ - Milan Lazecky

import os, glob
import subprocess as subp
import LiCSquery as lq
from volcdb import *
from LiCSAR_misc import *
import datetime as dt
import fiona
import pandas as pd
import geopandas as gpd
from shapely.wkt import loads
from shapely.geometry import Polygon
import matplotlib.pyplot as plt
import LiCSAR_lib.LiCSAR_misc as misc
import s1data as s1
import numpy as np
import time

try:
    #gpd.io.file.fiona.drvsupport.supported_drivers['KML'] = 'rw'
    fiona.drvsupport.supported_drivers['KML'] = 'rw'
    fiona.drvsupport.supported_drivers['LIBKML'] = 'rw'
except:
    print('WARNING: cannot load KML support')

import rioxarray
# for estimation of bperp based on overlapping burst ID:
from orbit_lib import *
try:
    import nvector as nv
except:
    print('warning, nvector not loaded - bperp estimation will not work')

pubdir = os.environ['LiCSAR_public']
procdir = os.environ['LiCSAR_procdir']


#'''
# notes:
# this is how i imported burst db - first i converted them from sqlite3 to geojson
# then i did, in /gws/nopw/j04/nceo_geohazards_vol1/projects/LiCS/proc/current/burst_database/IW/sqlite:

#import geopandas as gpd
#import shapely
#import time
#import LiCSquery as lq

#aa=gpd.read_file('burst_map.geojson')
#aa=aa[aa.burst_id>56099]
#aa['geometry']=aa['geometry'].convex_hull

#def _to_2d(x, y, z):
#    return tuple(filter(None, [x, y]))

#aa['geometry'] = aa['geometry'].apply(lambda x: shapely.ops.transform(_to_2d, x))

# now it is ready to import to database:
#for i,j in aa.iterrows():
#    print(i)
#    res = store_burst_geom(j[0], int(j[1][-1]), j[2], j[3], j[4][0], j[5].wkt)
#    #time.sleep(0.25)

#lon1=72.510
#lon2=72.845
#lat1=38.130
#lat2=38.365
#resol_m=30
#frame='100A_05236_141313'
#sid='SAREZ'
#fc.subset_initialise_corners(frame, lon1, lon2, lat1, lat2, sid)




def get_first_common_time(frame, date):
    ''' ML 2024 - sorry for short description
    this will get first time acquired in both frame and first file related to the given frame epoch. For bperp calculation..
    date=dt.datetime.strptime(date,'%Y%m%d').date()
    '''
    epochfile1 = get_frame_files_date(frame,date)[0][1]
    s1ab = epochfile1.split('_')[0]
    epochstart = get_time_of_file(epochfile1)
    epochbursts = sqlout2list(get_bursts_in_file(epochfile1))
    epochbursts.sort()
    epochfirstburst = epochbursts[0]
    framebursts = sqlout2list(get_bidtanxs_in_frame(frame))
    framebursts.sort()
    for e in epochbursts:
        if e in framebursts:
            break
    commonburst = e
    diffinseconds = (int(commonburst.split('_')[-1])-int(epochfirstburst.split('_')[-1]))*0.1 + 2.75/2  # adding half of the burst time as will work with central common point
    epochcommontime = epochstart+dt.timedelta(seconds=diffinseconds)
    # but need to get also avg range, so:
    polyy=get_polygon_from_bidtanx(commonburst)
    commonpoint = nv.GeoPoint(longitude=polyy.centroid.x, latitude=polyy.centroid.y, degrees=True)
    return commonburst, epochcommontime, s1ab, commonpoint


def estimate_bperps(frame, epochs = None, return_epochsdt=True, return_alphas = False):
    ''' Estimate Bperps based on orbit files. Working for LiCSAR frames (thanks to the burst database information).
    Epochs is list as e.g. ['20150202',...]. If epochs is None, it will estimate this for all processed frame epochs.
    if return_epochsdt, it will return also central time for each epoch.
    I enjoyed this. ML
    #### info from http://doris.tudelft.nl/usermanual/node182.html helped but there seems to be issue with sign!
    e.g. estimate_bperps(frame='002A_05136_020502', epochs=['20150202'], return_epochsdt=True)
    Note: ETA of processing time is about 2 s/epoch

    return_alphas only if return_epochsdt..
    '''
    start = time.time()
    if type(epochs) == type(None):
        print('getting all epochs for the frame ' + frame)
        epochs = get_epochs(frame)
    print('estimating Bperp for '+str(len(epochs))+' epochs. ETA '+str(round(len(epochs)*1.9))+' sec')
    # Getting base data for prime epoch
    primepochdt = get_master(frame,
                             asdatetime=True)  # this dt is center time of the frame - will use it to get tdelta, so we can have quite accurate center time for given epoch
    pb, pt, ps1ab, pcp = get_first_common_time(frame, primepochdt.date())
    porbit = get_orbit_filenames_for_datetime(pt, producttype='POEORB', s1ab=ps1ab)[-1]
    porbitxr = load_eof(porbit)
    #H = getHeading(porbitxr, pt, spacing=1) # ok but that's on satellite level... let's use frame info instead?
    metaf = os.path.join(get_frame_path(frame, 'public'), 'metadata', 'metadata.txt')
    H = float(misc.grep1line('heading', metaf).split('=')[-1]) # OK.. seems this heading fits better to the GAMMA estimates..
    # ploc = get_coords_in_time(porbitxr, pt, method='cubic', return_as_nv = True)
    #
    Bperps = []
    central_etimes = []
    alphas = []
    # Do this for every epoch:
    # e = epochs[0]
    for e in epochs:
        ## first get base data for that epoch
        eb, et, es1ab, ecp = get_first_common_time(frame, dt.datetime.strptime(e, '%Y%m%d').date())
        epdbt = (int(eb.split('_')[-1]) - int(
            pb.split('_')[-1])) * 0.1  # difference in seconds from first prime (frame) burst. Coarse info!
        primetime, epochtime = pt + dt.timedelta(seconds=epdbt), et  # both are coarse estimates
        try:
            eorbit = get_orbit_filenames_for_datetime(et, producttype='POEORB', s1ab=es1ab)[-1]
        except:
            print('ERROR getting orbit files for epoch '+e+'. Trying RESORBs.')
            try:
                eorbit = get_orbit_filenames_for_datetime(et, producttype='RESORB', s1ab=es1ab)[-1]
            except:
                print('... this also did not work. Skipping')
                Bperps.append(0)
                central_etimes.append(np.nan)
                continue
        eorbitxr = load_eof(eorbit)
        #
        # get real ploc (prime epoch sat location when observing mid-burst)
        # satalt = get_sat_altitude_above_point(latlon_sat[0], latlon_sat[1], porbitxr, pt)
        ploc, ptime = get_satpos_observing_point(porbitxr, ecp,
                                                 primetime)  # nv.GeoPoint(latitude = latlon_sat[0], longitude=latlon_sat[1], z=satalt)
        #
        # same for epochtime
        # eloc = get_coords_in_time(eorbitxr, epochtime, method='cubic', return_as_nv = True)
        eloc, etime = get_satpos_observing_point(eorbitxr, ecp, epochtime)
        # print(eloc, etime)
        #
        # calculate Bperp (based on doris manual, and some own thinking)
        B = nv.delta_E(ploc, eloc).length #
        # Bpar = ploc.z - eloc.z   # but Bpar is w.r.t. range to surface (need inc angle)
        # Bpar = nv.diff_positions(ploc, ecp).length - nv.diff_positions(eloc, ecp).length  # still not the proper geometry
        # actually could have used this - more correct is below - but the diff was very small (0.1 m)
        aa = nv.delta_E(eloc, ecp).length
        cc = nv.delta_E(ploc, ecp).length
        a = 2
        b = -2 * cc
        c = cc * cc - aa * aa - B * B
        D = b * b - 4 * a * c
        x1 = (-b + np.sqrt(D)) / (2 * a)
        x2 = (-b - np.sqrt(D)) / (2 * a)
        Bpar = np.min(np.abs([x1, x2]))  # that's fine as we need only abs value..
        Bperp = np.sqrt(B * B - Bpar * Bpar)
        #
        # get sign.. should investigate alpha-H-90 for right looking sat, thus cosinus
        alpha = ploc.distance_and_azimuth(eloc, long_unroll=True, degrees=True)[2] # no big diff between 1 and 2, should be 2 i think
        #Bperpsign = -1 * np.sign(np.cos(np.deg2rad(alpha - H)))  # check sign - OK... but maybe not???
        # improve by adding the 90 deg just for clarity:
        #Bperpsign = -1 * np.sign(np.sin(np.deg2rad(H + 90 - alpha)))   # this SHOULD be correct... but GaMMA switches sign! (opposite to doris standard)
        Bperpsign = np.sign(np.sin(np.deg2rad(H + 90 - alpha)))
        #diffangle = np.deg2rad(H + 90 - alpha)
        #Bperpsign = -1 * np.sign(np.sin(diffangle) * np.cos(diffangle))  # ok, this would mean if the sat is behind ploc in slant, it would have opposite phase meaning.. cross-sight.. makes sense?
        #
        '''
        # doing the lame way:
        anglediff = alpha - H - 90
        if (anglediff >= 0 ) and (anglediff < 180):
            Bperpsign = 1
        elif (anglediff >= -180 ) and (anglediff < 0):
            Bperpsign = -1
        elif (anglediff >= 180 ) and (anglediff < 360):
            Bperpsign = -1
        elif (anglediff >= -360 ) and (anglediff < -180):
            Bperpsign = 1
        else:
            print('unexpected angle - contact earmla to fix this')
        # but this got SAME RESULT :)
        '''
        Bperp = np.int8(Bperpsign * Bperp)
        Bperps.append(Bperp)
        if return_epochsdt:
            # get the diff from the central time of prime epoch
            dtime_sec = ptime.timestamp() - primepochdt.timestamp()
            #
            # add this difference to the given epoch (convert it to the central time)
            central_etime = etime + pd.Timedelta(seconds=dtime_sec)
            central_etimes.append(central_etime)
            # debug only: central_etimes.append(alpha)
            if return_alphas:
                alphas.append(alpha)
    elapsed_time = time.time() - start
    hour = int(elapsed_time / 3600)
    minite = int(np.mod((elapsed_time / 60), 60))
    sec = int(np.mod(elapsed_time, 60))
    print("\nElapsed time: {0:02}h {1:02}m {2:02}s".format(hour, minite, sec))
    if return_epochsdt:
        if not return_alphas:
            return Bperps, central_etimes
        else:
            return Bperps, central_etimes, alphas
    else:
        return Bperps



# bovls solution. Kudos to Muhammet Nergizci, 2023:
def extract_burst_overlaps(frame, jsonpath=os.getcwd()):
    bovlfile = os.path.join(jsonpath, frame + '.bovls.geojson')
    if not os.path.exists(bovlfile):
        print('extracting burst polygons from LiCSInfo database')
        gpd_bursts = fc.frame2geopandas(frame, use_s1burst=True)
        gpd_bursts.to_file(bovlfile, driver='GeoJSON')

    # Read GeoJSON data
    data_temp = gpd.read_file(bovlfile)

    # Change CRS to EPSG:4326
    data_temp = data_temp.to_crs(epsg=4326)

    # Extract subswath information
    if frame.startswith('00'):
        data_temp['swath'] = data_temp.burstID.str[4]
    elif frame.startswith('0'):
        data_temp['swath'] = data_temp.burstID.str[5]
    else:
        data_temp['swath'] = data_temp.burstID.str[6]

    # Divide frame into subswaths
    data_temp = data_temp.sort_values(by=['burstID']).reset_index(drop=True)
    gpd_overlaps = None
    swathdict = dict()
    # ML: a fix to handle less than 3 swaths
    for swath in data_temp.swath.unique():
        swdata = data_temp[data_temp.swath == swath]
        # Divide burst overlaps into odd and even numbers
        a1 = swdata.iloc[::2]
        b1 = swdata.iloc[1::2]
        # Find burst overlaps
        sw_overlaps = gpd.overlay(a1, b1, how='intersection')
        swathdict[int(swath)] = sw_overlaps
        if type(gpd_overlaps) == type(None):
            gpd_overlaps = sw_overlaps
        else:
            gpd_overlaps = pd.concat([gpd_overlaps, sw_overlaps], ignore_index=True)
    return gpd_overlaps, swathdict


def get_frame_path(frame, dirtype = 'procdir'):
    """Will get expected path for the frame.
       dirtype is either 'procdir' or 'public' """
    track=int(frame[:3])
    framepath = os.path.join(os.environ['LiCSAR_'+dirtype],str(track),frame)
    return framepath


def lonlat_to_poly(lon1, lon2, lat1, lat2):
    # sort the coordinates
    lon1,lon2=sorted([lon1,lon2])
    lat1,lat2=sorted([lat1,lat2])
    lonlats = [(lon1,lat1), (lon1,lat2), (lon2,lat2), (lon2,lat1), (lon1,lat1)]
    polygon = Polygon(lonlats)
    return polygon


def subset_get_frames(lon1, lon2, lat1, lat2, full_overlap=True, only_initialised=False):
    """This will get frames that overlap with given coordinates.
    """
    # sort the coordinates
    lon1,lon2=sorted([lon1,lon2])
    lat1,lat2=sorted([lat1,lat2])
    lonlats = [(lon1,lat1), (lon1,lat2), (lon2,lat2), (lon2,lat1), (lon1,lat1)]
    polygon = Polygon(lonlats)
    #wkt = polygon.wkt
    frames = lq.sqlout2list(get_frames_in_lonlat((lon1+lon2)/2,(lat1+lat2)/2))
    framesok = []
    for frame in frames:
        framepoly=lq.get_polygon_from_frame(frame)
        if only_initialised:
            if not os.path.exists(get_frame_path(frame)):
                continue
        if full_overlap:
            if framepoly.contains(polygon):
                framesok.append(frame)
        else:
            if framepoly.contains(polygon) or framepoly.overlaps(polygon):
                framesok.append(frame)
    return framesok


def vis_subset_frames(lon1, lon2, lat1, lat2):
    frames = subset_get_frames(lon1, lon2, lat1, lat2)
    poly=lonlat_to_poly(lon1, lon2, lat1, lat2)
    tovis=[poly]
    for frame in frames:
        framepoly=lq.get_polygon_from_frame(frame)
        tovis.append(framepoly)
    vis_aoi(tovis)


'''
sid='angren'
frames=subset_get_frames(lon1, lon2, lat1, lat2, full_overlap=True, only_initialised=True)

for frame in frames:
    subset_initialise_corners(frame, lon1, lon2, lat1, lat2, sid, is_volc = False, resol_m=30)


for frame in frames:
    cmd = 'framebatch_update_frame.sh -P '+frame+' upfill'
    os.system(cmd)
'''

def subset_initialise_corners(frame, lon1, lon2, lat1, lat2, sid, is_volc = False, resol_m=30):
    """This will initialise a subset given by corner lon/lat-s.
    The results will be stored in $LiCSAR_procdir/subsets
    
    Args:
        frame (str): frame ID,
        lon1, lon2 (float, float): corner longitudes (no need to be sorted)
        lat1, lat2 (float, float): corner latitudes (no need to be sorted)
        sid (str):  string ID (for volcano, use the volclip id (vid) instead of volcano ID (volcid) to keep consistence!)
        is_volc (bool): if true, it will set the output folder $LiCSAR_procdir/subsets/volc
        resol_m (float): output resolution in metres to have geocoding table ready in (note, RSLCs are anyway in full res)
    """
    if is_volc:
        sidpath = 'volc/'+sid
    else:
        sidpath = sid
    #
    resol=resol_m/111111 #0.00027
    resol=round(resol,6)
    # sort the coordinates
    lon1,lon2=sorted([lon1,lon2])
    lat1,lat2=sorted([lat1,lat2])
    #
    track=str(int(frame[0:3]))
    '''
        track=str(int(frame[0:3]))
    framedir = os.path.join(os.environ['LiCSAR_procdir'],track,frame)
    
    subsetdir = os.path.join(os.environ['LiCSAR_procdir'],'subsets',sidpath,frame[:4])
    if os.path.exists(subsetdir):
        print('the subset directory exists. continuing anyway..')
    if not os.path.exists(os.path.join(framedir, 'subsets')):
        os.mkdir(os.path.join(framedir, 'subsets'))
    #
    # get median height
    print('getting median height')
    hgt=os.path.join(os.environ['LiCSAR_public'], str(int(frame[:3])), frame, 'metadata', frame+'.geo.hgt.tif')
    a=rioxarray.open_rasterio(hgt)
    a=a.sortby(['x','y'])
    medhgt=round(float(a.sel(x=slice(lon1,lon2), y=slice(lat1, lat2)).median()))
    #medhgt=round(float(a.sel(x=(lon1,lon2), y=(lat1, lat2), method='nearest').median()))
    print('... as {} m'.format(str(medhgt)))
    #
    # running the clipping in init-only mode
    clipcmd = "cd "+framedir+"; "
    clipcmd = clipcmd + "clip_slc.sh "+subsetdir+" "+str(lon1)+" "+str(lon2)+" "
    clipcmd = clipcmd +str(lat1)+" "+str(lat2)+" "
    clipcmd = clipcmd +str(medhgt)+" "+str(resol)+" 0 1"
    #
    if os.path.exists(subsetdir):
        print('this subset already exists in:')
        print(subsetdir)
        print('cancelling for now - you may do this manually adapting:')
        print(clipcmd)
    '''
    framedir = os.path.join(os.environ['LiCSAR_procdir'],track,frame)
    if not os.path.exists(framedir):
        print('error, seems the frame was not initialised, cancelling')
        return False
    subsetdir = os.path.join(os.environ['LiCSAR_procdir'],'subsets',sidpath,frame[:4])
    if os.path.exists(subsetdir):
        print('the subset directory exists. cancelling - please delete manually. path:') #'continuing anyway..')
        print(subsetdir)
        return False
    if not os.path.exists(os.path.join(framedir, 'subsets')):
        os.mkdir(os.path.join(framedir, 'subsets'))
    #
    # get median height
    print('getting median height')
    hgt=os.path.join(os.environ['LiCSAR_public'], str(int(frame[:3])), frame, 'metadata', frame+'.geo.hgt.tif')
    a=rioxarray.open_rasterio(hgt)
    a=a.sortby(['x','y'])
    a=a.where(a>5)
    medhgt=a.sel(x=slice(lon1,lon2), y=slice(lat1, lat2)).median()
    if np.isnan(medhgt) or medhgt == 0:
        medhgt = 1
    else:
        medhgt=round(float(medhgt))
    #medhgt=round(float(a.sel(x=(lon1,lon2), y=(lat1, lat2), method='nearest').median()))
    print('... as {} m'.format(str(medhgt)))
    #
    # running the clipping in init-only mode
    clipcmd = "cd "+framedir+"; "
    clipcmd = clipcmd + "clip_slc.sh "+subsetdir+" "+str(lon1)+" "+str(lon2)+" "
    clipcmd = clipcmd +str(lat1)+" "+str(lat2)+" "
    clipcmd = clipcmd +str(medhgt)+" "+str(resol)+" 0 1"
    #
    if os.path.exists(subsetdir):
        print('this subset already exists in:')
        print(subsetdir)
        print('cancelling for now - you may do this manually adapting:')
        print(clipcmd)
        return False
    #
    print('initializing the subset')
    os.chdir(framedir)
    print(clipcmd)
    os.system(clipcmd)
    if os.path.exists(subsetdir):
        subsetlink = os.path.join(framedir, 'subsets', sid)
        if not os.path.exists(subsetlink):
            os.symlink(subsetdir, subsetlink)
    else:
        print('some error occurred and the output dir was not created')
    return


def subset_initialise_centre_coords(frame, clon, clat, sid, is_volc = False, radius_km = 25/2, resol_m=30):
    """This will initialise a subset given by centre lon/lat and radius in km.
    The results will be stored in \$LiCSAR_procdir/subsets
    
    Args:
        frame (str): frame ID,
        clon (float): centre longitude,
        clat (float): centre latitude,
        sid (str):  string ID (for volcano, use its volcano ID number)
        is_volc (bool): if true, it will set the output folder \$LiCSAR_procdir/subsets/volc
        radius_km (float): radius (half of the diameter) of the subset scene, in km
        resol_m (float): output resolution in metres to have geocoding table ready in (note, RSLCs are anyway in full res)
    """
    
    # BASICS
    radius_deg=radius_km/111
    lon1=clon-radius_deg
    lon2=clon+radius_deg
    lat1=clat-radius_deg
    lat2=clat+radius_deg
    subset_initialise_corners(frame, lon1, lon2, lat1, lat2, sid, is_volc = is_volc, resol_m=resol_m)
    return


def make_subsets_volcano(volcid):
    """Makes subset clips for the volcano with given ID"""
    volcvids=get_volclip_vids(volcid)
    for vid in volcvids:
        make_subsets_volclip(vid)


def make_subsets_volclip(vid):
    """Makes subset clips for the volc_frame_clip id vid"""
    volc = get_volclip_info(vid)
    if type(volc) == type(False):
        print('no records found')
        return
    print('Processing '+volc.name)
    # load volc_frame_clips info, get frames, and then:
    for frame in volc.polyid_name:
        print('creating subset for frame '+frame)
        if not volc.geometry and volc.diameter_km:
            rc = subset_initialise_centre_coords(frame, volc.lon, volc.lat, sid=str(vid), is_volc = True, radius_km = volc.diameter_km/2, resol_m=volc.resolution_m)
        else:
            lon1, lon2, lat1, lat2 = lq.get_boundary_lonlats(volc.geometry)
            rc = subset_initialise_corners(frame, lon1, lon2, lat1, lat2, sid=str(vid), is_volc = True, resol_m=volc.resolution_m)


def check_and_fix_burst(mburst, framebursts):
    # to get mbursts of a zip file, e.g.:
    # frame = '...'
    # filename = 'S1A_IW_SLC__1SDV_20210429T114802_20210429T114829_037665_047199_F24F.zip'
    # mbursts = fc.lq.sqlout2list(fc.lq.get_bursts_in_file(filename))
    # framebursts = fc.lq.sqlout2list(fc.lq.get_bidtanxs_in_frame(frame))
    # for mburst in mbursts: fc.check_and_fix_burst(mburst, framebursts)
    changed = False
    if mburst in framebursts:
        return changed
    tr=int(mburst.split('_')[0])
    iw=mburst.split('_')[1]
    tanx=int(mburst.split('_')[2])
    #
    for fburst in framebursts:
        iwf=fburst.split('_')[1]
        if iwf == iw:
            tanxf=int(fburst.split('_')[2])
            # checking in a 'relaxed' tolerance (0.8 s)
            if abs(tanx - tanxf) < 8:
                # just to make sure they are both of the same pass..
                if lq.get_orbdir_from_bidtanx(fburst) == lq.get_orbdir_from_bidtanx(mburst):
                    # check if their geometries overlap
                    fb_gpd = bursts2geopandas([fburst])
                    mb_gpd = bursts2geopandas([mburst])
                    if fb_gpd.overlaps(mb_gpd).values[0]:
                        print('we (very) probably found a cross-defined burst. fixing/merging to one')
                        print(mburst+' -> '+fburst)
                        lq.rename_burst(mburst, fburst)
                        changed = True
    return changed



def check_and_fix_all_bursts_in_frame(frame):
    t1 = '2014-10-01'
    t2 = dt.datetime.now().date()
    framefiles = lq.get_frame_files_period(frame,t1,t2)
    framebursts = lq.sqlout2list(lq.get_bidtanxs_in_frame(frame))
    fdates = []
    noch = 0
    for framefile in framefiles:
        filename=framefile[2]+'.zip'
        print('checking '+filename)
        mbursts = lq.sqlout2list(lq.get_bursts_in_file(filename))
        # visual check
        # from matplotlib import pyplot as plt
        # bursts_gpd = bursts2geopandas(mbursts)
        # frame_gpd = bursts2geopandas(framebursts)
        # bursts_gpd.plot()
        # frame_gpd.plot()
        # plt.show()

        for mburst in mbursts:
            changed = check_and_fix_burst(mburst, framebursts)
            if changed:
                noch = noch + 1
                fdate = filename[17:25]
                fdates.append(fdate)
    fdates = list(set(fdates))
    print('additionally checking only burst ids of similar tracks')
    print('(same orbit pass direction, relorb+-1)')
    #trackid = frame[:4]
    #for fburst in framebursts:
    track = int(frame[:3]) #int(fburst.split('_')[0])
    for cant in [str(track-1), str(track), str(track+1)]:
        if cant == '176':
            cant = '001'
        if cant == '0':
            cant = '175'
        if len(cant) == 1:
            cant = '00'+cant
        if len(cant) == 2:
            cant = '0'+cant
        trackid = cant+frame[3]
        #canfburst = str(cant)+'_'+fburst.split('_')[1]+'_'+fburst.split('_')[2]
        canfbursts = lq.get_bidtanxs_in_track(trackid)
        try:
            canfbursts = lq.sqlout2list(canfbursts)
            for canfburst in canfbursts:
                changed = check_and_fix_burst(canfburst, framebursts)
                if changed:
                    noch = noch + 1
        except:
            print('no bursts in the trackid '+trackid)
    print(str(noch)+' burst definitions changed to fit the frame burst IDs')
    if noch > 0:
        print('you may want to check following epochs:')
        for fdate in fdates:
            print('frame {0}: {1}'.format(frame, fdate))
            #print('remove_from_lics.sh {0} {1}'.format(frame, fdate))

'''
check these frames:
['149D_05278_131313', '150D_05107_131313', '150D_05306_131313', '151D_05241_131313']
['149D_05425_060707', '150D_05306_131313', '150D_05505_131313', '151D_05440_131313']
['149D_05278_131313', '150D_05107_131313', '150D_05306_131313', '151D_05241_131313']

'''

def check_and_fix_all_files_in_frame(frame):
    t1 = '2014-10-01'
    t2 = dt.datetime.now().date()
    files = lq.get_frame_files_period(frame, t1, t2, only_file_title = True)
    files = lq.sqlout2list(files)
    i = 0
    lenf = len(files)
    for f in files:
        i = i+1
        print('['+str(i)+'/'+str(lenf)+'] checking file '+f)
        check_bursts_in_file(f)


def check_and_fix_burst_supershifts_in_frame(frame, viewerror = True):
    frame_wkt = lq.geom_from_polygs2geom(frame)
    framepoly = loads(frame_wkt)
    framepoly_gpd = gpd.GeoSeries(framepoly)
    frame_bursts = lq.sqlout2list(lq.get_bidtanxs_in_frame(frame))
    fgpd = bursts2geopandas(frame_bursts)
    #b1 = fgpd.iloc[0]
    # 4.5 degrees in WGS-84 are approx 500 km - that should be enough to compare from the frame polygon centroid
    cluster1 = fgpd[fgpd.geometry.centroid.distance(framepoly.centroid) <= 4.5]
    cluster2 = fgpd[fgpd.geometry.centroid.distance(framepoly.centroid) > 4.5]
    #polyid = lq.sqlout2list(lq.get_frame_polyid(frame))[0]
    if not cluster2.empty:
        print('here we are - two burst clusters!')
        # checking for the overlap anyways
        if not framepoly.overlaps(cluster1.unary_union):
            badbursts_gpd = cluster1
            goodbursts_gpd = cluster2
        elif not framepoly.overlaps(cluster2.unary_union):
            badbursts_gpd = cluster2
            goodbursts_gpd = cluster1
        if viewerror:
            print('this is how the frame should look like:')
            framepoly_gpd.plot()
            plt.show()
            print('and this is how it looks with the current burst definitions')
            vis_frame(frame)
        #print('trying to solve it - first find one file that has the burst as bad one')
        check_and_fix_all_files_in_frame(frame)
        '''
        for bid in badbursts_gpd.burstID.values:
            filewithbidasbad = ''
            repeat = True
            filescheck = files.copy()
            while repeat:
                filewithbidasbad = ''
                for fileid in filescheck:
                    print(fileid)
                    is_bid_bad_there = check_bursts_in_file(fileid, badburstfind = bid)
                    if is_bid_bad_there == 'yes':
                        #now check if the file has some of the good bids, i.e. if it really is part of the frame
                        filebursts = lq.sqlout2list(lq.get_bursts_in_file(fileid))
                        for fbur in filebursts:
                            if fbur in goodbursts_gpd.burstID.values:
                                filewithbidasbad = fileid
                                break
                        if filewithbidasbad:
                            break
                if not filewithbidasbad:
                    print('no file with this burst as bad one, skipping')
                    repeat = False
                    continue
                #check_bursts_in_file(filewithbidasbad)
                lq.delete_file_from_db(filewithbidasbad, 'name')
                #print('debug')
                #print(filewithbidasbad)
                filepath = s1.get_neodc_path_images(filewithbidasbad, file_or_meta = True)[0]
                #this should regenerate the missing burst
                outchars = ingest_file_to_licsinfo(filepath)
                if outchars:
                    if outchars<200:
                        print('did not help')
                        filescheck.remove(filewithbidasbad)
                        repeat = True
                    else:
                        print('YESSS, the reingested image created new bursts!!!!!')
                        repeat = False
        '''
        # now all the missing bursts probably exist, so let's try getting them in the frame overlap + check colat and exchange bids
        minlon, minlat, maxlon, maxlat = framepoly.bounds
        track = int(frame[:3])
        burstcands = []
        for relorb in [track-1, track, track+1]:
            if relorb == 0: relorb = 175
            if relorb == 176: relorb = 1
            burstcandsT = lq.sqlout2list(lq.get_bursts_in_polygon(minlon, maxlon, minlat, maxlat, relorb))
            for b in burstcandsT:
                burstcands.append(b)
        # now check their number etc.
        #and if all ok, use them instead of the bad ones - replace them
        frame_bursts_to_change = []
        for b in frame_bursts:
            if not b in burstcands:
                frame_bursts_to_change.append(b)
            else:
                burstcands.remove(b)
        if len(frame_bursts_to_change)>len(burstcands):
            print('ERROR - not enough burst candidates - cannot exchange all bursts, cancelling')
            return False
        else:
            #for swath in [1,2,3]:
            frame_bursts_to_change_out = frame_bursts_to_change.copy()
            for fb in frame_bursts_to_change:
                print('checking burst '+fb)
                sw = fb.split('_')[1]
                tanx = fb.split('_')[2]
                for bc in burstcands:
                    if sw == bc.split('_')[1]:
                        if abs(int(bc.split('_')[2])-int(tanx)) < 10:
                            print('exchanging {0} -> {1}'.format(fb,bc))
                            lq.replace_bidtanx_in_frame(frame, fb, bc)
                            frame_bursts_to_change_out.remove(fb)
                            burstcands.remove(bc)
                            break
            if len(frame_bursts_to_change_out) > 0:
                print('ERROR - not all frame bursts were replaced - the problematic bursts are returned:')
                print(frame_bursts_to_change_out)
                print('potential burst candidates were:')
                print(burstcands)
                return [frame_bursts_to_change_out, burstcands]
            else:
                print('the frame was corrected properly!')
                if viewerror:
                    print('see yourself')
                    vis_frame(frame)
            #return burstcands, frame_bursts_to_change
    else:
        print('bursts of this frame are ok')
        return True

# to get all files that are not participating in any frame
#sql = "select f.name from files f where f.fid not in ( select fb.fid from files2bursts fb inner join polygs2bursts pb on fb.bid=pb.bid );"

import time
def process_all_frames():
    badtracks = []
    for relorb in range(1,175): #,175): #   86 need to do: 97-99
        try:
            print('preparing track '+str(relorb+1))
            allframes = lq.sqlout2list(lq.get_frames_in_orbit(relorb+1))
        except:
            print('error in relorb '+str(relorb+1))
            badtracks.append(relorb+1)
            continue
        for frame in allframes:
            print(frame)
            time.sleep(45)
            #just change the function here
            try:
                #rc = check_and_fix_burst_supershifts_in_frame(frame, viewerror = False)
                # to process ALL FILES! (that are related to some any frame)
                rc = check_and_fix_burst_supershifts_in_frame_files(frame, viewerror = False)
            except:
                print('some error during processing frame '+frame)
    return badtracks


'''
#to get files that are NOT in any frames - we have now over 250k of such files!
sql = "select f.name from files f where f.fid not in ( select fb.fid from files2bursts fb inner join polygs2bursts pb on fb.bid=pb.bid );"
nopolyfiles = lq.do_pd_query(sql)
i=0
filez = nopolyfiles.name.unique()
lenn = len(filez)
for fileid in filez:
    i=i+1
    print('['+str(i)+'/'+str(lenn)+']'+fileid)
    lq.delete_file_from_db(fileid, col = 'name')
    filepath = s1.get_neodc_path_images(fileid, file_or_meta = True)[0]
    chars = ingest_file_to_licsinfo(filepath)
    print(chars)
    #time.sleep(2)
    #if not check_bursts_in_file(fileid):
    #    print('error in file '+fileid)
'''

def check_and_fix_burst_supershifts_in_frame_files(frame, viewerror = False, force_reingest = True):
    #first get all files in frame and check them one by one:
    t1 = '2014-10-01'
    t2 = dt.datetime.now().date()
    files = lq.get_frame_files_period(frame, t1, t2, only_file_title = True)
    files = lq.sqlout2list(files)
    for fileid in files:
        if force_reingest:
            print('reingesting '+fileid)
            reingest_file(fileid)
        else:
            if not check_bursts_in_file(fileid):
                print('error in file '+fileid)
                if viewerror:
                    print('see yourself the current situation')
                    bursts = lq.sqlout2list(lq.get_bursts_in_file(fileid))
                    vis_bidtanxs(bursts)


def reingest_all_files_in_frame(frame):
    t1 = '2014-10-01'
    t2 = dt.datetime.now().date()
    files = lq.get_frame_files_period(frame, t1, t2, only_file_title = True)
    files = lq.sqlout2list(files)
    for fileid in files:
        reingest_file(fileid)


def vis_file(fileid):
    """ Visualize bursts of given file.
    """
    fbursts = lq.get_bursts_in_file(fileid)
    fbursts = lq.sqlout2list(fbursts)
    #filegpd = bursts2geopandas(fbursts)
    vis_bidtanxs(fbursts)


def check_bursts_in_file(fileid = 'S1A_IW_SLC__1SDV_20210908T235238_20210908T235305_039597_04AE3C_4CA7', badburstfind = None, autocorrect = True):
    fbursts = lq.get_bursts_in_file(fileid)
    fbursts = lq.sqlout2list(fbursts)
    if not fbursts:
        print('no bursts found for this file. trying to reingest it')
        ingest_file_to_licsinfo(fileid, False)
        return False
    filegpd = bursts2geopandas(fbursts)
    b1 = filegpd.iloc[0]
    # not perfect solution - there can be more than 2 clusters!!!!!!
    # but now, just removing and reingesting the file should help, anyway
    # 4.5 degrees in WGS-84 are approx 500 km - that should be enough..
    cluster1 = filegpd[filegpd.geometry.centroid.distance(b1.geometry.centroid) <= 4.5]
    cluster2 = filegpd[filegpd.geometry.centroid.distance(b1.geometry.centroid) > 4.5]
    if not cluster2.empty:
        print('here we are - two burst clusters!')
        info = s1.get_info_pd(fileid)
        try:
            filepoly = loads(info.footprint.values[0])
        except:
            print('some error loading footprint from scihub')
            print('(making sure things work fine - reingesting this file)')
            filepath = s1.get_neodc_path_images(fileid, file_or_meta = True)[0]
            chars = ingest_file_to_licsinfo(filepath)
            return True
        if not filepoly.overlaps(cluster1.unary_union):
            badbursts_gpd = cluster1
        elif not filepoly.overlaps(cluster2.unary_union):
            badbursts_gpd = cluster2
        else:
            print('weird - both clusters overlap with the original file')
            print('(making sure things work fine - reingesting this file)')
            filepath = s1.get_neodc_path_images(fileid, file_or_meta = True)[0]
            chars = ingest_file_to_licsinfo(filepath)
            return False
        if badburstfind:
            if badburstfind in badbursts_gpd.burstID.values:
                print('this burst is indeed in badbursts')
                return 'yes'
            else:
                return 'no'
        if not autocorrect:
            return badbursts_gpd
        else:
            allremoved = True
            for bid in badbursts_gpd.burstID.values:
                frames = lq.sqlout2list(lq.get_frames_with_burst(bid))
                print('checking '+bid)
                #print(frames)
                if len(frames) == 0:
                    print('no frame is using this burst ID. as it is a bad burst, will remove it now, including files that use it')
                    files2remove = lq.sqlout2list(lq.get_filenames_from_burst(bid))
                    print('removing and reingesting file {}'.format(str(len(files2remove))))
                    for ff in files2remove:
                        lq.delete_file_from_db(ff, col = 'name')
                        filepath = s1.get_neodc_path_images(ff, file_or_meta = True)[0]
                        chars = ingest_file_to_licsinfo(filepath)
                    print('removing the bad burst '+bid)
                    rc = lq.delete_burst_from_db(bid)
                else:
                    #print('this burst is used in following frame(s):')
                    #print(frames)
                    allremoved = False
                    # ye.. or better append and remove dup. but who cares..
                    badframes = frames
            if allremoved:
                print('bad bursts are cleaned! reingesting the file')
            else:
                print('not all bad bursts removed from the database - but reingesting the file to fix it')
                print('SOME of frames still using a bad burst:')
                print(badframes)
            lq.delete_file_from_db(fileid, col = 'name')
            filepath = s1.get_neodc_path_images(fileid, file_or_meta = True)[0]
            chars = ingest_file_to_licsinfo(filepath)
            return True
    else:
        print('bursts of this file are ok')
        return True

'''
filez=filez[4514:]
lenn = len(filez)
i=0
badones = []
for fileid in filez.name.values:
    i=i+1
    print('['+str(i)+'/'+str(lenn)+'] '+fileid)
    if 'IW' in fileid:
        try:
            reingest_file(fileid)
        except:
            print('error with '+fileid)
            badones.append(fileid)
        
        
    time.sleep(5)
    if not check_bursts_in_file(fileid):
        print('error in file '+fileid)

'''

def reingest_file(fileid):
    rc = lq.delete_file_from_db(fileid, col = 'name')
    chars = ingest_file_to_licsinfo(fileid, False)
    return chars


def ingest_file_to_licsinfo(filepath, isfullpath = True):
    """ Will ingest a S1 SLC zip file to the LiCSInfo database.
    If filepath is only filename, it will try find this file in neodc or LiCSAR_SLC"""
    if not isfullpath:
        filepath = s1.get_neodc_path_images(filepath, file_or_meta = True)[0]
    if not os.path.exists(filepath):
        filepath = os.path.join(os.environ['LiCSAR_SLC'], os.path.basename(filepath))
        if not os.path.exists(filepath):
            print('ERROR - this file does not exist')
            return False
        aaaa = subp.check_output(['arch2DB.py','-f',filepath])
    else:
        #cmd = 'arch2DB.py -f {} >/dev/null 2>/dev/null'.format(filepath)
        #cmd = 'arch2DB.py -f {}'.format(filepath)
        #rc = os.system(cmd)
        aaaa = subp.check_output(['arch2DB.py','-f',filepath])
    return len(aaaa)


def get_bidtanxs_from_xy(lon,lat,relorb=None,swath=None, tol=0.05):
    """Gets bursts in given coordinates (and optionally in given track or swath)"""
    bursts = lq.get_bursts_in_xy(lon,lat,relorb,swath,tol)
    bursts = lq.sqlout2list(bursts)
    return bursts


def get_bidtanxs_from_xy_file(intxt, relorb = None):
    """Gets bursts in polygon given by the xy text file."""
    if not os.path.exists(intxt):
        print('ERROR, the file does not exist')
        return False
    lonlat = load_xy(intxt)
    bidtanxs = lq.get_bursts_in_polygon(lonlat[0][0],lonlat[0][-1],lonlat[1][0], lonlat[1][-1], relorb = relorb)
    bidtanxs = lq.sqlout2list(bidtanxs)
    print('check the bursts, e.g. export_bidtanxs_to_kml')
    return bidtanxs


def make_bperp_file(frame, bperp_file, asfonly = False, donotstore = False):
    """Creates baselines file for given frame, by requesting info from ASF,
    and (new in 2024/08, as ASF has too many gaps over winters in N hemisphere - ML),
    if missing, estimate them directly from frame data
    """
    #if preload_if_exists: try preloading and then just filling missing dates"""
    #if preload_if_exists:
    #    try:
    #        prevbp = pd.read_csv(bperp_file, header=None, sep = ' ')
    #        prevbp.columns = ['ref_date', 'date', 'bperp', 'btemp']
    #        
    mid = get_master(frame, asfilenames = True)
    if not mid:
        return False
    bpd = False
    for midf in mid:
        midf=midf.split('.')[0]
        bpd1 = s1.get_bperps_asf(midf)
        if type(bpd) == type(False):
            bpd = bpd1
        else:
            try:
                bpd = pd.concat([bpd, bpd1]).reset_index(drop=True)
                bpd = bpd.drop_duplicates()
            except:
                pass
    # clean it
    torem = bpd[bpd.bperp == 0]
    torem = torem[torem.btemp != 0]
    bpd = bpd.drop(torem.index)
    #
    if not asfonly:
        # get missing epochs:
        allepochs = get_epochs(frame)
        missingepochs = []
        for e in allepochs:
            if e not in bpd.date.values:
                missingepochs.append(e)
        if missingepochs:
            print('ASF missed '+str(len(missingepochs))+' epochs for Bperp estimation. Using a bit coarser but still POD-based approach')
            bperps = estimate_bperps(frame, missingepochs, return_epochsdt=False)
            mdates = []
            btemps = []
            m = get_master(frame)
            for e in missingepochs:
                mdates.append(m)
                btemps.append(datediff(m, e))   # function from LiCSAR_misc
            pdict = {'ref_date': mdates, 'date': missingepochs, 'bperp': bperps, 'btemp': btemps}
            bpd2 = pd.DataFrame(pdict)
            bpd = pd.concat([bpd, bpd2]).reset_index(drop=True)
            bpd = bpd.sort_values('btemp').reset_index(drop=True)
    #
    bpd['bperp']=bpd.bperp.astype(np.int8)
    if not donotstore:
        bpd.to_csv(bperp_file, sep = ' ', index = False, header = False)
    else:
        return bpd


def get_master(frame, asfilenames = False, asdate = False, asdatetime = False, metafile = None):
    """Gets reference epoch of given frame, returns in several ways

    Args:
        frame (str): frame ID
        asfilenames (bool): returns as filenames that were used to create this ref. epoch during init
        asdate (bool): returns as dt.datetime.date
        asdatetime (bool): will include also the acquisition centre time (returns as dt.datetime)
        metafile (str): path to metadata file of the frame. if None, it will search in LiCSAR_public
    """
    if not metafile:
        track=str(int(frame[0:3]))
        metafile = os.path.join(pubdir,track,frame,'metadata','metadata.txt')
    if not os.path.exists(metafile):
        print('frame {} is not initialised'.format(frame))
        return False
    master = misc.grep1line('master',metafile)
    if not master:
        print('error parsing information from metadata.txt')
        return False
    masterdate = master.split('=')[1]
    if asfilenames:
        slcpath = os.path.join(procdir, track, frame, 'SLC', str(masterdate))
        try:
            zipfiles = []
            for zipfile in glob.glob(slcpath+'/S1*zip'):
                zipfiles.append(os.path.basename(zipfile))
            return zipfiles
        except:
            print('error finding zip files in the frame SLC directory')
            return False
    if asdate:
        a = masterdate
        masterdate = dt.date(int(a[:4]),int(a[4:6]),int(a[6:8]))
    if asdatetime:
        a = masterdate
        centime = misc.grep1line('center_time',metafile)
        if not centime:
            print('error parsing center_time information from metadata.txt')
            return False
        centime = centime.split('=')[1].split('.')[0]
        masterdate = dt.datetime(int(a[:4]),int(a[4:6]),int(a[6:8]),
                        int(centime.split(':')[0]),
                        int(centime.split(':')[1]),
                        int(centime.split(':')[2]))
    return masterdate


def get_frame_master_s1ab(frame, metafile = None):
    """ Gets information if the reference epoch of given frame is S1 'A' or 'B'.
    
    Args:
        frame (str): frame id
        metafile (str): if None, it will identify it on LiCSAR_public
    """
    tr = int(frame[:3])
    if not metafile:
        metafile = os.path.join(os.environ['LiCSAR_public'], str(tr), frame, 'metadata', 'metadata.txt')
    if not os.path.exists(metafile):
        print('metadata file does not exist for frame '+frame)
        return 'X'
    primepoch = grep1line('master=',metafile).split('=')[1]
    path_to_slcdir = os.path.join(os.environ['LiCSAR_procdir'], str(tr), frame, 'SLC', primepoch)
    try:
        out = os.path.basename(glob.glob(path_to_slcdir+'/S1*')[0])[2]
    except:
        print('error getting the value for frame '+frame)
        out = 'X'
    return out


def vis_aoi(aoi):
    """to visualize a polygon element ('aoi')
    Note: aoi might be a list of polygons, see subset_get_frames"""
    crs = {'init': 'epsg:4326'}
    if type(aoi)==list:
        aoi_gpd = gpd.GeoDataFrame(crs=crs, geometry=aoi)
        #for a in aoi:
    else:
        aoi_gpd = gpd.GeoDataFrame(index=[0], crs=crs, geometry=[aoi])
    # load world borders for background
    world = gpd.read_file(gpd.datasets.get_path('naturalearth_lowres'))
    base = world.plot(color='lightgrey', edgecolor='white')
    aoi_gpd.plot(ax=base, color='None', edgecolor='black')
    bounds = aoi_gpd.geometry.bounds
    plt.xlim([bounds.minx.min()-2, bounds.maxx.max()+2])
    plt.ylim([bounds.miny.min()-2, bounds.maxy.max()+2])
    plt.grid(color='grey', linestyle='-', linewidth=0.2)
    plt.show()

def vis_bidtanxs(bidtanxs):
    """Visualize list of bursts (use bidtanx id, i.e. e.g. '73_IW1_1234')"""
    tovis = []
    for bid in bidtanxs:
        tovis.append(lq.get_polygon_from_bidtanx(bid))
    vis_aoi(tovis)


def vis_frame(frame):
    """Visualize frame ID"""
    ai = lq.get_bursts_in_frame(frame)
    bidtanxs = lq.sqlout2list(ai)
    vis_bidtanxs(bidtanxs)

def extract_bursts_by_track(bidtanxs, track):
    newbids = []
    for bidtanx in bidtanxs:
        if bidtanx.split('_')[0] == str(track):
            newbids.append(bidtanx)
    return newbids


def bursts2geopandas(bidtanxs, merge = False, use_s1burst = False):
    """Gets geopandas layer for a list of burst IDs (in the form of bidtanx, i.e. e.g. 73_IW1_1234

    Args:
        bidtanxs (list): list of burst ids, e.g. ['73_IW1_1234']
        merge (bool): whether to merge the output into one polygon
        use_s1burst (bool): use the official S-1 burst polygons (more accurate, including burst overlaps)
    """
    # in order to export to KML:
    # frame_gpd.to_file('~/kmls/'+frame+'.kml', driver='KML')
    # or to SHP:
    # frame_gpd.to_file('~/shps/'+frame+'.shp', driver='ESRI Shapefile')
    geometry = []
    crs = {'init': 'epsg:4326'}
    for bidtanx in bidtanxs:
        try:
            orbdir = lq.get_orbdir_from_bidtanx(bidtanx)
            print(orbdir)
        except:
            orbdir = False
        if orbdir:
            break
    if merge == False:
        #if use_s1burst:
        if type(bidtanxs)==list:
            for bid in bidtanxs:
                if use_s1burst:
                    geometry.append(lq.get_s1b_geom_from_bidtanx(bid, opass = orbdir))
                else:
                    geometry.append(lq.get_polygon_from_bidtanx(bid))
            df_name = {'burstID': bidtanxs}
            aoi_gpd = gpd.GeoDataFrame(df_name, crs=crs, geometry=geometry)
        else:
            if use_s1burst:
                geometry.append(lq.get_s1b_geom_from_bidtanx(bidtanxs, opass = orbdir))
            else:
                geometry.append(lq.get_polygon_from_bidtanx(bidtanxs))
            aoi_gpd = gpd.GeoDataFrame(index=[0], crs=crs, geometry=[geometry])
    else:
        polygon = generate_frame_polygon(bidtanxs, orbdir)
        framename = generate_frame_name(bidtanxs)
        #aoi_gpd = gpd.GeoDataFrame(index=[0], crs=crs, geometry=[polygon])
        aoi_gpd = gpd.GeoDataFrame({'frameID': [framename]}, crs=crs, geometry=[polygon])
    return aoi_gpd


def frame2geopandas(frame, brute = False, use_s1burst = False, merge = False):
    """Gets geopandas layer for a frame

    Args:
        frame (str): frame ID
        brute (bool): do not use polygons in LiCSInfo, but regenerate them instead (by quite brute/slow approach)
        merge (bool): whether to merge the bursts into one (frame) polygon
        use_s1burst (bool): use the official S-1 burst polygons (more accurate, including burst overlaps)
    """
    if use_s1burst:
        bidtanxs=lq.get_bidtanxs_in_frame(frame)
        bidtanxs=lq.sqlout2list(bidtanxs)
        return bursts2geopandas(bidtanxs, merge = merge, use_s1burst = use_s1burst)
    if brute:
        gpan = frame2geopandas_brute(frame)
    else:
        if not lq.is_in_polygs2geom(frame):
            print('frame {} has no record in polygs2geom. Recreating'.format(frame))
            gpan = frame2geopandas_brute(frame)
        else:
            #geometry = []
            crs = {'init': 'epsg:4326'}
            wkt = lq.geom_from_polygs2geom(frame)
            geom = loads(wkt)
            #gpan['frameID'] = frame
            gpan = gpd.GeoDataFrame({'frameID': [frame]}, crs=crs, geometry=[geom])
    return gpan


def frame2geopandas_brute(frame):
    bidtanxs = lq.get_bursts_in_frame(frame)
    if not bidtanxs:
        #try it once again
        bidtanxs = lq.get_bursts_in_frame(frame)
        if not bidtanxs:
            print('the frame '+frame+' is not connected to any bursts. removing the frame')
            lq.delete_frame_only(frame)
            return None
    bidtanxs = lq.sqlout2list(bidtanxs)
    try:
        newname = generate_frame_name(bidtanxs)
    except:
        print('some problem generating frame name from the bursts of frame: '+frame)
        return None
    #get the geopandas record
    gpan = bursts2geopandas(bidtanxs, merge = True)
    if gpan.empty:
        return None
    if not newname:
        return None
    if (frame[-6:] != newname[-6:]) or (frame[3] != newname[3]):
        #print('WARNING! This frame changed its definition')
        #print('{0} ---> {1}'.format(frame,newname))
        #print('framecare_rename.sh {0} {1}'.format(frame,newname))
        #rename it in database
        lq.rename_frame(frame,newname)
        #print('now we should do: rename_frame_main(frame,newname)')
        rename_frame_main(frame,newname)
    else:
        #keep the original name if bursts did not change..
        gpan['frameID']=frame
    #outgpd = outgpd.append(gpan, ignore_index=True)
    return gpan

def rename_frame_main(framename,newname, reportcsv = '/gws/nopw/j04/nceo_geohazards_vol1/public/LiCSAR_products/frameid_changes.txt'):
    """
    this function will physically rename a frame (and move folders etc.) - oh, but it doesn't touch the frame def in database! for this, use lq.rename_frame
    """
    track = str(int(framename[0:3]))
    pubpath = os.path.join(pubdir,track,framename)
    procpath = os.path.join(procdir,track,framename)
    newpubpath = os.path.join(pubdir,track,newname)
    newprocpath = os.path.join(procdir,track,newname)
    if os.path.exists(pubpath):
        os.rename(pubpath, newpubpath)
        for fileext in ['.geo.E.tif','.geo.N.tif','.geo.hgt.tif','.geo.U.tif','-poly.txt']:
            oldfile = os.path.join(newpubpath,'metadata',framename+fileext)
            newfile = os.path.join(newpubpath,'metadata',newname+fileext)
            if os.path.exists(oldfile):
                os.rename(oldfile,newfile)
    if os.path.exists(procpath):
        os.rename(procpath, newprocpath)
    if os.path.exists(os.path.join(newprocpath,framename+'-poly.txt')):
        os.remove(os.path.join(newprocpath,framename+'-poly.txt'))
    print('frame {0} renamed to {1}'.format(framename,newname))
    if not os.path.exists(reportcsv):
        with open(reportcsv, 'w') as f:
            f.write('oldname,newname\n')
    with open(reportcsv, 'a') as f:
        f.write('{0},{1}\n'.format(framename, newname))

def get_number_of_ifgs(framename):
    pubdir = os.environ['LiCSAR_public']
    track = str(int(framename[0:3]))
    pubpath = os.path.join(pubdir,track,framename)
    if not os.path.exists(pubpath):
        return 0
    ifgspath = os.path.join(pubpath,'interferograms')
    if not os.path.exists(ifgspath):
        return 0
    filenumber = len(glob.glob1(ifgspath,'2???????_2???????'))
    return filenumber


def get_epochs(framename, return_mli_tifs = False, return_as_dt = False):
    pubdir = os.environ['LiCSAR_public']
    track = str(int(framename[0:3]))
    pubpath = os.path.join(pubdir,track,framename)
    if not os.path.exists(pubpath):
        return False
    epochspath = os.path.join(pubpath,'epochs')
    if not os.path.exists(epochspath):
        return False
    if return_mli_tifs:
        #this will return tif file paths
        return glob.glob(epochspath + "/**/*.geo.mli.tif", recursive = True)
    else:
        epochslist = glob.glob1(epochspath,'2???????')
        if return_as_dt:
            es = []
            for e in epochslist:
                es.append(dt.datetime.strptime(e, '%Y%m%d').date())
            return es
        return epochslist


def get_ifg_list_pubdir(framename):
    pubdir = os.environ['LiCSAR_public']
    track = str(int(framename[0:3]))
    pubpath = os.path.join(pubdir,track,framename)
    if not os.path.exists(pubpath):
        return 0
    ifgspath = os.path.join(pubpath,'interferograms')
    if not os.path.exists(ifgspath):
        return 0
    ifglist = glob.glob1(ifgspath,'2???????_2???????')
    return ifglist


def get_epochs_from_ifg_list_pubdir(framename):
    ifglist = get_ifg_list_pubdir(framename)
    epochs = set()
    if ifglist == 0:
        return 0
    else:
        for ifg in ifglist:
            epochs.add(ifg.split('_')[0])
            epochs.add(ifg.split('_')[1])
    return list(epochs)


def export_frames_to_licsar_csv(framesgpd, outcsv = '/gws/nopw/j04/nceo_geohazards_vol1/public/shared/frames/frames.csv', store_zero = False):
    #print('now we would export the frame to outcsv, including wkb')
    # this will update the csv, not rewrite it..
    if not os.path.exists(outcsv):
        with open(outcsv,'w') as f:
            f.write('the_geom,frame,files,download,direction\n')
    with open(outcsv,'a') as f:
        #extract needed information
        for index, row in framesgpd.iterrows():
            framename = row['frameID']
            track = int(framename[0:3])
            download = "<a href='http://gws-access.ceda.ac.uk/public/nceo_geohazards/LiCSAR_products/{0}/{1}/' target='_blank'>Link<a>".format(str(track),framename)
            orbdir = framename[3]
            if orbdir == 'A':
                direction = 'Ascending'
            elif orbdir == 'D':
                direction = 'Descending'
            else:
                print('wrong framename! Aborting')
                return False
            #get number of files
            files = get_number_of_ifgs(framename)
            #get geometrywkb
            geom = row['geometry'].wkb_hex
            #we do not want to export it in case of no files in public...:
            if ((not store_zero) and files > 0) or store_zero:
                #if frame already in csv file, remove its line and update by new files no.
                if misc.grep1line(framename, outcsv):
                    misc.sed_rmlinematch(framename, outcsv)
                f.write('{0},{1},{2},{3},{4}\n'.format(str(geom), framename, str(files), download, direction))


def store_frame_geometry(framesgpd):
    fileio_error = False
    for index, row in framesgpd.iterrows():
        framename = row['frameID']
        track = int(framename[0:3])
        geom = row['geometry'].wkt
        #update the xy file:
        pubfile = os.path.join(pubdir,str(track),framename,'metadata',framename+'-poly.txt')
        procfile = os.path.join(procdir,str(track),framename,framename+'-poly.txt')
        procframefile = os.path.join(procdir,str(track),framename,'frame.xy')
        xy = row['geometry'].exterior.coords.xy
        x = xy[0]
        y = xy[1]
        for fileout in [pubfile, procfile, procframefile]:
            if os.path.exists(fileout):
                os.remove(fileout)
            try:
                with open(fileout,'w') as f:
                    for i in range(len(x)-1):
                        f.write(str(x[i])+' '+str(y[i])+'\n')
            except:
                fileio_error = True
                #print('warning, {0} could not have been generated'.format(fileout))
        #update the database GIS table
        res = lq.store_frame_geometry(framename, geom)
    return res

def export_geopandas_to_kml(gpan, outfile):
    gpan.to_file(outfile, driver='KML', NameField='frameID')

def bursts_group_to_iws(bidtanxs):
    iw1s = []
    iw2s = []
    iw3s = []
    for bidt in bidtanxs:
        if 'IW1' in bidt:
            iw1s.append(bidt)
        if 'IW2' in bidt:
            iw2s.append(bidt)
        if 'IW3' in bidt:
            iw3s.append(bidt)
    iw1s.sort()
    iw2s.sort()
    iw3s.sort()
    return [iw1s, iw2s, iw3s]

def generate_frame_polygon(bidtanxs, orbdir = None):
    if not orbdir:
        orbdir = lq.get_orbdir_from_bidtanx(bidtanxs[0])
    try:
        burstgpd = bursts2geopandas(bidtanxs)
    except:
        print('some error during bursts2geopandas, maybe mysql problem')
        return None
    #unite bursts, but this will keep errors:
    framegpd = burstgpd.unary_union
    #corrections based on:
    # https://gis.stackexchange.com/questions/277334/shapely-polygon-union-results-in-strange-artifacts-of-tiny-non-overlapping-area
    eps = 0.025
    tolsim = eps
    from shapely.geometry import JOIN_STYLE
    framegpd = framegpd.buffer(eps, 1, join_style=JOIN_STYLE.mitre).buffer(-eps, 1, join_style=JOIN_STYLE.mitre)
    framegpd = framegpd.simplify(tolerance=tolsim)
    #maximal number of points should be 13!
    while len(framegpd.exterior.coords[:])>13:
        tolsim = tolsim+0.001
        framegpd = framegpd.simplify(tolerance=tolsim)
    return Polygon(framegpd.exterior)

def generate_frame_polygon_old(bidtanxs, orbdir):
    [iw1s, iw2s, iw3s] = bursts_group_to_iws(bidtanxs)
    if orbdir == 'A':
        #print('not yet tested')
        iwsmin = 0
        iwsmax = -1
        first_point_id = 0
        second_point_id = 1
        last_point = -1
        prelast_point = -2
    else:
        iwsmin = -1
        iwsmax = 0
        first_point_id = 0
        second_point_id = 1
        last_point = -1
        prelast_point = -2
    minbids = []
    maxbids = []
    for iws in [iw1s, iw2s, iw3s]:
        if len(iws)>0:
            minbids.append(iws[iwsmin])
            maxbids.append(iws[iwsmax])
    lons_poly=[]
    lats_poly=[]
    for bid in minbids:
        bidpoly = lq.get_polygon_from_bidtanx(bid)
        xy = bidpoly.exterior.coords.xy
        x = set()
        y = set()
        for pom in xy[0]: x.add(pom)
        for pom in xy[1]: y.add(pom)
        x = list(x)
        y = list(y)
        x.sort()
        y.sort()
            #get two minimal points of lats
        lats_poly.append(y[first_point_id])
        lats_poly.append(y[second_point_id])
        index_min0 = xy[1].index(y[first_point_id])
        index_min1 = xy[1].index(y[second_point_id])
            #get lons that correspond to their lats
        lons_poly.append(xy[0][index_min0])
        lons_poly.append(xy[0][index_min1])
    maxbids.reverse()
    for bid in maxbids:
        bidpoly = lq.get_polygon_from_bidtanx(bid)
        xy = bidpoly.exterior.coords.xy
        x = []
        y = []
        for pom in xy[0]: x.append(pom)
        for pom in xy[1]: y.append(pom)
        x.sort()
        y.sort()
        #get two maximal points of lats
        lats_poly.append(y[last_point])
        lats_poly.append(y[prelast_point])
        index_max0 = xy[1].index(y[last_point])
        index_max1 = xy[1].index(y[prelast_point])
        lons_poly.append(xy[0][index_max0])
        lons_poly.append(xy[0][index_max1])
    return Polygon(zip(lons_poly, lats_poly))

def generate_frame_name(bidtanxs):
    track = bidtanxs[0].split('_')[0]
    orbdir = lq.get_orbdir_from_bidtanx(bidtanxs[0])
    polyhon = generate_frame_polygon(bidtanxs, orbdir)
    if not polyhon:
        print('some error generating frame polygon - mysql access error?')
        return None
    lat_center = polyhon.centroid.xy[1][0]
    colat = misc.get_colat10(lat_center)
    #print(colat)
    polyid_track = '00'+str(track)+orbdir
    polyid_track = polyid_track[-4:]
    [iw1s, iw2s, iw3s] = bursts_group_to_iws(bidtanxs)
    iw1_str = str(len(iw1s)); iw2_str = str(len(iw2s)); iw3_str = str(len(iw3s))
    if len(iw1s) < 10: iw1_str = '0'+str(len(iw1s))
    if len(iw2s) < 10: iw2_str = '0'+str(len(iw2s))
    if len(iw3s) < 10: iw3_str = '0'+str(len(iw3s))
    polyid_colat10 = str(colat)
    if colat < 10000: polyid_colat10 = '0'+str(colat)
    if colat < 1000: polyid_colat10 = '00'+str(colat)
    if colat < 100: polyid_colat10 = '000'+str(colat)
    if colat < 10: polyid_colat10 = '0000'+str(colat)
    polyid_name = polyid_track+'_'+polyid_colat10+'_'+iw1_str+iw2_str+iw3_str
    return polyid_name

def generate_new_frame(bidtanxs,testonly = True, hicode = None):
    """ Main function to generate new frame definition based on selected bursts
    Args:
        bidtanxs (list): list of burst IDs in the bidtanx form, e.g. ['73_IW1_1234','73_IW1_2345',..]
        testonly (bool): if True, only perform dry run for debugging
        hicode (str or None): special code for non-standard frame resolution; use 'H' for high resolution (1/5 multilook), or 'M' for medium, i.e. 56 m - not much used but should work ok
    """
    #and now i can generate the new frame:
    track = bidtanxs[0].split('_')[0]
    orbdir = lq.get_orbdir_from_bidtanx(bidtanxs[0])
    polyhon = generate_frame_polygon(bidtanxs, orbdir)
    lat_center = polyhon.centroid.xy[1][0]
    colat = misc.get_colat10(lat_center)
    #print(colat)
    polyid_track = '00'+str(track)+orbdir
    polyid_track = polyid_track[-4:]
    [iw1s, iw2s, iw3s] = bursts_group_to_iws(bidtanxs)
    iw1_str = str(len(iw1s)); iw2_str = str(len(iw2s)); iw3_str = str(len(iw3s))
    if len(iw1s) < 10: iw1_str = '0'+str(len(iw1s))
    if len(iw2s) < 10: iw2_str = '0'+str(len(iw2s))
    if len(iw3s) < 10: iw3_str = '0'+str(len(iw3s))
    polyid_colat10 = str(colat)
    if colat < 10000: polyid_colat10 = '0'+str(colat)
    if colat < 1000: polyid_colat10 = '00'+str(colat)
    if colat < 100: polyid_colat10 = '000'+str(colat)
    if colat < 10: polyid_colat10 = '0000'+str(colat)
    polyid_name = polyid_track+'_'+polyid_colat10+'_'+iw1_str+iw2_str+iw3_str
    if hicode:
        polyid_name = polyid_name[:9]+hicode+polyid_name[10:]
    #print(polyid_name)
    sql = "select count(*) from polygs where polyid_name = '{0}';".format(polyid_name)
    polyid_exists = lq.do_query(sql)[0][0]
    if polyid_exists:
        print('the polyid_name '+ polyid_name +' exists, skipping')
        return False
    lats = []
    lons = []
    for i in range(12):
        lats.append('NULL')
        lons.append('NULL')
    #print(len(polyhon.exterior.coords.xy[1]))
    # removing last coordinate as this should be same as the first one
    for i in range(len(polyhon.exterior.coords.xy[1])-1):
        #lats.append(lat)
        lats[i] = polyhon.exterior.coords.xy[1][i]
        lons[i] = polyhon.exterior.coords.xy[0][i]
    #for lon in polyhon.exterior.coords.xy[0]:
    #    lons.append(lon)
    sql = 'select polyid from polygs order by polyid desc limit 1;'
    lastpolyid = lq.do_query(sql)
    try:
        polyid = int(lastpolyid[0][0])+1
    except:
        print('seems like first frame to ingest - ok')
        polyid = 1
    inserted = str(dt.datetime.now())
    name_old = 'frame_'+polyid_track[-1]+'_t'+str(int(polyid_track[0:3]))+'_1bidxxxxxx'
    sql = "INSERT INTO polygs VALUES ({0}, '{1}', '{2}', {3}, {4}, {5}, {6}, {7}, {8}, {9}, {10}, {11}, "\
    "{12}, {13}, {14}, {15}, {16}, {17}, {18}, {19}, {20}, {21}, {22}, {23}, {24}, {25}, {26}, {27}, "\
    "{28}, {29}, {30}, '{31}', {32}, '{33}');".format(\
                       polyid, polyid_name, polyid_track, polyid_colat10, len(iw1s), len(iw2s), len(iw3s),\
                       lats[0], lons[0], lats[1], lons[1], lats[2], lons[2], lats[3], lons[3],\
                       lats[4], lons[4], lats[5], lons[5], lats[6], lons[6], lats[7], lons[7],\
                       lats[8], lons[8], lats[9], lons[9], lats[10], lons[10], lats[11], lons[11],\
                       name_old, 0, inserted)
    #print(sql)
    #return 0
    if testonly:
        print('TEST ONLY')
        print('this command would be performed: ')
        print(sql)
    else:
        res = lq.do_query(sql, 1)
    bid_tanx = iw1s+iw2s+iw3s
    for bidtanx in bid_tanx:
        sql = 'select bid from bursts where bid_tanx="{}";'.format(bidtanx)
        res = lq.do_query(sql)
        #print(sql)
        bid = res[0][0]
        sql = 'INSERT INTO polygs2bursts VALUES ({0}, {1});'.format(polyid,bid)
        #print(sql)
        if testonly:
            print(sql)
        else:
            res = lq.do_query(sql, 1)
    if not testonly:
        print('including to polyg2gis table')
        gpan = frame2geopandas_brute(polyid_name)
        rc = store_frame_geometry(gpan)
        if rc != 1:
            print('ERROR STORING TO polyg2gis TABLE!!!')
        #else:
        #
        #actually the licsar csv should not contain this..
        #rc = export_frames_to_licsar_csv(gpan)
        print('generated new frame '+polyid_name)
        print('you may do following now: ')
        print('licsar_initiate_new_frame.sh '+polyid_name)
        if hicode:
            print('(but remember adding parameter -'+hicode+')')
        #delete_frame_commands(frame)
    return polyid_name


def generate_frame_from_bursts_kml(inputkml):
    """ Directly generates a frame definition from burst ids stored in a KML file
    """
    bursts = load_bursts_from_kml(inputkml)
    generate_new_frame(bursts, testonly=False)


def load_bursts_from_txt(intxt):
    f = open(intxt,'r')
    contents = f.readlines()
    bursts = []
    for burst in contents:
        bursts.append(burst.split('\n')[0])
    f.close()
    return bursts


def load_xy(intxt, onlyminmax = True):
    f = open(intxt,'r')
    contents = f.readlines()
    f.close()
    lon = []
    lat = []
    for line in contents:
        lon.append(float(line.split(' ')[0]))
        lat.append(float(line.split(' ')[1]))
    if onlyminmax:
        out = [min(lon), max(lon)], [min(lat), max(lat)]
    else:
        out = [lon, lat]
    return out


def load_bursts_from_kml(inputkml):
    #inputkml = '/gws/nopw/j04/nceo_geohazards_vol2/LiCS/temp/insar_temp/frames_redef/kmls/test_146a.kml'
    newbursts = gpd.read_file(inputkml, driver='KML')
    newbursts = newbursts[newbursts.columns[0]].tolist()
    return newbursts



def export_bidtanxs_to_kml(bidtanxs, outpath = '/gws/nopw/j04/nceo_geohazards_vol1/public/shared/test', projname = 'track', merge = False):
    """Exports list of burst IDs (bidtanxs) to an outpath/projname_TRACK.kml file. If merge=True, the bursts will be merged to one polygon"""
    #kmlout name will be auto_completed
    bidtanxs.sort()
    tracks = set()
    for bid in bidtanxs:
        tracks.add(bid.split('_')[0])
    #print(tracks)
    for track in tracks:
        track_bursts = []
        for bidtanx in bidtanxs:
            if bidtanx.split('_')[0] == track:
                track_bursts.append(bidtanx)
        #print(track_bursts)
        if len(tracks) > 1:
            kmlout = os.path.join(outpath,'{0}_{1}.kml'.format(projname, track))
        else:
            kmlout = os.path.join(outpath,'{0}.kml'.format(projname))
        #print(kmlout)
        if os.path.exists(kmlout): os.remove(kmlout)
        frame_gpd = bursts2geopandas(track_bursts, merge)
        print('exporting to '+kmlout)
        frame_gpd.to_file(kmlout, driver='KML')
    if merge == False:
        print('done. please edit the kmls - delete not wanted bursts, save and return')


def export_frame_to_kml(frame, outpath = '/gws/nopw/j04/nceo_geohazards_vol2/LiCS/temp/insar_temp/frames_redef/kmls', merge=False):
    """ Exports the frame polygon to kml. Currently only the uglier version (coarse burst polygons)
    """
    if not os.path.exists(outpath):
        os.mkdir(outpath)
    ai = lq.get_bursts_in_frame(frame)
    bidtanxs = lq.sqlout2list(ai)
    export_bidtanxs_to_kml(bidtanxs, outpath, projname = frame, merge=merge)


def export_all_frames_to_framecsv(outcsv = '/gws/nopw/j04/nceo_geohazards_vol1/public/shared/frames/frames.csv', store_zero = False):
    asc_gpd, desc_gpd = get_all_frames()
    rc = export_frames_to_licsar_csv(asc_gpd, outcsv, store_zero)
    rc = export_frames_to_licsar_csv(desc_gpd, outcsv, store_zero)
    return rc


def get_satids_of_burst(burstid, expected = ['S1A','S1B']):
    a = lq.get_filenames_from_burst(burstid)
    a = lq.sqlout2list(a)
    b = pd.DataFrame(expected)
    b['count'] = 0
    for x in a:
        satid=x[:3]
        if satid in expected:
            i=b[b[0] == satid]['count'].index[0]
            b.loc[i,'count'] =b.loc[i,'count']+1
    b = b.rename(columns={0: "sat_id"})
    return b


def get_frames_gpd(framelist):
    ''' framelist must be list of frame IDs'''
    fgpd = gpd.geodataframe.GeoDataFrame()
    for frame in framelist:
        a = frame2geopandas(frame)
        fgpd = fgpd.append(a)
    fgpd = fgpd.set_geometry('geometry')
    fgpd = fgpd.reset_index(drop=True)
    return fgpd


def get_all_frames(only_initialised = False, merge = False):
    """Will get geopandas for all LiCSAR frames

    Args:
        only_initialised (bool): will return only frames that are initialised
        merge (bool): if True, it will output in one table only, by default returns asc and desc frames separately
    """
    asc_gpd = gpd.geodataframe.GeoDataFrame()
    desc_gpd = gpd.geodataframe.GeoDataFrame()
    for i in range(1,175+1):
        print('preparing frames from track {}'.format(i))
        #descending:
        frames = lq.get_frames_in_orbit(i, 'D')
        frames = lq.sqlout2list(frames)
        for frame in frames:
            if only_initialised:
                if not os.path.exists(os.path.join(os.environ['LiCSAR_public'], str(int(frame[:3])), frame, 'metadata', 'metadata.txt')):
                    continue
            a = frame2geopandas(frame)
            if type(a) != type(None):
                desc_gpd = desc_gpd.append(a)
        #ascending
        frames = lq.get_frames_in_orbit(i, 'A')
        frames = lq.sqlout2list(frames)
        for frame in frames:
            if only_initialised:
                if not os.path.exists(os.path.join(os.environ['LiCSAR_public'], str(int(frame[:3])), frame, 'metadata', 'metadata.txt')):
                    continue
            a = frame2geopandas(frame)
            if type(a) != type(None):
                asc_gpd = asc_gpd.append(a)
    asc_gpd = asc_gpd.set_geometry('geometry')
    desc_gpd = desc_gpd.set_geometry('geometry')
    if merge:
        framesgpd = asc_gpd.append(desc_gpd)
        framesgpd = framesgpd.reset_index(drop=True)
        return framesgpd
    else:
        return asc_gpd, desc_gpd


def manual_check_master_files(frame, master):
    if type(master) == type('str'):
        masterdate=dt.datetime.strptime(master,'%Y%m%d')
    else:
        masterdate=master
    filelist = lq.get_frame_files_date(frame,masterdate)
    print(len(filelist))
    for filee in filelist:
        fid=filee[1]
        brsts = lq.get_bursts_in_file(fid)
        brsts = lq.sqlout2list(brsts)
        b=bursts2geopandas(brsts)
        print(filee[2])
        b.plot()
        plt.show()
    print('to fix the bad ones:')
    print('fullpath = ....')
    print('lq.delete_file_from_db(fullpath)')
    print("os.system('arch2DB.py -f {} >/dev/null 2>/dev/null'.format(fullpath))")


def export_all_frames_to_kmls(kmldirpath = '/gws/nopw/j04/nceo_geohazards_vol1/public/shared/test/bursts'): #'/gws/nopw/j04/nceo_geohazards_vol1/public/shared/frames/'):
    asc_gpd, desc_gpd = get_all_frames()
    if os.path.exists(os.path.join(kmldirpath,'ascending.kml')):
        os.remove(os.path.join(kmldirpath,'ascending.kml'))
    if os.path.exists(os.path.join(kmldirpath,'descending.kml')):
        os.remove(os.path.join(kmldirpath,'descending.kml'))
    
    export_geopandas_to_kml(asc_gpd, os.path.join(kmldirpath,'ascending.kml'))
    export_geopandas_to_kml(desc_gpd, os.path.join(kmldirpath,'descending.kml'))


def delete_bursts(bidtanxs, test = True):
     if test:
         print('WARNING, this will delete all bursts in the list FOREVER')
         print('if any frame still uses the burst ids, it will cancel their deletion')
         return
     else:
         for bidtanx in bidtanxs:
             print('deleting burst '+bidtanx)
             try:
                 rc = lq.delete_burst_from_db(bidtanx)
             except:
                 print('some error occurred - cancelling')
                 return


def epoch_has_all_frame_bursts(epoch, frame):
    """ Checks if epoch contains all necessary bursts in frame definition.
    Needs to have the epoch already ingested in LiCSInfo database.
    
    Args:
        epoch (dt.datetime.date, dt.datetime or str): epoch date (if str, should be as 20191120)
        frame (str): frame ID
    Returns:
        boolean: True means Yes, it has all bursts. False means it has missing bursts"
    """
    if type(epoch) == type('str'):
        epoch = dt.datetime.strptime(epoch, '%Y%m%d')
    if type(epoch) == type(dt.datetime.now()):
        epoch = epoch.date()
    burstlist = lq.get_bursts_in_frame(frame)
    from mk_imag_lib import check_master_bursts
    out = check_master_bursts( frame, burstlist, epoch, None, lq, midnighterror = True)
    if out == 0:
        return True
    else:
        return False


def subset_get_coords_from_sourcecmd(clipcmd):
    ''' Returns coordinates and resol from clip (subset) sourcecmd.txt file

    :param clipcmd: path to the sourcecmd.txt file
    :return: minlon, maxlon, minlat, maxlat, resol_deg
    '''
    clipstr = grep1line('clip_slc.sh', clipcmd)
    clipstr = clipstr.split(' ')
    return float(clipstr[2]), float(clipstr[3]), float(clipstr[4]), float(clipstr[5]), float(clipstr[7])

"""
def post_init_frame(frame, volc_full_overlap=True):
    '''additional operations after the frame gets initialised:
    - find volclips and init them
    - ...
    '''
    print('checking volcanoes in given frame')
    init_volcs_in_frame(frame, full_overlap=volc_full_overlap)
"""

def delete_frame(frame):
    ''' This will delete given frame from LiCSAR system:
    - physically all data in LiCSAR_procdir and public
    - including from frames.csv files
    - from the LiCSInfo database
    - from the related subsets (it will check for other possible frames, so better to first generate substitute frame, and then to delete this one)
    '''
    #print('cannot use this anymore, in CentOS7 - please contact admin to delete frame '+frame)
    #return False
    polyid = lq.get_frame_polyid(frame)[0][0]
    if not polyid:
        print('error - is it correct frame??')
        return
    #cmd_mysql='mysql -h ..... licsar_batch ' # see lics_mysql.sh
    os.system('setFrameInactive.py {0}'.format(frame))
    track=str(int(frame[0:3]))
    procdir = os.path.join(os.environ['LiCSAR_procdir'], track, frame)
    clipdir = os.path.join(procdir, 'subsets')
    if os.path.exists(clipdir):
        for clip in os.listdir(clipdir): # TOCHECK
            try:
                clipath = os.readlink(os.path.join(clipdir, clip))
            except:
                continue
            try:
                ## get polygon for the given subset folder
                clipcmd = os.path.join(clipath, 'sourcecmd.txt')
                if os.path.exists(clipcmd):
                    # get the coords
                    lon1, lon2, lat1, lat2, resol_deg = subset_get_coords_from_sourcecmd(clipcmd)
                    # get it as polygon
                    lon1, lon2 = sorted([lon1, lon2])
                    lat1, lat2 = sorted([lat1, lat2])
                    lonlats = [(lon1, lat1), (lon1, lat2), (lon2, lat2), (lon2, lat1), (lon1, lat1)]
                    polygon = Polygon(lonlats)
                    resol_m = int(round(resol_deg * 111111))
                    is_volc = False
                    if clipath.split('/')[-3] == 'volc':
                        is_volc = True
                    frames = lq.get_frames_in_polygon(lon1, lon2, lat1, lat2)
                    frames = lq.sqlout2list(frames)
                    framesok = []
                    for fr in frames:
                        frdir = os.path.join(os.environ['LiCSAR_procdir'], str(int(fr[:3])), fr)
                        if (int(fr[:3]) in [int(track)-1, int(track), int(track)+1]) and (fr[3] == frame[3]):
                            if os.path.exists(frdir):
                                framesok.append(fr)
                    framesok2 = []
                    for fr in framesok:
                        framepoly = lq.get_polygon_from_frame(fr)
                        if framepoly.contains(polygon):
                            framesok2.append(fr)
                    if len(framesok2) == 0:   # this means, no full overlap found, using only partial overlap
                        framesok2 = framesok
                    if len(framesok2)>1:
                        # choose the newer one
                        framesok2_crdate = []
                        for fr in framesok2:
                            frdir = os.path.join(os.environ['LiCSAR_procdir'], str(int(fr[:3])), fr)
                            try:
                                mtime = os.path.getmtime(os.path.join(frdir, 'geo', 'EQA.dem'))
                            except:
                                mtime = 0
                            framesok2_crdate.append(mtime)
                        i = np.array(framesok2_crdate).argmax()
                        finfr = framesok2[i]
                        framesok2 = [finfr]
                    # delete the subset clip
                    print('deleting subset from '+clipath)
                    os.system('rm -rf '+clipath)
                    if os.path.exists(clipath): # can happen due to permissions
                        os.system('mv '+clipath+' '+clipath+'.backup')
                    if len(framesok2) == 1:
                        # found frame to clip!
                        fr = framesok2[0]
                        print('initialising subset with the (new) frame '+fr)
                        subset_initialise_corners(fr, lon1, lon2, lat1, lat2, sid=str(clip), is_volc=is_volc,
                                                     resol_m=resol_m)
                    else:
                        print('no substitute frame found for the subset')
                # now delete the clipath data
            except:
                print('error rearranging subset '+clip)
            if os.path.exists(clipath):
                print('deleting subset from ' + clipath)
                os.system('rm -rf ' + clipath)
                if os.path.exists(clipath):  # can happen due to permissions
                    os.system('mv ' + clipath + ' ' + clipath + '.backup')
    else:
        print('no subsets for this frame')
    if os.path.exists(procdir):
        os.system('rm -rf $LiCSAR_procdir/{0}/{1} $LiCSAR_public/{0}/{1} $BATCH_CACHE_DIR/{1}'.format(track,frame))
        os.system('echo {0} >> /gws/nopw/j04/nceo_geohazards_vol1/projects/LiCS/volc-portal/processing_scripts/excluded_frames/excluded_frames_extras'.format(frame))
        os.system('mv $LiCSAR_procdir/{0}/{1} $LiCSAR_procdir/{0}/todel.{1} 2>/dev/null'.format(track, frame))
        os.system('mv $LiCSAR_public/{0}/{1} $LiCSAR_public/{0}/todel.{1} 2>/dev/null'.format(track, frame))
        os.system("sed -i '/{}/d' /gws/nopw/j04/nceo_geohazards_vol1/public/shared/frames/frames.csv".format(frame))
        os.system("sed -i '/{}/d' /gws/nopw/j04/nceo_geohazards_vol1/public/LiCSAR_products/EQ/eqframes.csv".format(frame))
    else:
        print('this frame was probably not initialised. Deleting only from database')
    #polyid = lq.get_frame_polyid(frame)[0][0]
    sql = "delete from licsar_batch.polygs2master where polyid={};".format(polyid)
    rc = lq.do_query(sql, 1)
    #os.system(cmd_mysql+' -e "{}"'.format(sql))
    sql = "delete from polygs2bursts where polyid={};".format(polyid)
    rc = lq.do_query(sql, 1)
    try:
        sql = "delete from esd where polyid={};".format(polyid)
        rc = lq.do_query(sql, 1)
    except:
        print('error in deleting from esd table')
    #os.system(cmd_mysql+' -e "{}"'.format(sql))
    frame_workaround = frame.replace('A','Y')
    frame_workaround = frame_workaround.replace('D','Y')
    sql = "update polygs set polyid_name='{0}' where polyid_name='{1}';".format(frame_workaround, frame)
    rc = lq.do_query(sql, 1)
    #os.system(cmd_mysql+' -e "{}"'.format(sql))
    sql = "delete from polygs where polygs.polyid_name='{}';".format(frame_workaround)
    rc = lq.do_query(sql, 1)
    #rc = os.system(cmd_mysql+' -e "{}" 2>/dev/null'.format(sql))
    #if rc != 0:
    #    print('WARNING: the frame was only partially removed. But it should not appear in processing')
    print('the frame {} has been removed, associated files purged'.format(frame))


def delete_frame_commands(frame):
    print('setFrameInactive.py {0}'.format(frame))
    track=str(int(frame[0:3]))
    print('rm -rf $LiCSAR_procdir/{0}/{1} $LiCSAR_public/{0}/{1}'.format(track,frame))
    print("sed -i '/{}/d' /gws/nopw/j04/nceo_geohazards_vol1/public/shared/frames/frames.csv".format(frame))
    print('lics_mysql.sh')
    sql = "select polyid from polygs where polyid_name = '{0}';".format(frame)
    polyid = lq.do_query(sql)[0][0]
    sql = "delete from polygs2master where polyid={};".format(polyid)
    print(sql)
    sql = "delete from polygs2bursts where polyid={};".format(polyid)
    print(sql)
    frame_workaround = frame.replace('A','X')
    frame_workaround = frame_workaround.replace('D','X')
    sql = "update polygs set polyid_name='{0}' where polyid_name='{1}';".format(frame_workaround, frame)
    print(sql)
    sql = "delete from polygs where polygs.polyid_name='{}';".format(frame_workaround)
    print(sql)
    print('')

def remove_bad_bursts(frame, badbursts, testonly = True):
    #badbursts should be a list of bursts existing in the frame that should be removed
    #e.g. the list of missing bursts during the licsar_init_frame.sh script..
    #in testonly - it will only give text output, rather than really do something..
    bursts = lq.get_bidtanxs_in_frame(frame)
    bursts = lq.sqlout2list(bursts)
    for b in badbursts:
        bursts.remove(b)
    generate_new_frame(bursts, testonly)
    print('to remove the old frame, you should do:')
    print("fc.delete_frame('{}')".format(frame))
    #delete_frame_commands(frame)


def add_more_bursts(frame, extrabursts, testonly = True):
    """Adds some more bursts to the frame definition. Please follow the printed comments to delete the old frame definition, as this operation will basically create new frame definition."""
    #extrabursts should be a list of bursts not existing in the frame, to be added there
    #in testonly - it will only give text output, rather than really do something..
    bursts = lq.get_bidtanxs_in_frame(frame)
    bursts = lq.sqlout2list(bursts)
    newbursts = bursts+extrabursts
    #remove duplicities
    newbursts = list(set(newbursts))
    newbursts.sort()
    generate_new_frame(newbursts, testonly)
    print('to remove the old frame, you should do:')
    print("fc.delete_frame('{}')".format(frame))


