SELECT jobs.job_id as "Job ID",
    polygs.polyid_name as "Frame",
    jobs.time_started as "Start Time",
    jobs.time_finished as "End Time",
    jobs.user as "User",
    job_types.description as "Job Type",
    jobs_status.description as "Job Status",
	CASE 
	WHEN jobs.job_type=0 THEN
		(SELECT count(slc.slc_id) 
			FROM slc
			WHERE (slc.slc_status=0 OR slc.slc_status=-6) AND slc.job_id=jobs.job_id
		)/(SELECT count(slc.slc_id)
			FROM slc
			WHERE slc.job_id=jobs.job_id
		)
	WHEN jobs.job_type=1 THEN
		(SELECT count(rslc.rslc_id) 
			FROM rslc
			WHERE rslc.rslc_status=0 AND rslc.job_id=jobs.job_id
		)/(SELECT count(rslc.rslc_id)
			FROM rslc
			WHERE rslc.job_id=jobs.job_id
		)
	WHEN jobs.job_type=2 THEN
		(SELECT count(ifg.ifg_id) 
			FROM ifg
			WHERE ifg.ifg_status=0 AND ifg.job_id=jobs.job_id
		)/(SELECT count(ifg.ifg_id)
			FROM ifg
			WHERE ifg.job_id=jobs.job_id
		)
	WHEN jobs.job_type=3 THEN
		(SELECT count(unw.unw_id) 
			FROM unw
			WHERE unw.unw_status=0 AND unw.job_id=jobs.job_id
		)/(SELECT count(unw.unw_id)
			FROM unw
			WHERE unw.job_id=jobs.job_id
		)
	END AS "Coverage"
    FROM jobs 
    INNER JOIN polygs ON polygs.polyid=jobs.polyid 
    INNER JOIN job_types on jobs.job_type=job_types.job_type 
    INNER JOIN jobs_status on jobs.job_status=jobs_status.job_status
    WHERE polygs.active = TRUE;
