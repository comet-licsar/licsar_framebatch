SELECT ifg.job_id AS "Job ID",
    polygs.polyid_name AS "Frame",
    DATE(imgA.acq_date) AS "Acquisition Date 1",
    DATE(imgB.acq_date) AS "Acquisition Date 2",
    jobs.user AS "User",
    ifg_status.description AS "IFG Status",
    jobs_status.description AS "Job Status",
    rstatA.description AS "RSLC 1 Status", 
    rstatB.description AS "RSLC 2 Status" 
    FROM ifg 
    INNER JOIN ifg_status ON ifg_status.ifg_status=ifg.ifg_status
    INNER JOIN jobs ON jobs.job_id=ifg.job_id
    INNER JOIN jobs_status ON jobs_status.job_status=jobs.job_status
    INNER JOIN acq_img AS imgA ON imgA.img_id=ifg.img_id_1 
    INNER JOIN acq_img AS imgB ON imgB.img_id=ifg.img_id_2 
    INNER JOIN rslc AS rslcA ON imgA.img_id=rslcA.img_id
    INNER JOIN rslc AS rslcB ON imgB.img_id=rslcB.img_id
    INNER JOIN rslc_status AS rstatA ON rstatA.rslc_status=rslcA.rslc_status
    INNER JOIN rslc_status AS rstatB ON rstatB.rslc_status=rslcB.rslc_status
    INNER JOIN polygs ON polygs.polyid=ifg.polyid
    WHERE polygs.active = TRUE;
