#!/bin/bash

# Set LiCSAR Path robustly
export LiCSAR_framebatch="$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)"

# Remove previous entries containing 'licsar_framebatch_testing' from PATH and PYTHONPATH
export PATH=$(echo "$PATH" | awk -v RS=: -v ORS=: '$0 !~ /licsar_framebatch_testing/' | sed 's/:$//')
export PYTHONPATH=$(echo "$PYTHONPATH" | awk -v RS=: -v ORS=: '$0 !~ /licsar_framebatch_testing/' | sed 's/:$//')

# Add the new LiCSAR_framebatch paths
export PATH="$LiCSAR_framebatch/bin:$LiCSAR_framebatch/python:$PATH"
export PYTHONPATH="$LiCSAR_framebatch/python:$PYTHONPATH"

# # Source external bash library explicitly (if needed)
# source "/gws/smf/j04/nceo_geohazards/software/licsar_proc_testing/lib/LiCSAR_bash_lib.sh"
