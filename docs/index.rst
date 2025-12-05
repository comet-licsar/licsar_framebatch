LiCSAR Framebatch
=================

This is a toolset combining LiCSAR core codes (licsar_proc) with the LiCSInfo database, as described in https://www.mdpi.com/2072-4292/12/15/2430/htm .
It contains set of tools to be used by COMET users with access to JASMIN computing facility. The tools help process Sentinel-1 data systematically to generate
standard LiCSAR interferometric products. The solution relies on an extended LiCSInfo database that would link the files to process with the processing jobs,
keeping control within the automatic processing using ``licsar_make_frame.sh`` and related tools.

This documentation is still only a stab. But you may check the 'help' of following key scripts to learn more:

``licsar_make_frame.sh``

``framebatch_update_frame.sh``

``framebatch_postproc_coreg.sh``

(dev comments)
--------------
pandf.sh - check on your disk (and NLA) quotas status