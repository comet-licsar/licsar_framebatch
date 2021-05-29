#!/usr/bin/env python

from quality_check import *
from getopt import getopt
import glob
import shutil, os
import warnings
warnings.filterwarnings('ignore')

"""
This is a tool to check quality of interferograms. it will 

Usage:

    frame_ifg_quality_check.py [-d] <frame>

    -d : also removes the identified bad files
    -n : does not keep coherence_stats.txt in the frame 
    -l : use local folder (e.g. cd $BATCH_CACHE_DIR; frame_ifg_quality_check.py -l 144D_00.....)
       : in this case, only lines detection and basic check is used..

"""
def main(argv=None):
    
    delete_ifgs = False
    keep_stats = True
    coh_threshold = 0.01
    do_local = False
    
    opts,args = getopt(argv[1:],'dnl')
    
    frame = args[0]
    if not frame:
        print('usage: frame_ifg_quality_check.py [-d] <frame>')
        print('parameter -d would also delete detected bad ifgs')
        return 0
    for o,a in opts:
        if o == '-d':
            delete_ifgs = True
        elif o == '-n':
            keep_stats = False
        elif o == '-l':
            do_local = True
        else:
            print("unexpected argument")
            return 1
    pubdir = os.environ['LiCSAR_public']
    track = str(int(frame[0:3]))
    hgttif = os.path.join(pubdir,track,frame,'metadata', frame+'.geo.hgt.tif')
    if not do_local:
        framedir = os.path.join(pubdir,track,frame)
        ifgdir = os.path.join(framedir,'interferograms')
    else:
        framedir = frame
        ifgdir = os.path.join(framedir,'GEOC')
    
    if not os.path.exists(framedir):
        print('the frame directory {} does not exist'.format(framedir))
        exit()
    if not os.path.exists(ifgdir):
        print('the provided directory {} does not exist'.format(ifgdir))
        exit()
    
    if not do_local:
        check_coh_file = os.path.join(framedir,'metadata', 'coherence_stats.txt')
        print('starting ifg check, using both line detection and timescan approaches')
        if os.path.exists(check_coh_file):
            os.remove(check_coh_file)
    
    
    badifgs_basic = []
    badifgs_stats = []
    badifgs_lines = []
    badifgs_dimensions = []
    for ifg in os.listdir(ifgdir):
        #check the lines in wrapped imgs
        #check only wrapped imgs:
        #wrap = os.path.join(ifgdir,ifg,ifg+'.geo.diff.png')
        #unwrap = os.path.join(ifgdir,ifg,ifg+'.geo.unw.png')
        wrap = os.path.join(ifgdir,ifg,ifg+'.geo.diff_pha.tif')
        unwrap = os.path.join(ifgdir,ifg,ifg+'.geo.unw.tif')
        cctif = os.path.join(ifgdir,ifg,ifg+'.geo.cc.tif')
        if not basic_check(os.path.join(ifgdir,ifg)):
            #if (not os.path.exists(wrap)) or (not os.path.exists(unwrap)) or (not os.path.exists(cctif)):
            flag = 1
            badifgs_basic.append(ifg)
        else:
            # older way checking just the png files...
            #flag = check_lines(wrap) #, unwrap)
            flag = check_lines_ifg_and_unw(wrap, unwrap)
            if flag == 1:
                badifgs_lines.append(ifg)
        if flag == 0:
            flag = check_dimensions(unwrap, hgttif)
            if flag == 1:
                badifgs_dimensions.append(ifg)
        if flag == 0:
            #check 
            stats = get_stats(os.path.join(ifgdir,ifg), ifg) 
            if not stats:
                flag = 1
                badifgs_stats.append(ifg)
            else:
                fid = open(check_coh_file, 'a')
                fid.write(stats)
                fid.close()
    #just print the bad ifgs now
    print('errors by basic check:')
    for ifg in badifgs_basic:
        print(ifg)
    print('errors by lines check:')
    for ifg in badifgs_lines:
        print(ifg)
    print('errors by dimensions check:')
    for ifg in badifgs_dimensions:
        print(ifg)
    print('errors by stats_check:')
    for ifg in badifgs_stats:
        print(ifg)
    
    badifgs = badifgs_stats + badifgs_dimensions + badifgs_lines + badifgs_basic
    
    if not do_local:
        #include also timescan approach
        badifgs_timescan = check_timescan(check_coh_file, coh_threshold)
        print('bad interferograms by timescan: ')
        for ifg in badifgs_timescan:
            print(ifg)
        if not keep_stats:
            if os.path.exists(check_coh_file):
                os.remove(check_coh_file)
        badifgs = badifgs+badifgs_timescan
    badepochs = []
    if badifgs:
        print('checking also for bad epochs')
        allifgs = os.listdir(ifgdir)
        epochs_master = []
        epochs_slave = []

        for ifg in badifgs:
            tmaster = ifg[0:8]
            tslave =  ifg[9:17]
            epochs_master.append(tmaster)
            epochs_slave.append(tslave)
        for m in set(epochs_master):
            if epochs_master.count(m) == len(glob.glob(ifgdir+'/{}_*'.format(m))):
                badepochs.append(m)
        for s in set(epochs_slave):
            if epochs_slave.count(s) == len(glob.glob(ifgdir+'/*_{}'.format(s))):
                badepochs.append(s)
        if badepochs:
            print('bad epochs detected:')
            for b in badepochs:
                print(b)
    if delete_ifgs and badifgs:
        print('deleting bad interferograms/epochs')
        if not do_local:
            for badifg in badifgs:
                os.system('remove_from_lics.sh {0} {1} 2>/dev/null'.format(frame,badifg))
            for badepoch in badepochs:
                os.system('remove_from_lics.sh {0} {1} 2>/dev/null'.format(frame,badepoch))
        else:
            for badifg in badifgs:
                try:
                    shutil.rmtree(os.path.join(ifgdir,badifg))
                    shutil.rmtree(os.path.join(framedir,'IFG',badifg))
                except:
                    print('warning, cannot delete ifg '+badifg)
            for badepoch in badepochs:
                try:
                    shutil.rmtree(os.path.join(framedir,'RSLC',badepoch))
                except:
                    print('warning, cannot delete epoch '+badepoch)
        print('regenerating the network plot')
        cmd = 'module load LiCSBAS; plot_network.py {0} {1} {2}'.format(framedir, os.path.join(framedir, 'metadata', 'network.png'), os.path.join(framedir, 'metadata', 'gaps.txt'))
        os.system(cmd)


if __name__ == "__main__":
    main(argv=sys.argv)
