from configparser import ConfigParser
from contextlib import contextmanager
import os

################################################################################
# Setup Config
################################################################################
config = ConfigParser()
config.read(os.environ['FRAME_BATCH_CONFIG'])
