#!/usr/bin/env python

################################################################################
#imports
################################################################################
import os
import fnmatch
import re
import shutil
import glob
import datetime as dt
from dirsync import sync

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
        if not masterDate: #Find master date from geo dir
            geoDir = os.path.join(frameDir,'geo')
            geoFls = os.listdir(geoDir)
            while not masterDate: # Randomly search geo files for date
                mtch = re.search(mstrDatePat,geoFls.pop())
                if mtch:
                    dateStr = mtch.group('dt')
                    masterDate = dt.datetime.strptime(dateStr,'%Y%m%d')
#-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
        subPats = ['DEM.*',
                'geo.*',
                'SLC/{:%Y%m%d}'.format(masterDate)]
        # Sync src geo,dem and master rslc
        sync(frameDir,frameCacheDir,'sync',create=True,only=subPats)
#-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
        #Link master rslc to master slc
        dateStr = masterDate.strftime('%Y%m%d')
        rslcDir = os.path.join(frameCacheDir,'RSLC',dateStr)
        if os.path.exists(rslcDir):
            print('The project exists..will try to use existing RSLCs')
            #    shutil.rmtree(rslcDir)
        else:
            os.makedirs(rslcDir)
        slcDir = os.path.join(frameCacheDir,'SLC',dateStr)
        slcFiles = os.listdir(slcDir)
        #print('debug')
        #print(slcFiles)
        while slcFiles: #Link all "slc" type files
            oldFile = slcFiles.pop()
            mtch = re.search('.*slc.*',oldFile)
            if mtch:
                newFile = re.sub('slc','rslc',oldFile)
                oldFile = os.path.join(slcDir,oldFile)
                newFile = os.path.join(rslcDir,newFile)
                if not os.path.exists(newFile): os.symlink(oldFile,newFile)
    else:
        raise InvalidFrameError

def get_rslcs_from_lics(frame,srcDir,cacheDir,masterstr):
    frameDir = srcDir + '/' + frame.split('_')[0].lstrip("0")[:-1] + '/' + frame
    rslcs=''
    if os.path.isdir(frameDir):
        rslcs = fnmatch.filter(os.listdir(frameDir+'/RSLC'), '20??????')
        if masterstr in rslcs: rslcs.remove(masterstr)
        for r in rslcs:
            if not os.path.exists(os.path.join(cacheDir,frame,'RSLC',r)):
                os.symlink(os.path.join(frameDir,'RSLC',r),os.path.join(cacheDir,frame,'RSLC',r))
        #update_existing_rslcs(frame,rslcs)
    return rslcs
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
        self.cleanDirs = []
        self.cleanHook = None
        try:
            lotusJobID = os.environ['LSB_JOBID']
            self.envID = '{}_{}'.format(jobID,lotusJobID)
        except:
            self.envID = str(jobID)
    def __enter__(self):
        #Create temporary dir if not present
        if not os.path.exists(self.frameTmp):
            os.mkdir(self.frameTmp)
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
            print("Recieved exception {}".format(args[1]))
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
        shutil.rmtree(self.actEnv)
        return True
