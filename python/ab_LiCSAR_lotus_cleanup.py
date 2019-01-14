#!/usr/bin/env python
from batchDBLib import set_job_finished, get_job_status
import sys

jobID = int(sys.argv[1])
jobStat = get_job_status(jobID)
if jobStat != 3:
    set_job_finished(jobID, 9)
