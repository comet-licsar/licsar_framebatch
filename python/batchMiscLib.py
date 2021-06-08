################################################################################
# Imports
################################################################################
import numpy as np
import pandas as pd
import os
import subprocess

################################################################################
#Get perc unwrapped
################################################################################
def get_ifg_perc_unwrapd(dateA,dateB):
    unwExt = '.unw'
    ifgDir = 'IFG'
    ifgName = '{:%Y%m%d}_{:%Y%m%d}'.format(dateA,dateB)
    
    unwrpdPath = os.path.join(ifgDir,ifgName,ifgName+unwExt)
    
    unwrpdIfg = np.fromfile(unwrpdPath,dtype=np.float32).byteswap()
    notNanCount = np.sum(~np.isnan(unwrpdIfg))
    ifgSize = unwrpdIfg.shape[0]
    
    return float(notNanCount)/float(ifgSize)

################################################################################
#base tab
################################################################################
def create_basetab_from_date_series(frameDir,baseTab, dateSeries):
    rslcSeries = dateSeries.map(
            lambda dt: dt.strftime(frameDir+'/RSLC/%Y%m%d/%Y%m%d.rslc')
            )
    parSeries = dateSeries.map(
            lambda dt: dt.strftime(frameDir+'/RSLC/%Y%m%d/%Y%m%d.rslc.par')
            )
    tabDataFrame = pd.concat([rslcSeries, parSeries],axis=1)
    frameBaseTab = os.path.join(frameDir,baseTab)
    tabDataFrame.to_csv(frameBaseTab,header=False,index=False,sep='\t')

################################################################################
#Calculate baseline file
################################################################################
def calc_baseline_file(frameDir, baseTab, mstrDate, baselineFile, itabFile):
    mstrDatePar = os.path.join(
            frameDir,
            'RSLC/{0:%Y%m%d}/{0:%Y%m%d}.rslc.par'.format(mstrDate)
                              )
    frameBaseTab = os.path.join(frameDir,baseTab)
    frameBaselineFile = os.path.join(frameDir,baselineFile)
    frameItabFile = os.path.join(frameDir,itabFile)
    gamma_call = ['base_calc', frameBaseTab, mstrDatePar,
                  frameBaselineFile, frameItabFile, '0']
    subprocess.call(gamma_call)

################################################################################
#Load the baseline file into data
################################################################################
def load_baseline_into_dataframe(frameDir, baselineFile):
    frameBaselineFile = os.path.join(frameDir,baselineFile)
    baseLnDF = pd.read_table(
            frameBaselineFile, sep='\s+', header=None,
            names=['Gamma Index', 'Ref Date', 'Date', 'Bperp',
                   'Delta_T', 'Bperp 1', 'Bperp 2'],
            usecols=['Date', 'Bperp'], parse_dates=['Date']
                            )
    return baseLnDF
