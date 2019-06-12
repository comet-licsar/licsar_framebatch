#!/usr/bin/env python
import subprocess
import os


class NotLSFJob(Exception):
    def __repr__(self):
        return 'Not Valid LSF Job'


def get_lotus_job_id():
    try:
        return int(os.environ['LSB_JOBID'])
    except KeyError:
        raise NotLSFJob


def set_lotus_job_status(status):
    jobID = get_lotus_job_id()
    subprocess.call(['bstatus', '-d', '"{}"'.format(status), str(jobID)])
