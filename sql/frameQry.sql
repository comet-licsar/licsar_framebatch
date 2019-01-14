SELECT polygs.polyid_name AS "Frame", 
acq_img.acq_date AS "Master Date",
CASE WHEN slcB.slc_N IS NOT NULL THEN slcB.slc_N/slcA.slc_N ELSE 0 END AS "SLC Coverage",
CASE WHEN rslcB.rslc_N IS NOT NULL THEN rslcB.rslc_N/rslcA.rslc_N ELSE 0 END AS "RSLC Coverage",
CASE WHEN ifgB.ifg_N IS NOT NULL THEN ifgB.ifg_N/ifgA.ifg_N ELSE 0 END AS "IFG Coverage",
CASE WHEN unwB.unw_N IS NOT NULL THEN unwB.unw_N/unwA.unw_N ELSE 0 END AS "UNW Coverage",
polygs.active AS "Active"
FROM polygs 
INNER JOIN acq_img on acq_img.img_id = polygs.master_img_id 
INNER JOIN (
	SELECT polyid,count(slc.slc_id) AS "slc_N" 
	FROM slc 
	GROUP BY polyid
) AS slcA ON slcA.polyid = polygs.polyid 
LEFT OUTER JOIN (
	SELECT polyid,count(slc.slc_id) AS "slc_N" 
	FROM slc 
	WHERE slc_status=0 OR slc_status=-6
	GROUP BY polyid
) AS slcB ON slcB.polyid = polygs.polyid 
INNER JOIN (
	SELECT polyid,count(rslc.rslc_id) AS "rslc_N" 
	FROM rslc 
	GROUP BY polyid
) AS rslcA ON rslcA.polyid = polygs.polyid 
LEFT OUTER JOIN (
	SELECT polyid,count(rslc.rslc_id) AS "rslc_N" 
	FROM rslc 
	WHERE rslc_status=0
	GROUP BY polyid
) AS rslcB ON rslcB.polyid = polygs.polyid
INNER JOIN (
	SELECT polyid,count(ifg.ifg_id) AS "ifg_N" 
	FROM ifg 
	GROUP BY polyid
) AS ifgA ON ifgA.polyid = polygs.polyid 
LEFT OUTER JOIN (
	SELECT polyid,count(ifg.ifg_id) AS "ifg_N" 
	FROM ifg 
	WHERE ifg_status=0
	GROUP BY polyid
) AS ifgB ON ifgB.polyid = polygs.polyid 
INNER JOIN (
	SELECT polyid,count(unw.unw_id) AS "unw_N" 
	FROM unw 
	GROUP BY polyid
) AS unwA ON unwA.polyid = polygs.polyid 
LEFT OUTER JOIN (
	SELECT polyid,count(unw.unw_id) AS "unw_N" 
	FROM unw 
	WHERE unw_status=0
	GROUP BY polyid
) AS unwB ON unwB.polyid = polygs.polyid;
