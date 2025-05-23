#!/usr/bin/env python

################################################################################
#import
################################################################################
import batchDBLib as lq
from configLib import config
from batchEnvLib import LicsEnv
import os
import shutil
import sys
import global_config as gc
import re
from LiCSAR_lib.mk_imag_lib import *
from LiCSAR_lib.LiCSAR_misc import *
from batchLSFLib import set_lotus_job_status

#to ensure GAMMA will have proper value for CPU count
#however i had to force processing on 1 core only, so hardcoding here
#from multiprocessing import cpu_count
#os.environ['OMP_NUM_THREADS'] = str(cpu_count())
os.environ['OMP_NUM_THREADS'] = str(1)

#to override missingBursts checks:
check_missing_bursts_bool = False

################################################################################
#Statuses
################################################################################
BUILDING = -5
FILES_MISSING = -4
UNKOWN_ERROR = -3
MISSING_BURSTS = -2
UNBUILT = -1
BUILT = 0

################################################################################
#SLC env class
################################################################################
class SlcEnv(LicsEnv):
    def __init__(self,jobID,frame,date,cacheDir,tempDir):
        LicsEnv.__init__(self,jobID,frame,cacheDir,tempDir)
        self.srcPats = ['local_config.py']
        self.outPats = ['SLC/{0:%Y%m%d}/{0:%Y%m%d}\.IW[1-3]\.slc.*'.format(date),
                        'SLC/{0:%Y%m%d}/{0:%Y%m%d}\..*mli.*'.format(date),
                        'SLC/{0:%Y%m%d}/{0:%Y%m%d}\.slc\.par'.format(date),
                        'SLC/{0:%Y%m%d}/{0:%Y%m%d}\.slc'.format(date),
                        'log.*']
                        #'tab.*']
        self.cleanDirs = ['./SLC','./tab']
################################################################################
#Check files
################################################################################
def check_all_files_on_disk(files):
    missing = False
    missingFiles = []
    while files:
        f = files.pop()
        f = re.sub('\.metadata_only','',f)
        if not os.path.exists(f):
            missingFiles.append(f)
            missing = True
    return missing,set(missingFiles)

################################################################################
#Main
################################################################################
def main(argv):
    #Paramters
    jobID = int(argv[1])
    slcs = lq.get_unbuilt_slcs(jobID)
    if slcs.empty:
        print('no unbuilt slcs were found. exiting')
        exit()
    frameName = lq.get_frame_from_job(jobID)
    #get acquisition mode - default is 'iw'
    acqMode = 'iw'
    if frameName.split('_')[1] == 'SM':
        acqMode = 'sm'
        print('processing stripmap frame - EXPERIMENTAL')
    try:
        cacheDir = os.environ['BATCH_CACHE_DIR']
    except KeyError as error:
        print('I required you to set your cache directory using the'\
                'enviroment variable BATCH_CACHE_DIR')
        raise error
    #tempDir = config.get('Env','TempDir')
    #user = os.environ['USER']
    #tempDir = os.path.join(tempDir,user)
    tempDir = os.environ['LiCSAR_temp']
    burstlist = lq.get_bursts_in_frame(frameName)

#-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
    print("Processing job {0} in frame {1}".format(
            jobID,frameName))
    lq.set_job_started(jobID)

#-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
    if os.path.exists('missingFiles'):
        os.remove('missingFiles')
    
    for ind,row in slcs.iterrows():
        date = row['acq_date']
        filesTable = lq.get_frame_files_date(frameName,date)
        files = [f[2] for f in filesTable]
        missing,missingFiles = check_all_files_on_disk(files)
#-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
        if missing:
            print("Missing files for date {:%Y%m%d}".format(date))
            lq.set_slc_status(row['slc_id'],FILES_MISSING)
            with open('missingFiles','a') as f:
                for missFile in missingFiles:
                    f.write(missFile+'\n')
#-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
        else:
            set_lotus_job_status('Setting up {:%y-%m-%d}'.format(date))
            with SlcEnv(jobID,frameName,date,cacheDir,tempDir) as env:
                print("created new processing environment {}".format(env.actEnv))
                print("processing slc {0} on acquisition date {1:%Y%m%d}".format(
                        row['slc_id'],row['acq_date']))

                set_lotus_job_status('Processing {:%y-%m-%d}'.format(date))
                env.cleanHook = lambda : lq.set_slc_status(row['slc_id'],UNKOWN_ERROR)

                #Check that we have no missing bursts
                imburstlist = lq.get_frame_bursts_on_date(frameName,date)
                missingbursts = [b for b in burstlist if not b in imburstlist]
                if not missingbursts or not check_missing_bursts(burstlist,missingbursts) or not check_missing_bursts_bool:
                    print('List of missing bursts:')
                    print(missingbursts)
                    #we will relax the condition here and checking for only critical missing bursts
                    #if not check_missing_bursts(burstlist,missingbursts):
                    print("All necessary bursts for frame {0} seem to be have been acquired "\
                            "on {1}...".format(frameName,date))
                    lq.set_slc_status(row['slc_id'],BUILDING) #building....
                    rc = make_frame_image(date,frameName,imburstlist,env.actEnv, lq, -1, acqMode)
                    lq.set_slc_status(row['slc_id'],rc)
                    if rc!=0:
                        shutil.rmtree('./SLC')
                else:
                    print("Missing bursts for date {:%Y%m%d}".format(date))
                    lq.set_slc_status(row['slc_id'],MISSING_BURSTS)
                set_lotus_job_status('Cleaning {:%y-%m-%d}'.format(date))

#-- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- -- 
    lq.set_job_finished(jobID,3)

if __name__ == "__main__":
    sys.exit(main(sys.argv))
