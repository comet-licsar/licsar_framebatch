SELECT slc.job_id AS "Job ID",
    polygs.polyid_name AS "Frame",
    DATE(acq_img.acq_date) AS "Acquisition Date",
    jobs.user AS "User",
    slc_status.description AS "Status",
    jobs_status.description AS "Job Status" 
    FROM slc 
    INNER JOIN polygs ON polygs.polyid=slc.polyid 
    INNER JOIN acq_img on acq_img.img_id=slc.img_id
    INNER JOIN jobs ON jobs.job_id=slc.job_id 
    INNER JOIN slc_status ON slc_status.slc_status=slc.slc_status 
    INNER JOIN jobs_status ON jobs_status.job_status=jobs.job_status
    WHERE polygs.active = TRUE;
