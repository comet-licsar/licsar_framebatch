#!/usr/bin/env python

import glob
import os
import sys
import argparse
import numpy as np
from datetime import datetime
import copy
import matplotlib.pyplot as plt
from matplotlib.dates import YearLocator, MonthLocator

'''Script to generate bperp plot with coherence values for each ifg; Nicholas Dodds, University of Oxford; March, 2018.'''

###########Input with parse, need to add help section!#######
def parse():
    parser = argparse.ArgumentParser(description='Generates perpendicular vs. temporal baseline plot including coherence for IFG network from output of LiCSAR framebatch. Also includes data on ESA Scihub vs output unwrapped IFGs comparison.')
    parser.add_argument('-i', action='store', default='bperp.list', dest='bperp_file', help='Bperp text file to be read for interferogram information. Output from base_calc (gamma) to create bperp relative to reference master. Default: bperp.list', type=str)
    parser.add_argument('-f', action='store', default='frame', dest='frame', help='LiCSAR framename string. Default: frame', type=str)
    parser.add_argument('-c', action='store', default='0', dest='coh', help='Coherence threshold, use same input as used for masking during unwrapping. Default: 0', type=str)
    inps = parser.parse_args()
    return inps

#########Start of the main program.
if __name__ == '__main__':
    inps = parse()

    ''' Run base_calc (gamma) to create bperp_aqs relative to reference master
    master=`ls geo/*.lt | xargs -I XX basename XX .lt`
    ls RSLC/*/*.rslc.mli > base_calc.list.rslc
    ls RSLC/*/*.rslc.mli.par > base_calc.list.rslc.par
    paste base_calc.list.rslc base_calc.list.rslc.par > base_calc.list; rm base_calc.list.rslc base_calc.list.rslc.par
    base_calc base_calc.list ./RSLC/${master}/${master}.rslc.mli.par bperp_aqs.list itab.list 0 0 ; rm base_calc.log base.out '''

    print('Coherence threshold (confirm with SNAPHU input): '+inps.coh)

    #function to convert date to date decimal
    def date2dec(dates):
        
        times = np.zeros(dates.shape, dtype=datetime)
        dates  = np.atleast_1d(dates)
        
        for k in range(len(dates)):
            try: 
                date1,date2 = dates[k]
                times[k,0] = datetime.strptime('{}'.format(date1),'%Y%m%d')
                times[k,1] = datetime.strptime('{}'.format(date2),'%Y%m%d')
            except:
                times[k] = datetime.strptime('{}'.format(dates[k]),'%Y%m%d')
        return times

    # to be run in frame processing directory
    cc_type = '.filt.cc'
    cc_ifgs = np.array(glob.glob('IFG/*/*'+cc_type))
    unw_ifgs = np.array(glob.glob('IFG/*/*.unw'))

    if unw_ifgs.shape != cc_ifgs.shape:
        print("Warning: number of unwrapped ifgs does not match number of coherence files.")

    # extract list of ifgs from names of unw ifgs in dir
    ifg_list = []
    for l in range(len(unw_ifgs)):
        ifg_list.append(os.path.splitext(os.path.basename(unw_ifgs[l]))[0])

    # convert to ifg acq dt objects  
    ifg_pairs = np.asarray([elem.strip().split('_') for elem in ifg_list])
    ifg_pairs = date2dec(ifg_pairs)

    # extract bp data
    print("Extracting BPerp data from output of base_calc.")
    bp_n, bp_mstr, bp_aq, bp_pb = np.loadtxt(inps.bperp_file, unpack=True, dtype='i,i,i,f')
    bp_aq = date2dec(bp_aq)

    # create perpendicular baseline for each acquisition lists (for image1 image2 separately)
    bp_pb_aq1 = np.zeros(ifg_pairs.shape[0])
    for k in range(len(ifg_pairs)):
        ind = np.argwhere(bp_aq==ifg_pairs[k,0])[0]
        bp_pb_aq1[k] = bp_pb[ind]
    
    bp_pb_aq2 = np.zeros(ifg_pairs.shape[0])
    for k in range(len(ifg_pairs)):
        ind = np.argwhere(bp_aq==ifg_pairs[k,1])[0]
        bp_pb_aq2[k] = bp_pb[ind]

    if (bp_pb_aq2.shape != bp_pb_aq1.shape) and (bp_pb_aq2.shape != ifg_pairs.shape[0]):
        print("warning: generated bperp vectors are not the same length as number of ifgs")

    mstr = glob.glob('geo/????????.hgt')
    mstr = os.path.splitext(os.path.basename(mstr[0]))[0]
    mstr_rslc = np.fromfile('RSLC/'+mstr+'/'+mstr+'.rslc.mli',dtype='>f4')
    mstr_rslc[np.where(mstr_rslc==0)] = np.nan
    mstr_rslc[np.where(mstr_rslc>=0)] = 1

    # read coherence values for each ifg
    print('Calculating unwrapped pixel perentage (this takes a while).')
    unw_pix_perc=np.zeros(len(ifg_list))

    # currently using unfiltered coherence, can change to .filt.cc
    for idx,ifg in enumerate(ifg_list):
        cc = np.fromfile('IFG/'+ifg+'/'+ifg+cc_type, dtype='>f4')
        cc[np.where(np.logical_or(cc==0,cc<=float(inps.coh)))] = np.nan
        unw_pix_perc[idx] = (np.nansum(cc)/np.nansum(mstr_rslc))*100
        print('Unwrapped pixel percentage for '+ifg+': '+str(unw_pix_perc[idx]))

    # plotting routines
    print('Plotting Bperp/Bt+Coherence.')
    plt.rcParams["figure.figsize"] = (30,15)
    font = {'family': 'sans-serif',
            'color':  'black',
            'weight': 'normal',
            'size': 24,
            }
    fig,ax = plt.subplots()
    years = YearLocator()
    months = MonthLocator()
    ax.set_xlabel('Sentinel-1 Acquisition Date',**font)
    ax.set_ylabel('Perpendicular Baseline (m)',**font)
    ax.xaxis.set_major_locator(years)
    ax.xaxis.set_minor_locator(months)

    # colorbar to change line colour according to unw pixel percentage
    cmap = plt.cm.ScalarMappable(cmap='hot_r', norm=plt.Normalize(vmin=0, vmax=100))
    cmap.set_array([])

    for l in range(len(ifg_pairs)):
        ax.plot([ifg_pairs[l,0], ifg_pairs[l,1]], [bp_pb_aq1[l],  bp_pb_aq2[l]], '-', color=cmap.to_rgba(unw_pix_perc[l]), zorder=-1)
    plt.colorbar(cmap, label='Unwrapped Pixel Percentage')
    font = {'family': 'sans-serif',
            'weight': 'normal',
            'size': 24,
            }
    plt.rc('font', **font)

    ax.scatter(bp_aq, bp_pb, color='black',zorder=1)
    ax.scatter((datetime.strptime(mstr,'%Y%m%d')), 0 , marker='o', color='red', edgecolors='black', s=80, zorder=2)

    # Plotting dots along bottom...
    print('Comparing SCIHUB/NLA/unwrapped ifg output lists.')

    # Scihub list
    scihub_dates = date2dec(np.loadtxt(inps.frame+'_scihub.list',comments="#",unpack=True,dtype='i'))
    print("Number of scihub acquisitions: ",len(scihub_dates))

    # ASF list
    asf_list = []
    with open(inps.frame+'_todown', 'r') as f:
        for line in f:
            if line[1:6] == 'neodc':
                bn = os.path.basename(line)[17:25]
                if bn not in asf_list:
                    asf_list.append(bn)
            elif line[1:4] == 'gws':
                bn = os.path.basename(line)[17:25]
                if bn not in asf_list:
                    asf_list.append(bn)
            else:
                print('WARNING: file path in ASF list in an unrecognised path.')
            
    asf_dates = date2dec(np.asarray(asf_list))
    print("Number of dates that needed files downloaded via ASF: ",len(asf_dates))
    
    ax.scatter(scihub_dates, (np.ones(len(scihub_dates))*(np.amin(bp_pb)-50)) ,facecolor='darkgrey',label='Available on Scihub')
    ax.scatter(asf_dates, (np.ones(len(asf_dates))*(np.amin(bp_pb)-40)) ,facecolor='lightcoral',label='Required ASF download')
    ax.scatter(bp_aq, (np.ones(len(bp_aq))*(np.amin(bp_pb)-30)) ,facecolor='deepskyblue',label='Processed to UNW')
    ax.legend(loc='upper right',fontsize=16)
    
    plt.savefig(inps.frame+'_bperp_unw.pdf', format='pdf')
    plt.savefig(inps.frame+'_bperp_unw.png', format='png')
    #plt.show()
