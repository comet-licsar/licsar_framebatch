#!/usr/bin/env python

################################################################################
#imports
################################################################################
import os
import time
import fnmatch
import re
import shutil
import glob
import datetime as dt
from dirsync import sync
from configLib import config
from framecare import get_master
from gamma_functions import SLC_mosaic_S1_TOPS, make_SLC_tab
import glob
import global_config as gc

pubdir = os.environ['LiCSAR_public']

################################################################################
#Cache Exception
################################################################################
class InvalidFrameError(Exception):
    def __init__(self,frame):
        self.frame = frame
    def __str__(self):
        return 'Frames should begin with the track number, i.e. TTT[AD]_*,'\
                'instead got {}'.format(self.frame)

################################################################################
#Create Cache Dir
################################################################################
def create_lics_cache_dir(frame,srcDir,cacheDir,masterDate=None):
    trackPat = '^(?P<trk>\d+)[AD].*'
    mstrDatePat = '(?P<dt>\d+)\.\w+$'
    mtch = re.search(trackPat,frame)
    # If Frame name right format
    if mtch:
        track = mtch.group('trk')
        track = str(int(track)) # remove begining 0's
        frameDir = os.path.join(srcDir,track,frame)
        frameCacheDir = os.path.join(cacheDir,frame)
#-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
        if not masterDate:
            #use new version
            dateStr = get_master(frame)
            if dateStr:
                masterDate = dt.datetime.strptime(dateStr,'%Y%m%d')
            if not masterDate:
                print('error getting masterdate from LiCSAR_public metadata file')
                print('trying from the directory structure')
                 #Find master date from geo dir
                geoDir = os.path.join(frameDir,'geo')
                geoFls = os.listdir(geoDir)
                while not masterDate: # Randomly search geo files for date
                    mtch = re.search(mstrDatePat,geoFls.pop())
                    if mtch:
                        dateStr = mtch.group('dt')
                        masterDate = dt.datetime.strptime(dateStr,'%Y%m%d')
#-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
        subPats = [    #'DEM.*',
                'geo.*',
                'SLC/{:%Y%m%d}'.format(masterDate)]
        # Sync src geo,dem and master rslc
        sync(frameDir,frameCacheDir,'sync',create=True,only=subPats)
        if not os.path.exists(os.path.join(frameCacheDir, 'DEM')):
            try:
                os.symlink(os.path.join(frameDir, 'DEM'), os.path.join(frameCacheDir, 'DEM'))
            except:
                print('no DEM folder in LiCSAR sys for this frame. Continuing anyway')
#-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
        # regenerate SLC mosaic for the master (needed later, for ifgs.
        # coregistration would work without it)
        dateStr = masterDate.strftime('%Y%m%d')
        slcDir = os.path.join(frameCacheDir,'SLC',dateStr)
        mastermosaic = os.path.join(slcDir,dateStr+'.slc')
        if not os.path.exists(mastermosaic):
            print('regenerating master mosaic (some 2 minutes)')
            slctab = os.path.join(slcDir,dateStr+'.mosaic.tab')
            #mastertab = os.path.join(slcDir,dateStr+'.master.tab')
            logmosaic = os.path.join(slcDir,dateStr+'.mosaic.log')
            #import glob
            iwfiles = glob.glob(os.path.join(slcDir,dateStr+'.IW*.slc'))
            swathlist = []
            for iwfile in iwfiles:
                swathlist.append(iwfile.split('/')[-1].split('.')[1])
            swathlist.sort()
            rc, msg = make_SLC_tab(slctab,mastermosaic,swathlist)
            #rc, msg = make_SLC_tab(mastertab,mastermosaic,swathlist)
            if rc > 0:
                print('Something went wrong creating the tab file for mosaic...')
                return 1
            rc = SLC_mosaic_S1_TOPS(slctab,mastermosaic,gc.rglks,gc.azlks,logmosaic)
            if not rc:
                print('something got wrong generating master mosaic. but going on..')
            os.remove(slctab)
        
        #Link master rslc to master slc
        rslcDir = os.path.join(frameCacheDir,'RSLC',dateStr)
        if os.path.exists(rslcDir):
            print('The project exists..will remove master rslcs and recreate (links)')
            shutil.rmtree(rslcDir)
        os.makedirs(rslcDir)
        #slcDir = os.path.join(frameCacheDir,'SLC',dateStr)
        slcFiles = os.listdir(slcDir)
        #print('debug')
        #print(slcFiles)
        while slcFiles: #Link all "slc" type files -- for master
            oldFile = slcFiles.pop()
            #mtch = re.search('*.slc.*',oldFile)
            if '.slc' in oldFile:
                newFile = re.sub('slc','rslc',oldFile)
                oldFileFull = os.path.join(slcDir,oldFile)
                newFileFull = os.path.join(rslcDir,newFile)
                #this way we will copy the par files to temp
                if 'par' in oldFile:
                    if not os.path.exists(newFileFull):
                        try:
                            rc = shutil.copy(oldFileFull,newFileFull)
                        except:
                            print('warning, file {} was not found'.format(oldFileFull))
                else:
                    if not os.path.exists(newFileFull):
                        try:
                            os.symlink(oldFileFull,newFileFull)
                        except:
                            print('warning, file {} was not found'.format(oldFileFull))
        #now, local config python parameters:
        lcfile = os.path.join(frameDir,'local_config.py')
        if os.path.exists(lcfile):
            rc = shutil.copyfile(lcfile,os.path.join(frameCacheDir,'local_config.py'))
    else:
        raise InvalidFrameError

def get_rslc_list(frame, lutBool = False):
    procdir = config.get('Env','SourceDir')
    track = str(int(frame[0:3]))
    frameDir = os.path.join(procdir,track,frame)
    rslclist = []
    if os.path.isdir(frameDir):
        m = fnmatch.filter(os.listdir(frameDir+'/SLC'), '20??????')[0] # should be only one there..
        rslcs = fnmatch.filter(os.listdir(frameDir+'/RSLC'), '20??????')
        rslcs7z = fnmatch.filter(os.listdir(frameDir+'/RSLC'), '20??????.7z')
        #add lut table here?
        if lutBool:
            luts7z = fnmatch.filter(os.listdir(frameDir+'/LUT'), '20??????.7z')
            for lut7z in luts7z:
                lut = lut7z.split('.')[0]
                rslclist.append(lut)
        for rslc7z in rslcs7z:
            rslc = rslc7z.split('.')[0]
            rslclist.append(rslc)
        for rslc in rslcs:
            if rslc not in rslclist:
                rslclist.append(rslc)
        rslclist.append(m)
        rslclist.sort()
    return rslclist

def get_rslcs_from_lics(frame,srcDir,cacheDir,date_strings):
    frameDir = srcDir + '/' + frame.split('_')[0].lstrip("0")[:-1] + '/' + frame
    outrslcs=[]
    if not os.path.isdir(os.path.join(cacheDir,frame,'RSLC')): os.mkdir(os.path.join(cacheDir,frame,'RSLC'))
    if os.path.isdir(frameDir):
        #getting RSLCs
        rslcs = fnmatch.filter(os.listdir(frameDir+'/RSLC'), '20??????')
        #for r in rslcs:
        #    if r not in date_strings: rslcs.remove(r)
        rslcs_ok = []
        for r in rslcs:
            if os.path.splitext(r)[0] in date_strings: rslcs_ok.append(r)
        for r in rslcs_ok:
            if fnmatch.filter(os.listdir(frameDir+'/RSLC/'+r), '20??????.IW?.rslc'):
                if not os.path.exists(os.path.join(cacheDir,frame,'RSLC',r)):
                    os.symlink(os.path.join(frameDir,'RSLC',r),os.path.join(cacheDir,frame,'RSLC',r))
                outrslcs.append(r)
        #also un7zip existing RSLCs
        rslcs7z = fnmatch.filter(os.listdir(frameDir+'/RSLC'), '20??????.7z')
        #remove files that are not specified to work on (start/end date)
        rslcs7z_ok = []
        for r in rslcs7z:
            if os.path.splitext(r)[0] in date_strings: rslcs7z_ok.append(r)
        #for r in rslcs7z:
        #    if os.path.splitext(r)[0] not in date_strings: rslcs7z.remove(r)
        for r in rslcs7z_ok:
            if not os.path.exists(os.path.join(cacheDir,frame,'RSLC',r.split('.')[0])):
                print('Extracting '+r)
                cmd="7za -mmt=1 x -o"+os.path.join(cacheDir,frame,'RSLC')+" "+os.path.join(frameDir,'RSLC',r)+" >/dev/null"
                b=os.system(cmd)
            if os.path.exists(os.path.join(cacheDir,frame,'RSLC',r.split('.')[0])): outrslcs.append(r.split('.')[0])

        #finally check for LUTs
        if os.path.exists(frameDir+'/LUT'):
            luts7z = fnmatch.filter(os.listdir(frameDir+'/LUT'), '20??????.7z')
            luts7z_ok = []
            for l in luts7z:
                if (os.path.splitext(l)[0] in date_strings) and (os.path.splitext(l)[0] not in outrslcs): luts7z_ok.append(l)
            for l in luts7z_ok:
                if not os.path.exists(os.path.join(cacheDir,frame,'RSLC',l.split('.')[0])):
                    if not os.path.exists(os.path.join(cacheDir,frame,'LUT')):
                        os.mkdir(os.path.join(cacheDir,frame,'LUT'))
                    if not os.path.exists(os.path.join(cacheDir,frame,'LUT',l.split('.')[0])):
                        print('Extracting LUT of '+l)
                        cmd="7za -mmt=1 x -o"+os.path.join(cacheDir,frame,'LUT')+" "+os.path.join(frameDir,'LUT',l)+" >/dev/null"
                        b=os.system(cmd)
            #this line is not used - the LUTs will just physically exist in RSLC folders and therefore used for recoreg
            #if os.path.exists(os.path.join(cacheDir,frame,'RSLC',l.split('.')[0])): outrslcs.append(l.split('.')[0])
        #update_existing_rslcs(frame,rslcs)
    return outrslcs

def get_ifgs_from_lics(frame,srcDir,cacheDir,startDate = False,endDate = False):
    frameDir = srcDir + '/' + frame.split('_')[0].lstrip("0")[:-1] + '/' + frame
    track = frame.split('_')[0].lstrip("0")[:-1]
    outifgs=[]
    if not os.path.isdir(os.path.join(cacheDir,frame,'IFG')): os.mkdir(os.path.join(cacheDir,frame,'IFG'))
    pubframeDir = os.path.join(pubdir,track,frame)
    pubframeDir_ifgs = os.path.join(pubframeDir, 'interferograms')
    if os.path.isdir(pubframeDir_ifgs):
        ifgs = fnmatch.filter(os.listdir(pubframeDir_ifgs), '20??????_20??????')
        #if os.path.isdir(frameDir+'/IFG'):
        #    ifgs = fnmatch.filter(os.listdir(frameDir+'/IFG'), '20??????_20??????')
        if startDate and ifgs:
            ifgs_ok = []
            for ifg in ifgs:
                #print('debug..'+str(ifg))
                #print(dt.datetime.strptime(ifg.split('_')[0],'%Y%m%d'))
                #print(startDate)
                #print(endDate)
                first_date = dt.datetime.strptime(ifg.split('_')[0],'%Y%m%d')
                second_date = dt.datetime.strptime(ifg.split('_')[1],'%Y%m%d')
                if first_date >= startDate and second_date <= endDate:
                    ifgs_ok.append(ifg)
            ifgs = ifgs_ok
        #sometimes the saved ifgs are not unwrapped!
        #hmm.. but perhaps it would be only good if to keep it...
        #ifgs = [ifg for ifg in ifgs if os.path.exists(os.path.join(frameDir,'IFG',ifg,ifg+'.unw')]
        
        for ifg in ifgs:
            if not os.path.exists(os.path.join(cacheDir,frame,'IFG',ifg)):
                os.mkdir(os.path.join(cacheDir,frame,'IFG',ifg))
                #ok, now.. if there are some files in LiCSAR_procdir, link them here:
                if os.path.isdir(frameDir+'/IFG'):
                    if os.path.isdir(os.path.join(frameDir,'IFG',ifg)):
                        for ifgfile in os.listdir(os.path.join(frameDir,'IFG',ifg)):
                            os.symlink(os.path.join(frameDir,'IFG',ifg,ifgfile),os.path.join(cacheDir,frame,'IFG',ifg,ifgfile))
            outifgs.append(ifg)
    return outifgs
################################################################################
# LiCS env
################################################################################
class LicsEnv():
    def __init__(self,jobID,frame,cacheDir,tempDir):
        self.frameTmp = os.path.join(tempDir,frame+'_envs')
        self.frameCache = os.path.join(cacheDir,frame)
        self.srcPats = []
        self.outPats = []
        self.prevDir = []
        self.newDirs = []
        self.frame = frame
        self.cleanDirs = []
        self.cleanHook = None
        try:
            try:
                JOBID = os.environ['SLURM_JOBID']
            except:
                JOBID = os.environ['LSB_JOBID']
            self.envID = '{}_{}'.format(jobID,JOBID)
        except:
            self.envID = str(jobID)
    def __enter__(self):
        #Create temporary dir if not present
        if not os.path.exists(self.frameTmp):
            # os.system('mkdir -p '+self.frameTmp)  # os.mkdir often fails due to paralellism..
            # time.sleep(1)  # for sync
            try:
                os.mkdir(self.frameTmp)
            except:
                time.sleep(1)  # for sync
        #Find prexisting 
        crtEnvs = glob.glob('{}/[0-9]*'.format(self.frameTmp))
        self.actEnv = os.path.join(self.frameTmp,self.envID)
        if self.srcPats:
            sync(self.frameCache,self.actEnv,'sync',create=True,only=self.srcPats)
        else:
            os.mkdir(self.actEnv)
        for newDir in self.newDirs:
            os.mkdir(os.path.join(self.actEnv,newDir))
        self.prevDir = os.getcwd()
        os.chdir(self.actEnv)
        return self
    def __exit__(self, *args):
        if args[0]:
            print("Received exception {}".format(args[1]))
            if self.cleanHook:
                self.cleanHook()
            for cleanDir in self.cleanDirs:
                if os.path.exists(cleanDir):
                    shutil.rmtree(cleanDir)                        
        if self.outPats:
            sync(self.actEnv,self.frameCache,'sync',create=True,only=self.outPats)
        else:
            sync(self.actEnv,self.frameCache,'sync',create=True)
        os.chdir(self.prevDir)
        import time
        time.sleep(1) # for sync
        try:
            shutil.rmtree(self.actEnv)
        except:
            print('WARNING, some residual files could not be deleted from ')
            print(self.actEnv)
        # 07/2021 - just to fix issue of not deleting SLC files after correctly generated RSLC files
        master = get_master(self.frame)
        slcdir = os.path.join(self.frameCache,'SLC')
        rslcdir = os.path.join(self.frameCache,'RSLC')
        rslcs = os.listdir(rslcdir)
        slcs = os.listdir(slcdir)
        slcs.remove(master)
        for slc in slcs:
            if slc in rslcs:
                print(slc+' was already coregistered, removing')
                try:
                    shutil.rmtree(os.path.join(slcdir, slc))
                except:
                    print('error deleting slc '+str(slc))
        return True
