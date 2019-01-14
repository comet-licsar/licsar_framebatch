SELECT DISTINCT DATE(files.acq_date) AS "Acq Date"
FROM files
INNER JOIN files2bursts ON files2bursts.fid=files.fid
INNER JOIN polygs2bursts ON files2bursts.bid=polygs2bursts.bid
INNER JOIN polygs ON polygs.polyid=polygs2bursts.polyid
WHERE polygs.polyid={polyid};
