from configparser import SafeConfigParser
from contextlib import contextmanager
import os

################################################################################
# Setup Config
################################################################################
config = SafeConfigParser()
config.read(os.environ['FRAME_BATCH_CONFIG'])
