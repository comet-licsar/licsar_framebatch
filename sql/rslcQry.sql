SELECT rslc.job_id AS "Job ID",
    polygs.polyid_name AS "Frame",
    DATE(acq_img.acq_date) AS "Acquisition Date",
    jobs.user AS "User",
    rslc_status.description AS "Status",
    jobs_status.description AS "Job Status",
    slc_status.description AS "SLC Status",
    acq_img.bperp AS "Perpendicular Baseline"
    FROM rslc 
    INNER JOIN polygs ON polygs.polyid=rslc.polyid 
    INNER JOIN acq_img on acq_img.img_id=rslc.img_id
    INNER JOIN jobs ON jobs.job_id=rslc.job_id 
    INNER JOIN rslc_status ON rslc_status.rslc_status=rslc.rslc_status 
    INNER JOIN slc ON slc.img_id=rslc.img_id 
    INNER JOIN slc_status ON slc.slc_status=slc_status.slc_status 
    INNER JOIN jobs_status ON jobs_status.job_status=jobs.job_status
    WHERE polygs.active = TRUE;
