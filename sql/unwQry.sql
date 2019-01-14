SELECT unw.job_id AS "Job ID",
    polygs.polyid_name AS "Frame",
    DATE(imgA.acq_date) AS "Acquisition Date 1",
    DATE(imgB.acq_date) AS "Acquisition Date 2",
    jobs.user AS "User",
    unw_status.description AS "UNW Status",
    jobs_status.description AS "Job Status", 
    ifg_status.description AS "IFG Status",
    unw.unw_perc AS "Unwrap Percentage"
    FROM unw 
    INNER JOIN unw_status ON unw_status.unw_status=unw.unw_status
    INNER JOIN jobs ON jobs.job_id=unw.job_id
    INNER JOIN jobs_status ON jobs_status.job_status=jobs.job_status
    INNER JOIN acq_img AS imgA ON imgA.img_id=unw.img_id_1 
    INNER JOIN acq_img AS imgB ON imgB.img_id=unw.img_id_2 
    INNER JOIN ifg ON ifg.img_id_1=unw.img_id_1 AND ifg.img_id_2=unw.img_id_2 
    INNER JOIN ifg_status ON ifg_status.ifg_status=ifg.ifg_status
    INNER JOIN polygs ON polygs.polyid=unw.polyid
    WHERE polygs.active = TRUE;
