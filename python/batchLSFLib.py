#!/usr/bin/env python
import subprocess
import os


class NotLSFJob(Exception):
    def __repr__(self):
        return 'Not Valid LSF Job'


def get_job_id():
    try:
        jobid = os.environ['LSB_JOBID']
        jtype = 'LSB'
    except:
        jobid = os.environ['SLURM_JOBID']
        jtype = 'SLURM'
    if jobid:
        return int(jobid), jtype
    else:
        return NotLSFJob


def set_lotus_job_status(status):
    jobID, jtype = get_job_id()
    if jtype == 'SLURM':
        print(status)
    if jtype == 'LSB':
        subprocess.call(['bstatus', '-d', '"{}"'.format(status), str(jobID)])
