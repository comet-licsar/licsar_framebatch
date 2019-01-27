#!/usr/bin/env python

################################################################################
# Imports
################################################################################
import pandas as pd
import numbers
import pymysql
from batchDBLib import engine
from configLib import config
import gspread
#oauth2client libraries are deprecated!
#from oauth2client.service_account import ServiceAccountCredentials
#from google.oauth2.service_account import Credentials
from google.oauth2 import service_account

import os

sqlPath = config.get('Config','SQLPath')
jsonPath = config.get('Config','JsonPath')
################################################################################
# gspread Stuff
################################################################################
scope = ['https://spreadsheets.google.com/feeds', 
         'https://www.googleapis.com/auth/drive']
#creds = ServiceAccountCredentials.from_json_keyfile_name(
#        jsonPath+'/LiCS-Track.json', scope)
print('authenticating to google spreadsheets')
SERVICE_ACCOUNT_FILE=jsonPath+'/LiCS-Track.json'

creds = service_account.Credentials.from_service_account_file(
        SERVICE_ACCOUNT_FILE, scopes=scope)

from google.auth.transport.requests import AuthorizedSession
gc = gspread.Client(auth=creds)
gc.session = AuthorizedSession(creds)
#gc = gspread.authorize(creds)

################################################################################
# Dump dataframe to sheet
################################################################################
def dump_dataframe_to_sheet(df,sheetName):
    sht = wrkBk.worksheet(sheetName)
    if not df.empty and sht:
        sz = df.shape
        hdrs = sht.range(1,1,1,sz[1])
        for hdr in hdrs:
            hdr.value = df.columns[hdr.col-1]
        #clear the old values
        range_of_cells = sht.range('A2:J'+str(sht.row_count))
        for cell in range_of_cells:
            cell.value = ''
        sht.update_cells(range_of_cells)
        #and now put the new values here
        cells = sht.range(2,1,sz[0]+1,sz[1])
        for cell in cells:
            if isinstance(df.values[cell.row-2,cell.col-1],numbers.Number):
                if pd.isna(df.values[cell.row-2,cell.col-1]):
                    cell.value = 0
                else:
                    cell.value = df.values[cell.row-2,cell.col-1]
            else:
                cell.value = str(df.values[cell.row-2,cell.col-1])
        sht.update_cells(hdrs)
        sht.update_cells(cells)
    else:
        print("Warning either sheet or dataframe is empty")
# ################################################################################
# # Create SQL engine
# ################################################################################
# engine = create_engine(
    # 'mysql+pymysql://{usr}:{psswd}@{hst}/{dbname}'.format(
        # usr='lics',
        # psswd='T34mLiCS',
        # hst='192.168.3.7',
        # dbname='licsinfo_batch',
        # )
    # )

################################################################################
# Get Job Table
################################################################################
jobQryFile = open(sqlPath+'/jobQry.sql','r')
if jobQryFile:
    jobQry = jobQryFile.read()
    jobDatFrm = pd.read_sql_query(jobQry,engine)
else:
    print('Could not open job query file')

################################################################################
# Get SLC Table
################################################################################
slcQryFile = open(sqlPath+'/slcQry.sql', 'r')
if slcQryFile:
    slcQry = slcQryFile.read()
    slcDatFrm = pd.read_sql_query(slcQry,engine)
else:
    print('Could not open slc query file')

################################################################################
# Get RSLC Table
################################################################################
rslcQryFile = open(sqlPath+'/rslcQry.sql', 'r')
if rslcQryFile:
    rslcQry = rslcQryFile.read()
    rslcDatFrm = pd.read_sql_query(rslcQry,engine)
else:
    print('Could not open rslc query file')

################################################################################
# Get IFG Table
################################################################################
ifgQryFile = open(sqlPath+'/ifgQry.sql', 'r')
if ifgQryFile:
    ifgQry = ifgQryFile.read()
    ifgDatFrm = pd.read_sql_query(ifgQry,engine)
else:
    print('Could not open ifg query file')

################################################################################
# Get UNW Table
################################################################################
unwQryFile = open(sqlPath+'/unwQry.sql', 'r')
if unwQryFile:
    unwQry = unwQryFile.read()
    unwDatFrm = pd.read_sql_query(unwQry,engine)
else:
    print('Could not open unw query file')

################################################################################
# Get Frame Table
################################################################################
frameQryFile = open(sqlPath+'/frameQry.sql', 'r')
if frameQryFile:
    frameQry = frameQryFile.read()
    frameDatFrm = pd.read_sql_query(frameQry,engine)
else:
    print('Could not open unw query file')

################################################################################
# Setup Google workbook
################################################################################
gsUrl = config.get('Sheets','Url')
wrkBk = gc.open_by_url(gsUrl)

################################################################################
# Setup sheets
################################################################################
print('exporting from database')
dump_dataframe_to_sheet(jobDatFrm,'Jobs')
dump_dataframe_to_sheet(slcDatFrm,'SLC')
dump_dataframe_to_sheet(rslcDatFrm,'RSLC')
dump_dataframe_to_sheet(ifgDatFrm,'IFG')
dump_dataframe_to_sheet(unwDatFrm,'UNW')
dump_dataframe_to_sheet(frameDatFrm,'Frames')
print('done')
