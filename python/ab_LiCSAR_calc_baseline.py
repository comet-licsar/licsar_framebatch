#!/usr/bin/env python
from batchDBLib import get_polyid, get_built_rslcs, set_baseline, get_master
from batchMiscLib import create_basetab_from_date_series, calc_baseline_file, load_baseline_into_dataframe
import os
import sys


def main(argv):
    frameName = argv[1]
    polyID = get_polyid(frameName)
    try:
        cacheDir = os.environ['BATCH_CACHE_DIR']
    except KeyError as error:
        print('I required you to set your cache directory using the'\
                'enviroment variable BATCH_CACHE_DIR')
        raise error
    frameCache = os.path.join(cacheDir, frameName)
    mstrDate = get_master(frameName)

    rslcs = get_built_rslcs(polyID)
    create_basetab_from_date_series(frameCache, 'tab/base_tab', rslcs['acq_date'])
    calc_baseline_file(frameCache, 'tab/base_tab', mstrDate, 'bperp', 'itab')
    bPerp = load_baseline_into_dataframe(frameCache, 'bperp')
    set_baseline(polyID, bPerp)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
